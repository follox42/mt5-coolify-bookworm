FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEPREFIX=/root/.wine
ENV WINEARCH=win64
ENV DISPLAY=:99
ENV WINEDEBUG=-all
ENV PATH=/root/.local/bin:$PATH

# ---- Wine 10 stable (winehq official Bookworm repo) + 32-bit i386 ----
# CRITICAL: scottyhardy:latest = Wine 11 = MT5 hang ("debugger detected" regression).
# Use winehq-stable on Bookworm = Wine 10.x (proven working with MT5).
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
        wget curl gnupg2 software-properties-common ca-certificates && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install --install-recommends -y winehq-stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Linux side: Python + Xvfb + xdotool + winetricks ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        xvfb x11-utils xdotool imagemagick \
        net-tools iproute2 \
        cabextract winbind p7zip-full unzip \
    && rm -rf /var/lib/apt/lists/*

# winetricks (latest from upstream, not debian outdated package)
RUN wget -q -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /usr/local/bin/winetricks

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

# Verify Wine version (must be 10.x, NOT 11.x)
RUN wine --version

# ---- Scripts (Wine init + MT5 install at runtime, not build-time) ----
# Coolify Custom Docker Run Options must include: --security-opt seccomp=unconfined
COPY install_mt5.sh /install_mt5.sh
COPY app.py /app/app.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /install_mt5.sh /entrypoint.sh

EXPOSE 5001 18812

ENTRYPOINT ["/entrypoint.sh"]
