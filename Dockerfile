FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
ENV DISPLAY=:99
ENV WINEDEBUG=-all,err-toolbar,fixme-all
ENV PATH=/root/.local/bin:$PATH

# Enable contrib (where some Wine deps live in Bookworm)
RUN sed -i 's/ main$/ main contrib non-free/' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/ main$/ main contrib non-free/' /etc/apt/sources.list 2>/dev/null || true

# 32-bit support REQUIRED for Wine + MT5
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates wget curl xz-utils \
        wine wine64 wine32 \
        xvfb x11vnc \
        python3 python3-pip python3-venv \
        cabextract fonts-wine \
    && rm -rf /var/lib/apt/lists/*

# Verify Wine works (Bookworm ships only /usr/bin/wine — handles both 64/32 via WINEARCH)
RUN wine --version && which wine

# ---- Python (Linux side, runs FastAPI + talks to mt5linux RPyC) ----
RUN pip3 install --no-cache-dir --break-system-packages \
        rpyc==5.3.1 \
        mt5linux==0.1.9 \
        fastapi==0.115.0 \
        "uvicorn[standard]==0.32.0" \
        pydantic==2.9.0 \
        httpx==0.27.0

# ---- Pre-bake Wine prefix + Python-in-Wine + MT5 + MetaTrader5 lib ----
COPY install_mt5.sh /install_mt5.sh
RUN chmod +x /install_mt5.sh && /install_mt5.sh

# Copy app + entrypoint
COPY app.py /app/app.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5000 18812

ENTRYPOINT ["/entrypoint.sh"]
