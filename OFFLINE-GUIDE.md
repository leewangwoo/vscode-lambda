# VS Code Lambda - 오프라인 내부망 구축 가이드

인터넷이 차단된 내부망(폐쇄망)에서 VS Code, 확장 프로그램, Python 패키지를
사용하기 위한 전체 구축 가이드입니다.

---

## 목차

1. [시스템 구성](#1-시스템-구성)
2. [서버 설정](#2-서버-설정)
3. [확장 갤러리 서버](#3-확장-갤러리-서버)
4. [Python 패키지 서버 (devpi)](#4-python-패키지-서버-devpi)
5. [Lambda Chat 확장 빌드](#5-lambda-chat-확장-빌드)
6. [클라이언트 설정](#6-클라이언트-설정)
7. [운영 및 업데이트](#7-운영-및-업데이트)
8. [문제 해결](#8-문제-해결)

---

## 1. 시스템 구성

### 전체 아키텍처

```
┌──────────────────────────────────────────────────────────────┐
│                       내부망 (폐쇄망)                           │
│                                                               │
│  ┌─────────────┐                                              │
│  │ VS Code     │  확장 설치/업데이트 (HTTPS)                     │
│  │ 클라이언트   │ ─────────────────────┐                        │
│  │ (Windows)   │                      ▼                        │
│  └──────┬──────┘              ┌──────────────┐                 │
│         │                     │ Caddy :8443  │ (TLS 종단)       │
│         │                     │ (자체서명 인증) │                 │
│         │                     └──────┬───────┘                 │
│         │                            │ 리버스 프록시              │
│         │                            ▼                         │
│         │                     ┌──────────────────┐             │
│         │                     │ code-marketplace │             │
│         │                     │ :3001 (내부 전용)  │             │
│         │                     │ (VS Code API)    │             │
│         │                     └──────────────────┘             │
│         │                                                      │
│         │ pip 패키지                                           │
│         ▼                                                      │
│  ┌─────────────┐                                               │
│  │ devpi :3141 │ (PyPI Proxy)                                  │
│  └─────────────┘                                               │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐                            │
│  │ LiteLLM     │  │ llama.cpp    │                            │
│  │ :8088       │──│ :8084/8085   │                            │
│  │ (LLM Proxy) │  │ (Qwen 모델)   │                            │
│  └─────────────┘  └──────────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

> code-marketplace는 평문 HTTP로만 동작하지만, VS Code의 CSP 정책이
> HTTPS 갤러리 URL만 허용하므로 Caddy 리버스 프록시로 TLS를 종단합니다.
> 폐쇄망에서는 Let's Encrypt를 사용할 수 없으므로 자체 서명 인증서를
> 자동 생성하고 클라이언트에서 신뢰해야 합니다.

### 포트 할당

| 서비스 | 포트 | 용도 |
|--------|------|------|
| Caddy (HTTPS 리버스 프록시) | 8443 | VS Code 확장 검색/설치/업데이트 (외부 노출) |
| code-marketplace (내부) | 3001 | VS Code 갤러리 API (Caddy 뒤단, 외부 비노출) |
| LiteLLM 프록시 | 8088 | LLM 모델 라우팅 |
| devpi (PyPI 프록시) | 3141 | Python 패키지 관리 |
| llama.cpp (Qwen3.6-35B) | 8084 | MoE 모델 서버 |
| llama.cpp (Qwen3.6-27B) | 8085 | Dense 모델 서버 |

### 사전 준비

- **내부망 Linux 서버**: Docker 및 Docker Compose 설치
- **외부망 PC**: 인터넷 접속 가능 (패키지 다운로드용)
- **클라이언트 PC**: Windows, VS Code 1.115 이상

---

## 2. 서버 설정

### 2.1 Docker 이미지 준비

내부망은 인터넷이 차단되어 있으므로, **외부망에서 Docker 이미지를 미리 빌드하여 tar 파일로 내부망으로 가져가야 합니다.**

#### 외부망 Windows PC에서 이미지 빌드 (인터넷 필요)

```cmd
:: 저장소 복제
git clone https://github.com/leewangwoo/vscode-lambda.git
cd vscode-lambda

:: Docker 이미지 빌드 + tar 파일로 내보내기
gallery-server\scripts\build-offline-image.bat .\offline-images
```

생성되는 파일:

```
offline-images\
├── code-marketplace.tar   # VS Code 갤러리 API 백엔드 (오픈소스)
├── caddy.tar              # HTTPS 리버스 프록시 (TLS 종단)
└── devpi-server.tar       # devpi Python 패키지 서버
```

#### 내부망 서버에서 이미지 로드

`offline-images/` 폴더 전체를 내부망 서버로 복사한 후:

```bash
# tar 파일에서 Docker 이미지 로드
./gallery-server/scripts/load-offline-images.sh ./offline-images

# 로드 확인
docker images | grep -E "code-marketplace|lambda-gallery-caddy|devpi"
```

### 2.2 소스 코드 복사

저장소 전체를 내부망 서버로 복사합니다 (USB, 내부망 파일 서버 등).

```bash
# 내부망 서버에 저장소 복사 후
cd vscode-lambda
```

> **참고:** Docker 이미지는 2.1에서 로드했으므로, 내부망에서 빌드(`docker build`)할 필요가 없습니다. `docker-compose.yml`은 사전 빌드된 이미지를 사용하도록 설정되어 있습니다.

### 2.3 IP 주소 설정

서버 IP가 `100.252.201.200`이 아닌 경우, 다음 파일에서 IP를 변경하세요:

| 파일 | 수정 항목 |
|------|-----------|
| `lambda-chat-deploy/install.bat` | `GALLERY_URL` 값 |
| `gallery-server/docker-compose.yml` | `GALLERY_HOST` 환경변수 (Caddy 인증서 CN/SAN) |
| `devpi/docker-compose.yml` | `--outside-url` 값 |
| `devpi/scripts/sync-packages.sh` | 기본 URL |
| `devpi/scripts/configure-pip.ps1` | 기본 URL |

> `GALLERY_HOST`는 자체 서명 인증서에 포함되는 호스트 이름/IP입니다.
> 클라이언트가 접속할 주소와 일치해야 인증서 검증이 통과합니다.

### 2.4 LiteLLM 설정

LiteLLM은 이미 구성되어 있다고 가정합니다. 설정 파일(`litellm-config.yaml`)에서 다음을 확인:

```yaml
model_list:
  - model_name: qwen27
    litellm_params:
      model: openai/qwen27
      api_base: http://qwen27-5:8080/v1
      api_key: none

  - model_name: qwen35
    litellm_params:
      model: openai/qwen35
      api_base: http://qwen35-4:8080/v1
      api_key: none
```

LiteLLM 프록시 주소: `http://<서버IP>:8088/v1`

---

## 3. 확장 갤러리 서버

확장 갤러리는 Coder의 오픈소스 **code-marketplace**를 사용합니다.
VS Code의 실제 갤러리 API 계약을 구현하여 검색/설치/자동 업데이트가
그대로 동작합니다.

- **code-marketplace** (`:3001`, 내부 전용): VSIX 파일을 읽어 VS Code 갤러리 API 제공
- **uploader** (`:8001`, 내부 전용): 외부 PC에서 HTTPS로 VSIX를 올리면(`POST /upload`)
  code-marketplace에 자동 등록. 서버 접속/SSH 불필요
- **Caddy** (`:8443`, 외부 노출): HTTPS 종단 + CORS 헤더 추가, code-marketplace/uploader로 라우팅

### 3.1 서버 시작

```bash
cd gallery-server
docker compose up -d
```

> Caddy는 첫 실행 시 자체 서명 인증서를 자동 생성하여
> `/sqream/gallery-data/certs/`에 저장합니다.

서버가 `https://<서버IP>:8443`에서 실행됩니다.

```bash
# 헬스 체크 (인증서 검증 건너뜀)
curl -k https://<서버IP>:8443/healthz

# 인증서 다운로드 (클라이언트 신뢰용)
curl -k https://<서버IP>:8443/cert -o gallery-ca.crt
```

### 3.2 Lambda 확장 등록

외부 PC에서 **HTTPS로 VSIX를 업로드하면 갤러리에 자동 등록**됩니다. 서버에 접속할 필요 없이 publish.bat 한 번이면 끝납니다.

```cmd
:: 외부 PC에서 (갤러리 서버에 접근 가능하면 됨, 인터넷 불필요)
gallery-server\scripts\publish.bat lambda-chat-deploy\copilot-chat-999.1.0.vsix
```

여러 파일이나 디렉토리도 가능:

```cmd
gallery-server\scripts\publish.bat C:\extensions
gallery-server\scripts\publish.bat ext1.vsix ext2.vsix
```

내부적으로는 `POST https://<서버IP>:8443/upload` (헤더 `X-Upload-Token`)로 전송 →
uploader 사이드카가 `code-marketplace add`를 실행하여 자동 등록합니다.

> 등록 직후 약 5초 이내 캐시 갱신 후 갤러리에 표시됩니다
> (`--list-cache-duration 5s` 설정).

### 3.3 공통 VS Code 확장 등록

외부망 PC에서 실행 (인터넷 필요). 마켓플레이스에서 VSIX를 다운로드하여
갤러리 서버의 `/upload`로 전송합니다:

```cmd
gallery-server\scripts\fetch-vscode-extensions.bat
```

등록되는 확장:
- `ms-python.python` (Python)
- `ms-python.vscode-pylance` (Pylance)
- `ms-python.debugpy` (디버거)
- `ms-python.black-formatter` (Black 포매터)
- `ms-python.isort` (import 정렬)
- 그 외 YAML, Docker, Remote-SSH 등

### 3.4 갤러리 확인

VS Code 갤러리 API를 직접 조회하여 등록된 확장을 확인합니다:

```bash
# 검색 쿼리 (VS Code가 보내는 형식)
curl -k -X POST https://<서버IP>:8443/api/extensionquery \
  -H "Content-Type: application/json" \
  -H "Accept: application/json;api-version=3.0-preview.1" \
  --data '{"filters":[{"criteria":[{"filterType":8,"value":"Microsoft.VisualStudio.Code"}]}],"flags":439}' \
  | python3 -m json.tool
```

### 3.5 확장 삭제 (필요시)

확장 삭제는 서버에서 직접 실행해야 합니다 (업로드와 달리 HTTP API가 없음):

```bash
# 특정 버전 삭제
docker exec code-marketplace code-marketplace remove ms-python.python@2024.0.0 --extensions-dir /extensions

# 특정 확장의 모든 버전 삭제
docker exec code-marketplace code-marketplace remove ms-python.python --all --extensions-dir /extensions
```

---

## 4. Python 패키지 서버 (devpi)

### 4.1 서버 시작

```bash
cd devpi
docker compose up -d
```

devpi가 `http://<서버IP>:3141`에서 실행됩니다.

### 4.2 초기 설정 (최초 1회)

```bash
# devpi-client 설치 (외부망 또는 서버에서)
pip install devpi-client

# 서버 연결
devpi use http://<서버IP>:3141

# 관리자 로그인 (초기 비밀번호는 비어있음)
devpi user -c admin password=<비밀번호>
devpi login admin --password=<비밀번호>

# 패키지 캐시용 인덱스 생성
devpi index -c staging bases=root/pypi volatile=True
```

### 4.3 패키지 동기화

외부망 PC에서 실행 (인터넷 필요):

```bash
pip install devpi-client
devpi use http://<서버IP>:3141
devpi login admin --password=<비밀번호>
devpi use admin/staging

# 공통 패키지 일괄 동기화
# Windows:
.\devpi\scripts\sync-packages.bat devpi\requirements-common.txt http://<서버IP>:3141
# Linux/macOS:
./devpi/scripts/sync-packages.sh devpi/requirements-common.txt http://<서버IP>:3141
```

동기화되는 패키지 (`requirements-common.txt`):
- 데이터 과학: numpy, pandas, scipy, matplotlib, jupyter
- 웹 프레임워크: flask, fastapi, django, requests
- 개발 도구: pytest, black, mypy, ruff
- 데이터베이스: sqlalchemy, psycopg2, redis
- 유틸리티: tqdm, click, rich, pydantic

### 4.4 개별 패키지 추가

외부망 PC에서 필요한 패키지만 추가:

```bash
devpi use http://<서버IP>:3141
devpi login admin --password=<비밀번호>
devpi use admin/staging

# 단일 패키지 동기화
pip download <패키지명> -d /tmp/pkg
devpi upload /tmp/pkg/<패키지명>-*.whl
```

### 4.5 클라이언트 pip 설정

각 사용자 PC에서:

```powershell
# Windows
.\devpi\scripts\configure-pip.ps1 -DevpiUrl "http://<서버IP>:3141"
```

```bash
# Linux
./devpi/scripts/configure-pip.sh http://<서버IP>:3141
```

설정 후 `pip install`이 내부 devpi 서버를 사용합니다:

```bash
pip install numpy pandas flask  # 내부망에서 정상 작동
```

---

## 5. Lambda Chat 확장 빌드

### 5.1 빌드 환경

빌드는 외부망 PC에서 수행합니다 (Node.js 필요).

```bash
# 의존성 설치
npm install

# 확장 빌드
npm run build

# VSIX 패키징
npx vsce package --no-git-tag-version --allow-package-secrets sendgrid --no-dependencies
```

결과물: `copilot-chat-<버전>.vsix`

### 5.2 버전 관리

```bash
# 패치 버전 업 (999.1.0 → 999.1.1)
npm version patch
npm run build
npx vsce package --no-git-tag-version --no-dependencies

# 마이너 버전 업 (999.1.0 → 999.2.0)
npm version minor
npm run build
npx vsce package --no-git-tag-version --no-dependencies
```

### 5.3 갤러리에 새 버전 등록

```cmd
gallery-server\scripts\publish.bat copilot-chat-999.2.0.vsix
```

VS Code 클라이언트에서 자동으로 업데이트 알림이 표시됩니다.

---

## 6. 클라이언트 설정

### 6.1 배포 패키지 준비

`lambda-chat-deploy/` 폴더 전체를 내부망 클라이언트 PC로 복사합니다.

### 6.2 설치 실행

```powershell
# install.bat를 관리자 권한으로 실행
.\lambda-chat-deploy\install.bat
```

자동으로 수행되는 작업:

1. VS Code의 `product.json`을 내부 갤러리 URL로 설정
2. 순정 GitHub Copilot Chat VSIX 설치 (신뢰 설정)
3. AI 기능 비활성화 (설정 캐시 초기화)
4. Lambda 커스텀 VSIX 설치
5. AI 기능 활성화 (Lambda 설정 로드)

### 6.3 Python 환경 설정

```powershell
.\devpi\scripts\configure-pip.ps1 -DevpiUrl "http://<서버IP>:3141"
```

### 6.4 설정 확인

1. VS Code 재시작 (`Developer: Reload Window`)
2. 설정 (`Ctrl+,`)에서 `customoai` 검색:
   - URL: `http://<서버IP>:8088/v1`
   - Key: `dummy-key`
3. 채팅 패널 열기 → 모델 드롭다운 확인 (qwen27, qwen35 표시)
4. 모델 선택 후 메시지 전송 테스트

### 6.5 확장 설치

VS Code 확장 탭 (`Ctrl+Shift+X`)에서 내부 갤러리의 확장을 검색하여 설치:

- `@builtin copilot-chat` 비활성화 후 Lambda 확정 설치
- Python 확장, YAML 확장 등 자유롭게 설치

---

## 7. 운영 및 업데이트

### 7.1 Lambda Chat 업데이트

```bash
# 1. 새 버전 빌드 (외부망)
npm version minor
npm run build
npx vsce package --no-git-tag-version --no-dependencies

# 2. 갤러리에 등록 (배포 서버/클라이언트 PC에서)
gallery-server\scripts\publish.bat copilot-chat-999.2.0.vsix

# 3. 클라이언트는 자동 업데이트 (extensions.autoUpdate 기본값 on)
```

### 7.2 새 VS Code 확장 추가

```cmd
:: 외부망에서 마켓플레이스 확장 다운로드 → 내부 갤러리 등록
gallery-server\scripts\fetch-vscode-extensions.bat
```

또는 수동으로 VSIX를 확보한 뒤 publish.bat으로 등록:

```bash
# 마켓플레이스에서 VSIX 다운로드 (외부망)
curl -sL "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<name>/latest/vspackage" -o ext.vsix.gz
gzip -d ext.vsix.gz

# 갤러리에 등록 (배포 서버에서)
gallery-server\scripts\publish.bat ext.vsix
```

### 7.3 Python 패키지 추가

```bash
# 외부망에서 패키지 동기화
# Windows:
.\devpi\scripts\sync-packages.bat <requirements.txt> http://<서버IP>:3141
# Linux/macOS:
./devpi/scripts/sync-packages.sh <requirements.txt> http://<서버IP>:3141
```

### 7.4 백업

```bash
# 확장 갤러리 백업 (VSIX + 인증서)
tar -czf gallery-backup.tar.gz /sqream/gallery-data

# devpi 백업
docker cp devpi-server:/data ./devpi-backup
```

---

## 8. 문제 해결

### 8.1 채팅 패널에서 "Sign in to use Copilot"이 표시됨

**원인:** 내장 Copilot Chat과 Lambda 확장의 설정 충돌

**해결:**
1. 확장 탭 (`Ctrl+Shift+X`)
2. `@builtin copilot-chat` 검색
3. 비활성화 (Disable)
4. `Developer: Reload Window` 실행
5. 다시 활성화 (Enable)
6. `Developer: Reload Window` 실행
7. `customoai` 설정 확인

### 8.2 `customoai` 설정이 보이지 않음

**원인:** VS Code 설정 캐시가 갱신되지 않음

**해결:** 위 8.1의 disable/enable 트릭 수행

### 8.3 채팅 요청 시 GitHub 서버 에러가 발생함

**원인:** 요청이 LiteLLM이 아닌 GitHub로 라우팅됨

**확인사항:**
- `customoai` URL 설정이 올바른지 확인
- LiteLLM 서버가 실행 중인지 확인: `curl http://<서버IP>:8088/v1/models`
- VS Code를 완전히 재시작

### 8.4 모델 응답이 없음 (no response was returned)

**원인:** LiteLLM(llama.cpp)이 `stream_options` 파라미터를 지원하지 않음

이 문제는 Lambda 확장에서 자동으로 처리됩니다. 최신 버전 사용을 권장합니다.

### 8.5 pip install 실패

**원인:** 패키지가 devpi에 캐시되지 않음

**해결:**
```bash
# 외부망에서 해당 패키지 동기화
devpi use admin/staging
pip download <패키지명> -d /tmp/pkg
devpi upload /tmp/pkg/<패키지명>-*.whl
```

### 8.6 확장 자동 업데이트가 동작하지 않음

**확인사항:**
- VS Code 설정에서 `extensions.autoUpdate`이 `true`인지 확인
- `product.json`의 갤러리 URL이 올바른지 확인 (`/api`, `/item`, `/files/...`)
- 갤러리 서버가 실행 중인지 확인: `curl -k https://<서버IP>:8443/healthz`
- 자체 서명 인증서가 신뢰되는지 확인 (configure-vscode.ps1 -InstallCert)

### 8.7 확장이 활성화되지 않음 (Proposed API)

**원인:** VS Code가 확장의 Proposed API를 승인하지 않음

**해결:** `install.bat`의 순서를 정확히 따라야 함:
1. 순정 Copilot Chat 설치 (신뢰 설정)
2. AI 비활성화 → Lambda 설치 → AI 활성화

순서가 바뀌면 Proposed API가 승인되지 않습니다.

---

## 파일 위치 요약

```
vscode-lambda/
├── src/                           # 확장 소스 코드
├── gallery-server/                # 확장 갤러리 서버
│   ├── docker-compose.yml         # code-marketplace + uploader + Caddy 서비스 정의
│   ├── README.md                  # 갤러리 서버 가이드
│   ├── caddy/                     # HTTPS 리버스 프록시 (자체 서명 인증서)
│   │   ├── Dockerfile
│   │   ├── Caddyfile              # TLS 종단 + CORS + /cert + /upload 라우팅
│   │   └── entrypoint.sh          # 인증서 자동 생성 후 Caddy 실행
│   ├── uploader/                  # VSIX 업로드 사이드카 (/upload → 자동 등록)
│   │   ├── Dockerfile
│   │   └── app.py
│   └── scripts/
│       ├── build-offline-image.bat    # 외부망(Windows): Docker 이미지 빌드 + tar 내보내기
│       ├── load-offline-images.sh     # 내부망(Linux): tar에서 Docker 이미지 로드
│       ├── publish.bat                # 외부 PC: VSIX → POST /upload (자동 등록)
│       ├── fetch-vscode-extensions.bat # 마켓플레이스 확장 다운로드 + /upload
│       └── configure-vscode.ps1       # product.json 갤러리 URL + 인증서 신뢰
├── devpi/                         # Python 패키지 서버
│   ├── docker-compose.yml         # devpi Docker 설정
│   ├── requirements-common.txt    # 공통 패키지 목록
│   ├── README.md                  # devpi 가이드
│   └── scripts/
│       ├── sync-packages.bat      # 패키지 동기화 (Windows)
│       ├── sync-packages.sh       # 패키지 동기화 (Linux)
│       ├── configure-pip.ps1      # Windows pip 설정
│       └── configure-pip.sh       # Linux pip 설정
├── lambda-chat-deploy/            # 클라이언트 배포 패키지
│   ├── install.bat                # 원클릭 설치 스크립트
│   ├── configure-vscode.ps1       # 갤러리 URL 설정 (configure-vscode.ps1 복사본)
│   ├── copilot-chat-original.vsix # 순정 Copilot Chat
│   ├── copilot-chat-*.vsix        # Lambda 커스텀 확장
│   └── README.txt                 # 설치 가이드
├── OFFLINE-GUIDE.md               # 이 문서
└── README.md                      # 프로젝트 전체 README
```
