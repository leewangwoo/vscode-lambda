# VS Code Lambda

인터넷이 차단된 내부망(폐쇄망)에서 GitHub Copilot Chat을 로컬 LLM(LiteLLM)과 연동하여 사용할 수 있도록 커스터마이징한 VS Code 확장 프로젝트입니다.

## 개요

VS Code Lambda는 다음 세 가지 목표를 달성합니다:

1. **오프라인 LLM 채팅** — GitHub 로그인 없이 내부망의 LiteLLM 프록시(llama.cpp 백엔드)를 통해 AI 채팅 사용
2. **내부 확장 갤러리** — VS Code 확장을 마켓플레이스 대신 내부 갤러리에서 검색·설치·업데이트
3. **내부 Python 패키지 저장소** — 인터넷 없이 `pip install`로 Python 패키지 설치

## 시스템 구성

```
┌──────────────────────────────────────────────────────────────┐
│                       내부망 (폐쇄망)                           │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐          │
│  │ VS Code     │  │ 확장 갤러리   │  │ devpi       │          │
│  │ 클라이언트   │  │ :8000        │  │ :3141       │          │
│  │ (Windows)   │  │ (FastAPI)    │  │ (PyPI Proxy)│          │
│  └──────┬──────┘  └──────┬───────┘  └──────┬──────┘          │
│         │                │                  │                  │
│         │ 확장 설치/업데이트 │ VSIX 서빙       │ pip 패키지       │
│         │                │                  │                  │
│  ┌──────┴──────┐  ┌──────┴───────┐                            │
│  │ LiteLLM     │  │ llama.cpp    │                            │
│  │ :8088       │──│ :8084/8085   │                            │
│  │ (LLM Proxy) │  │ (Qwen 모델)   │                            │
│  └─────────────┘  └──────────────┘                            │
│                                                               │
│              ┌───────────────────┐                            │
│              │ Docker Host       │                            │
│              │ (Linux 서버)       │                            │
│              └───────────────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

## 포트 할당

| 서비스 | 포트 | 용도 |
|--------|------|------|
| 확장 갤러리 서버 | 8000 | VS Code 확장 검색/설치/업데이트 |
| LiteLLM 프록시 | 8088 | LLM 모델 라우팅 |
| devpi (PyPI 프록시) | 3141 | Python 패키지 관리 |
| llama.cpp (Qwen3.6-35B) | 8084 | MoE 모델 서버 |
| llama.cpp (Qwen3.6-27B) | 8085 | Dense 모델 서버 |

## 디렉토리 구조

```
vscode-lambda/
├── src/                        # 확장 소스 코드
├── gallery-server/             # 확장 갤러리 서버 (FastAPI + Docker)
│   ├── server.py               # 갤러리 API 서버
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── scripts/                # 갤러리 관리 스크립트
├── devpi/                      # Python 패키지 서버
│   ├── docker-compose.yml
│   └── scripts/                # 패키지 동기화 및 pip 설정 스크립트
├── lambda-chat-deploy/         # 클라이언트 배포 패키지
│   ├── install.bat             # 원클릭 설치 스크립트
│   ├── configure-vscode.ps1    # VS Code 갤러리 URL 설정
│   └── copilot-chat-*.vsix     # Lambda 확장 파일
├── OFFLINE-GUIDE.md            # 상세 배포 가이드 (한글)
└── package.json                # 확장 메타데이터
```

## 빠른 시작

### 서버 설정 (내부망 Linux 서버)

```bash
# 1. 확장 갤러리 서버 시작
cd gallery-server
docker compose up -d --build

# 2. Python 패키지 서버 시작
cd ../devpi
docker compose up -d

# 3. Lambda 확장을 갤러리에 등록
./gallery-server/scripts/publish.sh lambda-chat-deploy/copilot-chat-999.1.0.vsix http://localhost:8000
```

### 클라이언트 설정 (내부망 Windows PC)

```powershell
# 1. 확장 설치 + 갤러리 등록 (원클릭)
.\lambda-chat-deploy\install.bat

# 2. Python pip 설정
.\devpi\scripts\configure-pip.ps1 -DevpiUrl "http://<서버IP>:3141"

# 3. VS Code 재시작 후 채팅 패널에서 사용
```

상세한 설정 방법은 [OFFLINE-GUIDE.md](./OFFLINE-GUIDE.md)를 참조하세요.

## 주요 기능

### 오프라인 LLM 채팅

- GitHub 로그인 불필요 (Mock 인증으로 우회)
- LiteLLM 프록시를 통한 로컬 모델(Qwen3.6) 사용
- 채팅 패널에서 모델 선택 및 대화
- 스트리밍 응답 지원 (LiteLLM 호환성 처리 포함)

### 내부 확장 갤러리

- VS Code 확장 탭에서 내부 갤러리 검색/설치
- 자동 업데이트 (버전 비교 → 알림 → 설치)
- 버전 관리 (semver 기반)
- 마켓플레이스 확장 다운로드 → 내부 갤러리 등록

### 내부 Python 패키지 관리

- devpi를 통한 PyPI 프록시/캐시
- 외부망에서 패키지 동기화
- 사용자는 `pip install`만 하면 됨

## 기술 스택

- **확장**: TypeScript, VS Code Extension API
- **갤러리 서버**: Python, FastAPI, Docker
- **패키지 서버**: devpi-server, Docker
- **LLM 백엔드**: llama.cpp, LiteLLM, Qwen3.6

## 라이선스

원본 VS Code Copilot Chat의 라이선스를 따릅니다. 자세한 내용은 [LICENSE.txt](./LICENSE.txt)를 참조하세요.
