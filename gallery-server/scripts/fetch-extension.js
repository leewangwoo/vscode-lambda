#!/usr/bin/env node
/**
 * VS Code 마켓플레이스에서 특정 플랫폼의 VSIX를 다운로드합니다.
 *
 * 기존 /vspackage URL은 호출한 머신의 플랫폼(또는 web) VSIX를 반환해서
 * Windows 클라이언트에 설치 불가능한(@web, darwin-x64) 확장이 올라가는
 * 문제가 있었습니다. 이 스크립트는 extensionquery API로 먼저 정확한
 * win32-x64 (또는 universal) VSIX 다운로드 URL을 얻어서 받습니다.
 *
 * 사용법:
 *   node fetch-extension.js <publisher.name> [output.vsix] [targetPlatform]
 *
 * 예:
 *   node fetch-extension.js ms-python.python python.vsix win32-x64
 *   node fetch-extension.js redhat.vscode-yaml yaml.vsix
 *
 * targetPlatform 생략 시: win32-x64 우선, 없으면 universal.
 */

const https = require("https");
const fs = require("fs");
const zlib = require("zlib");
const path = require("path");

const extId = process.argv[2];
const outPath = process.argv[3] || `${extId}.vsix`;
const wantPlatform = process.argv[4] || "win32-x64";

if (!extId) {
    console.error("Usage: node fetch-extension.js <publisher.name> [output.vsix] [targetPlatform]");
    process.exit(1);
}

function fetchJson(url, body) {
    return new Promise((resolve, reject) => {
        const req = https.request(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Accept": "application/json;api-version=6.1-preview.1",
            },
        }, (res) => {
            const chunks = [];
            res.on("data", (c) => chunks.push(c));
            res.on("end", () => {
                try {
                    resolve(JSON.parse(Buffer.concat(chunks).toString()));
                } catch (e) {
                    reject(new Error(`JSON parse failed (HTTP ${res.statusCode})`));
                }
            });
        });
        req.on("error", reject);
        req.write(body);
        req.end();
    });
}

function downloadFile(url, dest) {
    return new Promise((resolve, reject) => {
        const file = fs.createWriteStream(dest);
        https.get(url, (res) => {
            // Follow redirects
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                file.close();
                fs.unlinkSync(dest);
                return resolve(downloadFile(res.headers.location, dest));
            }
            if (res.statusCode !== 200) {
                file.close();
                fs.unlinkSync(dest);
                return reject(new Error(`Download failed: HTTP ${res.statusCode}`));
            }
            // Check if gzipped
            const isGzip = (res.headers["content-encoding"] || "").includes("gzip");
            const encoding = url.endsWith(".gz") || isGzip ? "gzip" : "none";
            if (encoding === "gzip") {
                const gunzip = zlib.createGunzip();
                res.pipe(gunzip).pipe(file);
            } else {
                res.pipe(file);
            }
            file.on("finish", () => {
                file.close();
                resolve(fs.statSync(dest).size);
            });
        }).on("error", (err) => {
            fs.unlinkSync(dest);
            reject(err);
        });
    });
}

(async () => {
    console.log(`Querying marketplace for ${extId} (${wantPlatform})...`);

    // Step 1: Query the gallery API for the extension's versions + VSIX URLs.
    const queryBody = JSON.stringify({
        filters: [{
            criteria: [
                { filterType: 7, value: extId },
                { filterType: 8, value: "Microsoft.VisualStudio.Code" },
            ],
        }],
        flags: 914, // IncludeVersionProperties = files + targetPlatform
    });

    let data;
    try {
        data = await fetchJson("https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery", queryBody);
    } catch (e) {
        console.error(`[FAIL] Gallery query failed: ${e.message}`);
        process.exit(1);
    }

    const exts = data.results[0].extensions || [];
    const ext = exts.find(e => `${e.publisher.publisherName}.${e.extensionName}`.toLowerCase() === extId.toLowerCase());
    if (!ext) {
        console.error(`[FAIL] Extension ${extId} not found`);
        process.exit(1);
    }

    // Step 2: Pick the best version — prefer the requested platform, then universal.
    const versions = ext.versions || [];
    let chosen = versions.find(v => (v.targetPlatform || "universal") === wantPlatform);
    if (!chosen) {
        chosen = versions.find(v => (v.targetPlatform || "universal") === "universal");
    }
    if (!chosen) {
        console.error(`[FAIL] No ${wantPlatform} or universal version for ${extId}`);
        console.error("  Available platforms:");
        versions.forEach(v => console.error(`    ${(v.targetPlatform || "universal")}: v${v.version}`));
        process.exit(1);
    }

    const tp = chosen.targetPlatform || "universal";
    const version = chosen.version;

    // Step 3: Get the VSIX download URL from the files array.
    const vsixFile = (chosen.files || []).find(f => f.assetType === "Microsoft.VisualStudio.Services.VSIXPackage");
    if (!vsixFile) {
        console.error(`[FAIL] No VSIX file in version ${version}`);
        process.exit(1);
    }

    console.log(`  Found: v${version} [${tp}]`);

    // Step 4: Download the VSIX.
    console.log(`  Downloading from ${vsixFile.source.substring(0, 80)}...`);
    try {
        const size = await downloadFile(vsixFile.source, outPath);
        console.log(`  [OK] Downloaded ${(size / 1024 / 1024).toFixed(1)} MB -> ${path.basename(outPath)} [${tp}]`);
    } catch (e) {
        console.error(`  [FAIL] Download failed: ${e.message}`);
        process.exit(1);
    }
})();
