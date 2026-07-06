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
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐          │
│  │ VS Code     │  │ 확장 갤러리   │  │ devpi       │          │
│  │ 클라이언트   │  │ :8000        │  │ :3141       │          │
│  │ (Windows)   │  │ (FastAPI)    │  │ (PyPI Proxy)│          │
│  └──────┬──────┘  └──────┬───────┘  └──────┬──────┘          │
│         │ 확장 설치/업데이트  VSIX 서빙       pip 패키지         │
│         │                │                  │                  │
│  ┌──────┴──────┐  ┌──────┴───────┐                            │
│  │ LiteLLM     │  │ llama.cpp    │                            │
│  │ :8088       │──│ :8084/8085   │                            │
│  │ (LLM Proxy) │  │ (Qwen 모델)   │                            │
│  └─────────────┘  └──────────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

### 포트 할당

| 서비스 | 포트 | 용도 |
|--------|------|------|
| 확장 갤러리 서버 | 8000 | VS Code 확장 검색/설치/업데이트 |
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

### 2.1 저장소 복제

```bash
git clone https://github.com/leewangwoo/vscode-lambda.git
cd vscode-lambda
```

### 2.2 IP 주소 설정

서버 IP가 `100.252.201.200`이 아닌 경우, 다음 파일에서 IP를 변경하세요:

| 파일 | 수정 항목 |
|------|-----------|
| `lambda-chat-deploy/install.bat` | `GALLERY_URL` 값 |
| `devpi/docker-compose.yml` | `--outside-url` 값 |
| `devpi/scripts/sync-packages.sh` | 기본 URL |
| `devpi/scripts/configure-pip.ps1` | 기본 URL |
| `gallery-server/scripts/fetch-vscode-extensions.sh` | 기본 URL |

### 2.3 LiteLLM 설정

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

### 3.1 서버 시작

```bash
cd gallery-server
docker compose up -d --build
```

서버가 `http://<서버IP>:8000`에서 실행됩니다.

### 3.2 Lambda 확장 등록

```bash
# Lambda Chat VSIX를 갤러리에 업로드
./gallery-server/scripts/publish.sh lambda-chat-deploy/copilot-chat-999.1.0.vsix http://<서버IP>:8000
```

### 3.3 공통 VS Code 확장 등록

외부망 PC에서 실행 (인터넷 필요):

```bash
# 마켓플레이스에서 확장을 다운로드하여 내부 갤러리에 등록
./gallery-server/scripts/fetch-vscode-extensions.sh http://<서버IP>:8000
```

등록되는 확장:
- `ms-python.python` (Python)
- `ms-python.vscode-pylance` (Pylance)
- `ms-python.debugpy` (디버거)
- `ms-python.black-formatter` (Black 포매터)
- `ms-python.isort` (import 정렬)
- 그 외 YAML, Docker, Remote-SSH 등

### 3.4 갤러리 확인

```bash
# 등록된 확장 목록 확인
curl http://<서버IP>:8000/api/extensions | python3 -m json.tool

# 갤러리 정보
curl http://<서버IP>:8000/
```

### 3.5 확장 삭제 (필요시)

```bash
# 특정 버전 삭제
curl -X DELETE http://<서버IP>:8000/api/extensions/ms-python.python/2024.0.0
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

```bash
./gallery-server/scripts/publish.sh copilot-chat-999.2.0.vsix http://<서버IP>:8000
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

# 2. 갤러리에 등록
./gallery-server/scripts/publish.sh copilot-chat-999.2.0.vsix http://<서버IP>:8000

# 3. 클라이언트는 자동 업데이트 (extensions.autoUpdate 기본값 on)
```

### 7.2 새 VS Code 확장 추가

```bash
# 외부망에서 마켓플레이스 확장 다운로드 → 내부 갤러리 등록
./gallery-server/scripts/fetch-vscode-extensions.sh http://<서버IP>:8000
```

또는 특정 확장만:

```bash
# 마켓플레이스에서 VSIX 다운로드
curl -sL "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<name>/latest/vspackage" -o ext.vsix.gz
gzip -d ext.vsix.gz

# 갤러리에 등록
curl -X POST -F "file=@ext.vsix" http://<서버IP>:8000/api/upload
```

### 7.3 Python 패키지 추가

```bash
# 외부망에서 패키지 동기화
./devpi/scripts/sync-packages.sh <requirements.txt> http://<서버IP>:3141
```

### 7.4 백업

```bash
# 확장 갤러리 백업
docker cp vscode-gallery:/data ./gallery-backup

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
- `product.json`의 갤러리 URL이 올바른지 확인
- 갤러리 서버가 실행 중인지 확인: `curl http://<서버IP>:8000/health`

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
│   ├── server.py                  # FastAPI 갤러리 서버
│   ├── docker-compose.yml         # Docker 설정
│   ├── Dockerfile
│   ├── requirements.txt           # Python 의존성
│   ├── README.md                  # 갤러리 서버 가이드
│   └── scripts/
│       ├── publish.sh             # VSIX 갤러리 업로드
│       ├── add_extension.py       # VSIX 로컬 등록
│       ├── fetch-vscode-extensions.sh  # 마켓플레이스 확장 다운로드
│       └── configure-vscode.ps1   # VS Code 갤러리 URL 설정
├── devpi/                         # Python 패키지 서버
│   ├── docker-compose.yml         # devpi Docker 설정
│   ├── requirements-common.txt    # 공통 패키지 목록
│   ├── README.md                  # devpi 가이드
│   └── scripts/
│       ├── sync-packages.sh       # 패키지 동기화
│       ├── configure-pip.ps1      # Windows pip 설정
│       └── configure-pip.sh       # Linux pip 설정
├── lambda-chat-deploy/            # 클라이언트 배포 패키지
│   ├── install.bat                # 원클릭 설치 스크립트
│   ├── configure-vscode.ps1       # 갤러리 URL 설정
│   ├── copilot-chat-original.vsix # 순정 Copilot Chat
│   ├── copilot-chat-*.vsix        # Lambda 커스텀 확장
│   └── README.txt                 # 설치 가이드
├── OFFLINE-GUIDE.md               # 이 문서
└── README.md                      # 프로젝트 전체 README
```
