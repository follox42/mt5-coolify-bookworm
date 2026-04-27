FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
ENV DISPLAY=:99
ENV WINEDEBUG=-all,err-toolbar,fixme-all
ENV PATH=/root/.local/bin:$PATH

# 32-bit support is REQUIRED for Wine + MT5 (some MT5 installers still need 32-bit DLLs)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates wget curl xz-utils \
        wine wine64 wine32 winbind winetricks \
        xvfb x11vnc \
        python3 python3-pip python3-venv \
        cabextract \
    && rm -rf /var/lib/apt/lists/*

# Verify Wine works
RUN wine64 --version

# ---- Python (Linux side, runs FastAPI + talks to mt5linux RPyC) ----
RUN pip3 install --no-cache-dir --break-system-packages \
        rpyc==5.3.1 \
        mt5linux==0.1.9 \
        fastapi==0.115.0 \
        uvicorn[standard]==0.32.0 \
        pydantic==2.9.0 \
        httpx==0.27.0

# ---- Pre-bake Wine prefix + Python (inside Wine) + MT5 + MetaTrader5 lib ----
# This is done at BUILD time so the runtime image is ready.
# /tmp will hold installers; remove after.
COPY install_mt5.sh /install_mt5.sh
RUN chmod +x /install_mt5.sh && /install_mt5.sh

# Copy app + entrypoint
COPY app.py /app/app.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5000 18812

ENTRYPOINT ["/entrypoint.sh"]
