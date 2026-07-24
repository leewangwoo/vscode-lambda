# Private VS Code Extension Gallery

이 디렉토리는 인터넷이 차단된 내부망(폐쇄망)에서 VS Code 확장 프로그램을
검색/설치/자동 업데이트할 수 있게 해주는 **사설 갤러리 서버** 구성입니다.

Coder의 오픈소스 **[code-marketplace](https://github.com/coder/code-marketplace)**
를 사용하여 VS Code의 실제 갤러리 API 계약을 구현합니다. 커스텀 서버와 달리
검색·설치·업데이트가 VS Code와 완벽하게 호환됩니다.

## 아키텍처

```
┌────────────────┐     HTTPS:8443     ┌────────────┐      HTTP:3001     ┌──────────────────┐
│  VS Code       │ ─────────────────▶ │   Caddy    │ ─────────────────▶ │ code-marketplace │
│  클라이언트     │   (TLS + CORS)     │ (자체서명)  │   리버스 프록시     │ (VS Code API)    │
└────────────────┘                    └─────┬──────┘                    └──────────────────┘
                                            │ HTTP:8001
                                            ▼
┌────────────────┐                   ┌──────────────┐
│  외부 PC       │ ─── POST /upload ▶│  uploader    │── docker exec ──▶ code-marketplace
│ (VSIX 전송)    │   (X-Upload-Token)│  (사이드카)   │   add <vsix>
└────────────────┘                   └──────────────┘
                                            │
                                            └─ /cert 로 인증서 서빙 (클라이언트 신뢰용)
```

- **code-marketplace** (`:3001`, 내부 전용): VSIX 파일을 `/extensions`에서 읽어
  `/api/extensionquery`, `/files/{publisher}/{name}/{version}/{path}` 엔드포인트 제공
- **uploader** (`:8001`, 내부 전용): 외부 PC에서 VSIX를 HTTP로 올리면(`POST /upload`)
  `docker exec code-marketplace add`로 자동 등록. 폐쇄망에서 SSH/접속 없이 등록하기 위함
- **Caddy** (`:8443`, 외부 노출): TLS 종단 + CORS 헤더 추가. code-marketplace와 uploader로 라우팅.
  첫 실행 시 자체 서명 인증서를 자동 생성

> VS Code의 Content Security Policy는 HTTPS 갤러리 URL만 허용하므로 Caddy가 필요합니다.
> 폐쇄망에서는 Let's Encrypt를 사용할 수 없어 자체 서명 인증서를 사용합니다.

## 빠른 시작

### 1. 서버 실행

```bash
cd gallery-server
docker compose up -d
```

Caddy가 첫 부팅 시 자체 서명 인증서를 생성하여 `/sqream/gallery-data/certs/`에 저장합니다.

```bash
# 헬스 체크
curl -k https://localhost:8443/healthz
```

### 2. 확장 등록

외부 PC에서 **HTTPS로 VSIX를 업로드하면 갤러리에 자동 등록**됩니다. 서버에
접속하거나 docker를 직접 만질 필요가 없습니다.

```cmd
:: 단일 파일 (기본 대상: https://100.252.201.200:8443)
scripts\publish.bat lambda-chat-deploy\copilot-chat-999.1.0.vsix

:: 디렉토리 (모든 VSIX)
scripts\publish.bat C:\extensions

:: 여러 파일
scripts\publish.bat a.vsix b.vsix c.vsix

:: 다른 갤러리 서버 지정
scripts\publish.bat https://192.168.1.50:8443 ext.vsix
```

내부적으로는 `POST /upload` (헤더 `X-Upload-Token`)로 전송 → uploader 사이드카가
받아서 `code-marketplace add`로 등록합니다.

또는 마켓플레이스에서 공통 확장을 일괄 다운로드 + 업로드 (외부망 필요):

```cmd
scripts\fetch-vscode-extensions.bat
```

### 3. 클라이언트 설정

각 클라이언트 PC에서:

```powershell
.\scripts\configure-vscode.ps1 -GalleryUrl "https://100.252.201.200:8443" -InstallCert
```

이 스크립트는:
1. `product.json`의 `extensionsGallery`를 code-marketplace 엔드포인트로 설정
   (`/api`, `/item`, `/files/{publisher}/{name}/{version}/{path}`)
2. `-InstallCert` 플래그로 Caddy의 자체 서명 인증서를 다운로드하여
   Windows 신뢰할 수 있는 루트 인증 기관에 설치

VS Code 재시작 후 확장 탭(`Ctrl+Shift+X`)에서 사설 갤러리가 보입니다.

## 디렉토리 구성

```
gallery-server/
├── docker-compose.yml       # code-marketplace + uploader + Caddy 서비스 정의
├── README.md                # 이 문서
├── caddy/                   # HTTPS 리버스 프록시
│   ├── Dockerfile
│   ├── Caddyfile            # TLS 종단 + CORS + /cert 서빙 + /upload 라우팅
│   └── entrypoint.sh        # 인증서 자동 생성 후 Caddy 실행
├── uploader/                # VSIX 업로드 사이드카
│   ├── Dockerfile           # python + docker-ce-cli (docker exec용)
│   ├── app.py               # /upload → code-marketplace add 자동 등록
│   └── requirements.txt
└── scripts/
    ├── build-offline-image.bat     # 외부망: 이미지 빌드 + tar 내보내기
    ├── load-offline-images.sh      # 내부망: tar에서 이미지 로드
    ├── publish.bat                 # VSIX → POST /upload (외부 PC에서 실행)
    ├── fetch-vscode-extensions.bat # 마켓플레이스 확장 다운로드 + /upload
    └── configure-vscode.ps1        # 클라이언트 product.json + 인증서 설정
```

## 데이터 영속성

- `/sqream/gallery-data/extensions/` — code-marketplace가 파싱한 VSIX 콘텐츠
- `/sqream/gallery-data/inbox/` — 업로드된 VSIX 원본 (uploader가 여기에 저장 후 등록)
- `/sqream/gallery-data/certs/` — Caddy의 자체 서명 인증서 (재시작 시 재사용)

## 오프라인 배포

외부망에서 Docker 이미지를 빌드하여 tar로 내보내고 내부망에서 로드합니다:

```cmd
:: 외부망 (Windows)
scripts\build-offline-image.bat .\offline-images

:: 내부망 (Linux) - tar 로드 후 docker compose up -d
scripts\load-offline-images.sh ./offline-images
```

상세한 절차는 프로젝트 루트의 [`OFFLINE-GUIDE.md`](../OFFLINE-GUIDE.md)를 참조하세요.

## 버전 관리

확장 버전을 올리면 VS Code 클라이언트가 자동으로 업데이트를 감지합니다
(`extensions.autoUpdate` 기본값 on):

```bash
# 확장 버전 업
npm version minor           # 999.1.0 → 999.2.0
npm run build
npx vsce package --no-git-tag-version --no-dependencies

# 갤러리에 새 버전 등록
scripts\publish.bat copilot-chat-999.2.0.vsix
```
