Lambda Chat Extension - 설치 가이드
=====================================

요구사항:
- VS Code 1.115.0 이상
- 내부망 갤러리 서버 (https://<서버IP>:8443) 접근 가능

설치 방법:
1. "install.bat" 더블클릭
   자동으로 수행되는 작업:
   a) VS Code의 product.json을 내부 갤러리(code-marketplace)로 설정
   b) 갤러리의 자체 서명 HTTPS 인증서 설치
   c) 확장 서명 검증 비활성화 (내부 갤러리)
   d) GitHub MCP Server 비활성화 (GitHub 로그인 프롬프트 방지)
   e) 순정 Copilot Chat VSIX 다운로드 및 설치 (신뢰 설정)
   f) Lambda Chat VSIX 다운로드 및 설치
   g) pip를 내부 devpi 서버로 설정 (Python이 설치된 경우만)

   관리자 권한 불필요. 인증서는 현재 사용자 저장소에 설치됩니다.
   Python이 설치되어 있지 않으면 pip 설정 단계는 자동으로 건너뜁니다.

2. VS Code에서 customoai 활성화 (반드시 필요):
   CLI 설치만으로는 customoai 설정이 나타나지 않습니다.
   VS Code UI에서 Disable 후 다시 Enable해야 합니다.

   a) VS Code 실행
   b) 확장 탭 열기 (Ctrl+Shift+X)
   c) "lambda" 검색
   d) GitHub Copilot Chat 확장의 Disable 클릭
   e) 다시 Enable 클릭
   f) 설정 (Ctrl+,)에서 "customoai" 검색

   (Reload Window 필요 없음)

설정:
- Customoai: Url  -> http://100.252.201.200:8088/v1 (자동 입력됨)
- Customoai: Key  -> dummy-key (자동 입력됨)

문제 해결:
- customoai 설정이 보이지 않는 경우:
  1. 확장 탭 (Ctrl+Shift+X)
  2. "lambda" 검색
  3. GitHub Copilot Chat 확장 Disable 클릭
  4. 다시 Enable 클릭
  5. 설정에서 "customoai" 검색

- 확장 탭이 비어있는 경우:
  1. 갤러리 서버 확인: https://<서버IP>:8443/healthz
  2. 인증서 신뢰 확인
  3. Developer: Reload Window 실행

- 채팅에서 파일 저장 요청 시 GitHub 로그인 프롬프트가 나오는 경우:
  - GitHub MCP Server가 활성화되어 있어서 그럼
  - 설정에서 "githubMcp" 검색 > "Chat > GitHub Mcp Server: Enabled" 끄기
  - 또는 settings.json에 "chat.githubMcpServer.enabled": false 추가

참고사항:
- 내부망의 LiteLLM 서버와 연동하여 오프라인으로 동작
- "Sign in to GitHub" 프롬프트는 무시
- Python 설치 후 pip install로 패키지 설치 시 내부 devpi 서버 사용
  예: pip install numpy pandas flask

파일 구성:
- install.bat                -> 더블클릭하여 자동 설정 실행
- configure-vscode.ps1       -> 갤러리 URL + 인증서 + 설정 (install.bat이 자동 호출)
- configure-pip.ps1          -> pip를 내부 devpi로 설정 (install.bat이 자동 호출)
