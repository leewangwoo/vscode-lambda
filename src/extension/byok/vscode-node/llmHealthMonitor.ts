/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import { commands, MarkdownString, StatusBarAlignment, StatusBarItem, ThemeColor, window, workspace } from 'vscode';
import { Disposable, toDisposable } from '../../../util/vs/base/common/lifecycle';

const POLL_INTERVAL_MS = 10_000;
const FETCH_TIMEOUT_MS = 15_000;

interface MonitorHealth {
	total: number;
	available: number;
	busy: number;
	offline: number;
}

interface MonitorStatus {
	instances: Array<{
		name: string;
		model: string;
		url: string;
		status: 'available' | 'busy' | 'offline';
		busy_slots: number;
	}>;
	summary: MonitorHealth;
	updated_at: string;
}

/**
 * Status bar item that polls the LiteLLM proxy `/health` endpoint and shows
 * how many LLM instances are available. Helps users understand when the LLM
 * is busy processing another request.
 *
 * Uses pure VS Code API — no DI needed. Registered directly in activate().
 */
export class LLMHealthMonitor extends Disposable {

	private readonly _statusBarItem: StatusBarItem;
	private readonly _outputChannel: ReturnType<typeof window.createOutputChannel>;
	private _pollingHandle: ReturnType<typeof setInterval> | undefined;
	private _isWindowFocused = true;
	private _lastHealth: MonitorHealth | undefined;
	private _lastStatus: MonitorStatus | undefined;
	private _lastError: string | undefined;
	private _slowResponse = false;

	constructor() {
		super();
		this._outputChannel = window.createOutputChannel('Lambda LLM Health');
		this._register(this._outputChannel);

		this._statusBarItem = window.createStatusBarItem('lambda.llmHealth', StatusBarAlignment.Right, -999);
		this._statusBarItem.name = 'Lambda LLM Health';
		this._statusBarItem.command = 'lambda.llmHealth.showDetails';
		this._register(this._statusBarItem);

		this._register(commands.registerCommand('lambda.llmHealth.showDetails', () => this._showDetails()));

		this._register(workspace.onDidChangeConfiguration(e => {
			if (e.affectsConfiguration('github.copilot.chat.byok.customoai')) {
				this._startPolling();
			}
		}));

		this._register(window.onDidChangeWindowState(state => {
			this._isWindowFocused = state.focused;
			if (state.focused) {
				this._poll();
			}
		}));

		this._register({ dispose: () => this._stopPolling() });

		this._startPolling();
		console.log('[LAMBDA-HEALTH] LLMHealthMonitor initialized');
	}

	private _getEndpoint(): { url: string; key: string } | undefined {
		const config = workspace.getConfiguration('github.copilot.chat.byok.customoai');
		const url = config.get<string>('url');
		if (!url) {
			return undefined;
		}
		const key = config.get<string>('key') || 'dummy-key';
		// Parse the customoai URL to extract the hostname.
		// Monitor runs on port 8090 (or 18090 for local) of the same host.
		try {
			const parsed = new URL(url);
			const hostname = parsed.hostname;
			const isLocal = hostname === 'localhost' || hostname === '127.0.0.1';
			const monitorPort = isLocal ? 18090 : 8090;
			return { url: `http://${hostname}:${monitorPort}/health`, key };
		} catch {
			return undefined;
		}
	}

	private _startPolling(): void {
		this._stopPolling();

		const endpoint = this._getEndpoint();
		console.log(`[LAMBDA-HEALTH] startPolling endpoint=${endpoint ? endpoint.url : 'none'}`);
		if (!endpoint) {
			this._statusBarItem.hide();
			return;
		}

		this._poll();

		this._pollingHandle = setInterval(() => {
			if (!this._isWindowFocused) {
				return;
			}
			this._poll();
		}, POLL_INTERVAL_MS);
	}

	private _stopPolling(): void {
		if (this._pollingHandle) {
			clearInterval(this._pollingHandle);
			this._pollingHandle = undefined;
		}
	}

	private async _poll(): Promise<void> {
		const endpoint = this._getEndpoint();
		if (!endpoint) {
			this._statusBarItem.hide();
			return;
		}

		try {
			const controller = new AbortController();
			const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

			const response = await globalThis.fetch(endpoint.url, {
				method: 'GET',
				signal: controller.signal,
			});
			clearTimeout(timeout);

			if (!response.ok) {
				throw new Error(`HTTP ${response.status}`);
			}

			this._lastHealth = await response.json() as MonitorHealth;
			this._lastError = undefined;

			// Also fetch detailed status for tooltip/output
			try {
				const statusResp = await globalThis.fetch(endpoint.url.replace('/health', '/status'), {
					signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
				});
				if (statusResp.ok) {
					this._lastStatus = await statusResp.json() as MonitorStatus;
				}
			} catch {
				// Detailed status is optional
			}

			this._updateStatusBar();
		} catch (err) {
			this._lastError = err instanceof Error ? err.message : String(err);
			this._updateStatusBar();
		}
	}

	private _updateStatusBar(): void {
		if (this._lastError) {
			this._statusBarItem.text = '$(error) LLM: 모니터 연결 실패';
			this._statusBarItem.tooltip = `LLM 모니터 연결 실패: ${this._lastError}\n모니터 서비스(포트 8090)가 실행 중인지 확인하세요.`;
			this._statusBarItem.backgroundColor = new ThemeColor('statusBarItem.errorBackground');
			this._statusBarItem.show();
			return;
		}

		if (!this._lastHealth) {
			this._statusBarItem.text = '$(loading~spin) LLM: 확인 중...';
			this._statusBarItem.tooltip = 'LLM 서버 상태를 확인하는 중입니다.';
			this._statusBarItem.backgroundColor = undefined;
			this._statusBarItem.show();
			return;
		}

		const { total, available, busy, offline } = this._lastHealth;
		this._statusBarItem.backgroundColor = undefined;

		if (offline === total) {
			this._statusBarItem.text = '$(error) LLM: 모두 오프라인';
			this._statusBarItem.backgroundColor = new ThemeColor('statusBarItem.errorBackground');
		} else if (busy > 0 && available === 0) {
			this._statusBarItem.text = `$(watch~spin) LLM: 전부 처리 중 (${busy})`;
			this._statusBarItem.backgroundColor = new ThemeColor('statusBarItem.warningBackground');
		} else if (busy > 0) {
			this._statusBarItem.text = `$(pulse) LLM: ${available} 가능 / ${busy} 처리중`;
			this._statusBarItem.backgroundColor = new ThemeColor('statusBarItem.warningBackground');
		} else if (offline > 0) {
			this._statusBarItem.text = `$(warning) LLM: ${available} 가능 / ${offline} 오프라인`;
		} else {
			this._statusBarItem.text = `$(check-all) LLM: ${available} 사용 가능`;
		}

		// Build tooltip with per-instance details
		const tooltip = new MarkdownString();
		tooltip.isTrusted = true;
		tooltip.appendMarkdown(`**LLM 서버 상태**\n\n`);
		tooltip.appendMarkdown(`✅ 사용 가능: **${available}** | ⏳ 처리 중: **${busy}** | ❌ 오프라인: **${offline}**\n\n`);
		if (this._lastStatus?.instances?.length) {
			for (const inst of this._lastStatus.instances) {
				const icon = inst.status === 'available' ? '✅' : inst.status === 'busy' ? '⏳' : '❌';
				tooltip.appendMarkdown(`- ${icon} \`${inst.name}\` (${inst.model})\n`);
			}
		}
		tooltip.appendMarkdown(`\n*클릭하여 상세 정보 보기*`);
		this._statusBarItem.tooltip = tooltip;
		this._statusBarItem.show();
	}

	private _showDetails(): void {
		this._outputChannel.clear();
		this._outputChannel.appendLine('=== Lambda LLM Health Status ===');
		this._outputChannel.appendLine(`Time: ${new Date().toLocaleString()}`);
		this._outputChannel.appendLine('');

		if (this._lastError) {
			this._outputChannel.appendLine(`❌ Error: ${this._lastError}`);
		} else if (this._lastHealth) {
			this._outputChannel.appendLine(`✅ Available: ${this._lastHealth.available}`);
			this._outputChannel.appendLine(`⏳ Busy: ${this._lastHealth.busy}`);
			this._outputChannel.appendLine(`❌ Offline: ${this._lastHealth.offline}`);
			this._outputChannel.appendLine('');

			if (this._lastStatus?.instances?.length) {
				this._outputChannel.appendLine('--- Instances ---');
				for (const inst of this._lastStatus.instances) {
					const icon = inst.status === 'available' ? '✅' : inst.status === 'busy' ? '⏳' : '❌';
					this._outputChannel.appendLine(`  ${icon} ${inst.name} (${inst.model}) [${inst.url}] busy_slots=${inst.busy_slots}`);
				}
			}
		} else {
			this._outputChannel.appendLine('⏳ Checking...');
		}

		this._outputChannel.show();
	}

	public markSlowResponse(): void {
		this._slowResponse = true;
		this._updateStatusBar();
		setTimeout(() => {
			this._slowResponse = false;
			this._updateStatusBar();
		}, 30_000);
	}
}
