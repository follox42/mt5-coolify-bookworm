FROM scottyhardy/docker-wine:latest

USER root
WORKDIR /root

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV DISPLAY=:99
ENV WINEDEBUG=-all,err-toolbar,fixme-all
ENV PATH=/root/.local/bin:$PATH

# ---- Linux side: Python deps (FastAPI + RPyC client to mt5linux) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        wget curl ca-certificates \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

# mt5linux==0.1.9 pinne numpy==1.21.4 (Python <=3.10) — workaround --no-deps + numpy compatible.
RUN pip3 install --no-cache-dir --break-system-packages \
        rpyc==5.3.1 \
        fastapi==0.115.0 \
        "uvicorn[standard]==0.32.0" \
        pydantic==2.9.0 \
        httpx==0.27.0 \
        "numpy>=1.26,<2.0" \
        pandas==2.2.3 \
    && pip3 install --no-cache-dir --break-system-packages --no-deps \
        mt5linux==0.1.9

# ---- Scripts (Wine init + MT5 install runs at FIRST BOOT, not build-time) ----
# Build-time wineboot fails because Coolify's BuildKit blocks seccomp syscalls Wine needs.
# Runtime works if container has --security-opt seccomp=unconfined (set in Coolify Custom Docker Run Options).
COPY install_mt5.sh /install_mt5.sh
COPY app.py /app/app.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /install_mt5.sh /entrypoint.sh

EXPOSE 5001 18812

ENTRYPOINT ["/entrypoint.sh"]
