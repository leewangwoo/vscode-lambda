FROM ghcr.io/berriai/litellm:main-stable

# ──────────────────────────────────────────────
# Airgap: 인터넷 차단 환경을 위한 tiktoken 로컬화
# ──────────────────────────────────────────────
# tiktoken은 런타임에 인터넷에서 토크나이저 파일을 다운로드한다.
# 폐쇄망에서는 이 다운로드가 실패하므로 파일을 미리 이미지에 넣고
# load.py를 패치하여 로컬 파일을 읽도록 변경한다.

COPY cl100k_base.tiktoken /app/cl100k_base.tiktoken
COPY o200k_base.tiktoken  /app/o200k_base.tiktoken

RUN LOAD_PY=$(/app/.venv/bin/python -c "import tiktoken; print(tiktoken.__file__.replace('/__init__.py', '/load.py'))") && \
    sed -i 's|resp = requests.get(blobpath)|import requests; resp = requests.Response(); resp.status_code = 200; resp._content = open("/app/" + blobpath.split("/")[-1], "rb").read()|' "$LOAD_PY"

# ──────────────────────────────────────────────
# 메트릭 & 대기열 관제 환경변수
# ──────────────────────────────────────────────
ENV LITELLM_MODE="development"
ENV PROMETHEUS_MULTIPROC_DIR=/tmp
RUN mkdir -p /tmp
