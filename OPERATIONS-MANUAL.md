# Lambda 폐쇄망 AI 개발 환경 - 운영 매뉴얼

## 1. 시스템 개요

### 1.1 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                     폐쇄망 (Internal Network)                  │
│                                                               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │  LLM Server  │    │ Gallery Srv  │    │  devpi Srv   │    │
│  │100.252.201.200│   │100.252.201.200│   │100.252.201.200│    │
│  │              │    │   :8443      │    │   :3141      │    │
│  │ ┌──────────┐ │    │  (HTTPS)     │    │              │    │
│  │ │llama.cpp │ │    └──────────────┘    └──────────────┘    │
│  │ │ :8084    │ │                                              │
│  │ │ :8085    │ │    ┌──────────────┐                         │
│  │ └──────────┘ │    │   LiteLLM    │                         │
│  │      ↓       │    │   :8088      │                         │
│  │ ┌──────────┐ │    │  (Proxy v2)  │                         │
│  │ │ LiteLLM  │ │    └──────────────┘                         │
│  │ │  :8088   │ │              ↓                               │
│  │ └──────────┘ │    ┌──────────────┐                         │
│  │      ↓       │    │LLM Monitor   │                         │
│  │ ┌──────────┐ │    │   :8090      │                         │
│  │ │ Monitor  │ │    └──────────────┘                         │
│  │ │  :8090   │ │                                              │
│  │ └──────────┘ │                                              │
│  └──────────────┘                                              │
│         ↕                       ↕                              │
│  ┌──────────────────────────────────────┐                     │
│  │      사용자 PC (Windows 10/11)        │                     │
│  │                                      │                     │
│  │  VS Code + Lambda Extension (999.46) │                     │
│  │  - CustomOAI → LiteLLM :8088         │                     │
│  │  - LLM Health Monitor (상태 표시줄)    │                     │
│  │  - Reasoning 실시간 스트리밍          │                     │
│  │  - insertEdit 도구 (폐쇄망 직접 수정)  │                     │
│  └──────────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 구성 요소

| 구성 요소 | 포트 | 용도 | 기술 스택 |
|----------|------|------|----------|
| llama.cpp (qwen27) | 8085 | Qwen3.6-27B Dense 모델 | Docker + GPU |
| llama.cpp (qwen35) | 8084 | Qwen3.6-35B MoE 모델 | Docker + GPU |
| LiteLLM v2 | 8088 | LLM 프록시 / 로드밸런서 | LiteLLM 1.93.0 |
| LLM Monitor | 8090 | 인스턴스 실시간 상태 모니터링 | FastAPI |
| Gallery Server | 8443 | VS Code 확장 갤러리 | code-marketplace + Caddy |
| devpi | 3141 | Python 패키지 서버 | devpi-server |

### 1.3 모델 정보

| 모델 | 타입 | 용도 |
|------|------|------|
| Qwen3.6-27B-Q4_K_M | Dense | 일반 코딩/채팅 |
| Qwen3.6-35B-A3B-UD-Q4_K_M | MoE | 복잡한 추론/코딩 |

---

## 2. 서버 운영

### 2.1 LLM 서버 관리

#### 전체 서비스 시작/중지

```bash
cd /path/to/litellm_config/SLTPRODL01

# 전체 시작
docker compose -f docker-compose-v2.yaml up -d

# 전체 중지
docker compose -f docker-compose-v2.yaml down

# 특정 서비스만 재시작
docker compose -f docker-compose-v2.yaml restart litellm
docker compose -f docker-compose-v2.yaml restart llm-monitor

# 상태 확인
docker compose -f docker-compose-v2.yaml ps
docker compose -f docker-compose-v2.yaml logs -f --tail=50
```

#### 서비스별 로그 확인

```bash
# LiteLLM 로그
docker compose -f docker-compose-v2.yaml logs -f litellm

# LLM Monitor 로그
docker compose -f docker-compose-v2.yaml logs -f llm-monitor

# llama.cpp 로그
docker compose -f docker-compose-v2.yaml logs -f qwen27-5
docker compose -f docker-compose-v2.yaml logs -f qwen35-4
```

### 2.2 LiteLLM 설정 변경

LiteLLM 설정 파일 위치: `litellm_config/SLTPRODL01/litellm-config-v2.yaml`

#### 모델 추가/제거

```yaml
model_list:
  # 새 모델 추가 예시
  - model_name: qwen27
    litellm_params:
      model: openai/qwen27
      api_base: http://새서버IP:포트/v1
      api_key: none
```

설정 변경 후:
```bash
docker compose -f docker-compose-v2.yaml restart litellm
```

#### 마스터 키 변경

`litellm-config-v2.yaml`에서:
```yaml
general_settings:
  master_key: 새키값
```

`docker-compose-v2.yaml`에서:
```yaml
environment:
  - LITELLM_MASTER_KEY=새키값
```

VS Code 설정에서도 동일한 키로 변경:
```json
"github.copilot.chat.byok.customoai": {
    "url": "http://100.252.201.200:8088/v1",
    "key": "새키값"
}
```

### 2.3 LLM Monitor 설정 변경

설정 파일 위치: `litellm_config/SLTPRODL01/monitor-config.py`

인스턴스 목록 변경:
```python
LLM_INSTANCES = [
    {"name": "새인스턴스명", "model": "qwen27", "url": "http://IP:포트"},
    # ...
]
```

설정 변경 후:
```bash
docker compose -f docker-compose-v2.yaml restart llm-monitor
```

### 2.4 Gallery Server 관리

```bash
cd /path/to/gallery-server

# 시작
docker compose up -d

# 중지
docker compose down

# 로그
docker compose logs -f

# 확장 업로드
curl -k -X POST -H "X-Upload-Token: lambda-upload" \
  -F "file=@확장파일.vsix" \
  https://100.252.201.200:8443/upload
```

### 2.5 devpi 관리

```bash
cd /path/to/devpi

# 시작
docker compose up -d

# 패키지 동기화 (온라인 PC에서)
./scripts/sync-packages.bat
```

---

## 3. 사용자 PC 설정

### 3.1 신규 PC 설치

1. 설치 파일을 PC로 전달:
   - `lambda-chat-deploy/install.bat`
   - `lambda-chat-deploy/configure-vscode.ps1`
   - `lambda-chat-deploy/configure-pip.ps1`
   - `lambda-chat-deploy/dummy-key`
   - `lambda-chat-deploy/README.txt`

2. `install.bat` 실행 (관리자 권한 불필요)

3. VS Code 실행 후:
   - Extensions 탭에서 `lambda` 검색 → Install
   - "Enable AI Features" 클릭
   - 채팅 모델 선택기에서 Qwen 모델 선택

### 3.2 확장 업데이트

```bash
# update.bat 실행 (내부망 갤러리에서 자동 다운로드)
lambda-chat-deploy\update.bat
```

### 3.3 VS Code 설정

VS Code Settings (Ctrl+,) → `customoai` 검색:

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `github.copilot.chat.byok.customoai.url` | `http://100.252.201.200:8088/v1` | LiteLLM 프록시 주소 |
| `github.copilot.chat.byok.customoai.key` | `dummy-key` | 인증 키 |
| `github.copilot.chat.byok.customoai.maxTokens` | `4096` | 최대 응답 토큰 수 |

### 3.4 문제 해결

#### 모델이 안 보이는 경우
1. VS Code 완전 종료 후 재시작
2. `reset-vscode.bat` 실행 후 `install.bat` 재실행
3. Settings에서 customoai URL/Key 확인

#### 응답이 느린 경우
1. 상태 표시줄 확인 (`✅ LLM: N 사용 가능`)
2. `⏳ 처리 중` 표시면 다른 사용자가 LLM 사용 중 → 대기
3. Ask 모드 사용 (도구 없이 응답 → 더 빠름)

#### 응답이 짤리는 경우
- Settings에서 `maxTokens` 값을 8192 또는 16384로 증가

#### 코드 수정이 안 되는 경우
- Agent 모드 사용 (Ask 모드는 코드 수정 불가)
- 확장 버전 999.46.0 이상 확인

---

## 4. 확장 빌드 및 배포

### 4.1 빌드 환경 요구사항

- Node.js 22+
- npm 9+
- 인터넷 연결 (의존성 설치용)

### 4.2 빌드 절차

```bash
cd C:\GitHub\vscode-lambda

# 1. 의존성 확인
npm install

# 2. package.json scripts 복구 (필요시)
node -e "
const fs=require('fs');
const orig=JSON.parse(fs.readFileSync('scratch/orig-package.json','utf8'));
const curr=JSON.parse(fs.readFileSync('./package.json','utf8'));
curr.scripts=orig.scripts;
fs.writeFileSync('./package.json',JSON.stringify(curr,null,2)+'\n');
"

# 3. 버전 번호 변경
# package.json에서 version 수정

# 4. 빌드
npm run build

# 5. 바이너리 파일 복사 (tree-sitter wasm, tiktoken)
# 최초 1회만: 기존 VSIX에서 추출
unzip -o copilot-chat-999.15.0.vsix "extension/dist/*.wasm" "extension/dist/*.tiktoken" -d /tmp/vsix-extract
cp /tmp/vsix-extract/extension/dist/*.wasm dist/
cp /tmp/vsix-extract/extension/dist/*.tiktoken dist/

# 6. VSIX 패키징
npx vsce package --no-git-tag-version --no-dependencies --allow-package-secrets sendgrid

# 7. 갤러리 업로드
curl -k -H "Expect:" -X POST -H "X-Upload-Token: lambda-upload" \
  -F "file=@copilot-chat-버전.vsix" \
  https://100.252.201.200:8443/upload

# 8. update.bat 버전 번호 수정
# lambda-chat-deploy/update.bat에서 LAMBDA_EXT_VERSION 변경
```

### 4.3 주의사항

- `npm run build` 후 `dist/` 폴더에 `.wasm`, `.tiktoken` 파일이 유지되어야 함
- `rm -rf dist` 후 빌드하면 바이너리 파일이 사라지므로 주의
- `package.json`의 scripts가 사라지는 현상이 발생하면 `scratch/orig-package.json`에서 복구
- VSIX 크기가 ~8MB 이하면 바이너리 파일이 누락된 것 (정상: ~8.4MB)

---

## 5. LiteLLM 이미지 빌드 (폐쇄망용)

### 5.1 빌드 환경

- Docker
- 인터넷 연결 (이미지 pull용)

### 5.2 빌드 절차

```bash
cd litellm_config/airgap

# Dockerfile, tiktoken 파일 확인
ls -la
# Dockerfile, cl100k_base.tiktoken, o200k_base.tiktoken

# 빌드
docker build -t litellm-airgap-v2:latest .

# 이미지 내보내기 (폐쇄망 전송용)
docker save litellm-airgap-v2:latest -o litellm-airgap-v2.tar
```

### 5.3 서버에 배포

```bash
# tar 파일을 서버로 전송 후
docker load -i litellm-airgap-v2.tar
docker images | grep litellm-airgap-v2
```

---

## 6. LLM Monitor 이미지 빌드

```bash
cd litellm_config/llm-monitor

# 빌드
docker build -t llm-monitor:latest .

# 내보내기
docker save llm-monitor:latest -o llm-monitor.tar

# 서버 배포
docker load -i llm-monitor.tar
```

---

## 7. 모니터링

### 7.1 상태 확인 명령어

```bash
# LiteLLM health (전체 인스턴스)
curl -s http://100.252.201.200:8088/health -H "Authorization: Bearer dummy-key"

# LLM Monitor (상세)
curl -s http://100.252.201.200:8090/status | python3 -m json.tool

# LLM Monitor (요약)
curl -s http://100.252.201.200:8090/health

# 모델 목록
curl -s http://100.252.201.200:8088/v1/models -H "Authorization: Bearer dummy-key"

# 개별 인스턴스 슬롯 상태
curl -s http://100.252.201.200:8085/slots
```

### 7.2 VS Code 상태 표시줄

하단 상태 표시줄 우측에 표시:

| 표시 | 의미 |
|------|------|
| `✅ LLM: 10 사용 가능` | 모든 인스턴스 대기 중 |
| `⏳ LLM: 9 가능 / 1 처리중` | 1개 인스턴스가 요청 처리 중 |
| `⚠️ LLM: 8 가능 / 2 오프라인` | 2개 인스턴스 응답 없음 |
| `❌ LLM: 모두 오프라인` | 모든 인스턴스 다운 |

### 7.3 Docker 리소스 모니터링

```bash
# 컨테이너 리소스 사용량
docker stats

# 디스크 사용량
docker system df

# 이미지 정리 (주의)
docker image prune -a
```

---

## 8. 백업 및 복구

### 8.1 백업 항목

| 항목 | 위치 | 방법 |
|------|------|------|
| LiteLLM 설정 | `litellm_config/SLTPRODL01/` | git 또는 파일 복사 |
| Gallery 데이터 | Docker volume `gallery-data` | `docker run --rm -v gallery-data:/data -v $(pwd):/backup alpine tar czf /backup/gallery-data.tar.gz /data` |
| devpi 데이터 | Docker volume | 위와 동일 |
| VS Code 확장 | Gallery 서버 | VSIX 파일 보관 |

### 8.2 복구 절차

```bash
# Gallery 데이터 복구
docker run --rm -v gallery-data:/data -v $(pwd):/backup alpine tar xzf /backup/gallery-data.tar.gz -C /

# 서비스 재시작
cd gallery-server && docker compose up -d
```

---

## 9. 보안

### 9.1 인증

- LiteLLM 마스터 키: `dummy-key` (내부망 전용, 외부 노출 금지)
- Gallery 업로드 토큰: `lambda-upload`
- 인증서: 자체 서명 인증서 (Caddy 자동 생성)

### 9.2 네트워크

- 모든 서비스는 내부망 IP (100.252.x.x)에서만 접근
- 외부 인터넷 연결 없음 (폐쇄망)
- Caddy HTTPS (자체 서명 인증서)로 Gallery 제공

---

## 10. FAQ

### Q: 새로운 LLM 모델을 추가하려면?
1. llama.cpp 서버에 모델 파일 배치
2. `docker-compose-v2.yaml`에 새 서비스 추가
3. `litellm-config-v2.yaml`에 모델 정의 추가
4. `monitor-config.py`에 인스턴스 추가
5. `docker compose -f docker-compose-v2.yaml up -d`

### Q: 사용자가 늘어나서 응답이 느려지면?
- llama.cpp 인스턴스 추가 (원격 서버에 GPU 추가)
- LiteLLM `routing_strategy: least-busy`가 자동으로 분산
- 모니터에서 인스턴스 수 확인

### Q: 확장을 수정해서 배포하려면?
- [4. 확장 빌드 및 배포](#4-확장-빌드-및-배포) 참조
- 빌드 후 갤러리에 업로드
- 사용자는 `update.bat` 실행

### Q: Reasoning이 안 보이면?
1. LiteLLM 버전 확인 (1.93.0 이상 필요)
2. customoai URL이 LiteLLM 프록시(8088)를 가리키는지 확인
3. llama.cpp 직접(8085) 연결 시에도 reasoning_content 전달 확인
4. 확장 버전 999.28.0 이상 확인

### Q: `@github/copilot/sdk` 에러가 콘솔에 나오면?
- 무시해도 됩니다. copilotcli 세션 프로바이더의 빌드 문제이며 채팅 기능에 영향을 주지 않습니다.

---

## 11. 파일 구조

```
vscode-lambda/
├── src/                                    # 확장 소스 코드
│   ├── extension/
│   │   ├── byok/
│   │   │   ├── node/
│   │   │   │   └── openAIEndpoint.ts       # CustomOAI 엔드포인트 (reasoning, max_tokens, 도구)
│   │   │   └── vscode-node/
│   │   │       ├── customOAIProvider.ts     # CustomOAI 프로바이더
│   │   │       └── llmHealthMonitor.ts     # LLM 상태 모니터 (상태 표시줄)
│   │   ├── prompt/node/
│   │   │   └── pseudoStartStopConversationCallback.ts  # Reasoning markdown 스트리밍
│   │   ├── tools/node/
│   │   │   └── insertEditTool.tsx          # 파일 수정 도구 (폐쇄망 직접 수정)
│   │   └── log/vscode-node/
│   │       └── loggingActions.ts           # LLMHealthMonitor 등록
│   └── platform/
│       ├── thinking/common/                 # reasoning_content 추출 로직
│       └── networking/node/stream.ts        # SSE 스트림 처리
├── gallery-server/                         # VS Code 확장 갤러리
│   ├── caddy/                              # Caddy HTTPS 역방향 프록시
│   ├── uploader/                           # VSIX 업로드 사이드카
│   ├── docker-compose.yml                  # 갤러리 서비스 구성
│   └── scripts/                            # 확장 관리 스크립트
├── lambda-chat-deploy/                     # 사용자 PC 배포
│   ├── install.bat                         # 초기 설치 스크립트
│   ├── update.bat                          # 확장 업데이트 스크립트
│   ├── reset-vscode.bat                    # VS Code 초기화
│   ├── configure-vscode.ps1                # VS Code 설정 (product.json, 인증서)
│   ├── configure-pip.ps1                   # pip/devpi 설정
│   ├── dummy-key                           # 인증 키 파일
│   └── README.txt                          # 설치 가이드
├── devpi/                                  # Python 패키지 서버
│   ├── docker-compose.yml
│   └── scripts/
├── litellm_config/                         # LLM 프록시 설정
│   ├── airgap/                             # LiteLLM airgap 이미지 빌드
│   │   ├── Dockerfile
│   │   ├── cl100k_base.tiktoken
│   │   └── o200k_base.tiktoken
│   ├── llm-monitor/                        # LLM 모니터 사이드카
│   │   ├── Dockerfile
│   │   ├── monitor.py
│   │   └── requirements.txt
│   └── SLTPRODL01/                         # 프로덕션 서버 설정
│       ├── docker-compose-v2.yaml          # 통합 운영용 compose
│       ├── litellm-config-v2.yaml          # LiteLLM 설정
│       ├── monitor-config.py               # 모니터 설정 (서버용)
│       └── 배포가이드-v2.md
├── package.json                            # 확장 메타데이터 (버전 999.46.0)
├── .esbuild.ts                             # 빌드 설정
└── OPERATIONS-MANUAL.md                    # 이 파일
```

---

## 12. 연락처 및 이스컬레이션

| 항목 | 담당 | 비고 |
|------|------|------|
| LLM 서버 | 인프라팀 | GPU 서버, Docker |
| VS Code 확장 | 개발팀 | 확장 빌드/배포 |
| Gallery 서버 | 인프라팀 | 확장 배포 |
| 사용자 지원 | 계리팀 헬프데스크 | 설치, 사용 문의 |

---

*최종 업데이트: 2026-07-24*
*Lambda Extension 버전: 999.46.0*
*LiteLLM 버전: 1.93.0*
