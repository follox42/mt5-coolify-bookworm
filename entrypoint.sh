#!/bin/bash
# Runtime: 1) Xvfb, 2) install MT5 if first boot, 3) MT5 terminal, 4) RPyC server, 5) FastAPI
# Build-time wineboot fails on Coolify (seccomp restrictions). Runtime needs:
#   custom_docker_run_options = --security-opt seccomp=unconfined

set +e
echo "[ENTRYPOINT] $(date) — starting MT5 stack"

export DISPLAY=:99
export WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export WINEARCH=win64
export WINEDEBUG=-all,err-toolbar,fixme-all

MT5_BIN="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
INSTALL_MARKER="$WINEPREFIX/.mt5-install-done"

# 1) Xvfb (virtual display)
Xvfb :99 -screen 0 1280x1024x16 -ac &
sleep 3
echo "[ENTRYPOINT] Xvfb up"

# 2) First-boot install (Wine prefix + MT5 + Python-in-Wine + MetaTrader5 lib)
if [ ! -f "$INSTALL_MARKER" ] || [ ! -f "$MT5_BIN" ]; then
    echo "[ENTRYPOINT] First boot — running /install_mt5.sh"
    /install_mt5.sh
    if [ $? -ne 0 ]; then
        echo "[ENTRYPOINT] FATAL: install_mt5.sh failed."
        echo "[ENTRYPOINT] Hint: ensure Coolify Custom Docker Run Options contains:"
        echo "[ENTRYPOINT]   --security-opt seccomp=unconfined"
        exit 1
    fi
    touch "$INSTALL_MARKER"
fi

if [ ! -f "$MT5_BIN" ]; then
    echo "[ENTRYPOINT] FATAL: MT5 still not installed after install_mt5.sh"
    exit 1
fi

# 3) Start MT5 terminal (auto-login si env vars presents)
if [ -n "$MT5_LOGIN" ] && [ -n "$MT5_PASSWORD" ] && [ -n "$MT5_SERVER" ]; then
    echo "[ENTRYPOINT] auto-login: $MT5_LOGIN @ $MT5_SERVER"
    wine "$MT5_BIN" /portable /login:"$MT5_LOGIN" /password:"$MT5_PASSWORD" /server:"$MT5_SERVER" &
else
    echo "[ENTRYPOINT] no MT5_LOGIN env — starting without auto-login"
    wine "$MT5_BIN" /portable &
fi
sleep 15

# 4) mt5linux RPyC server (Wine python, talks to local MT5 terminal)
echo "[ENTRYPOINT] starting mt5linux RPyC server on :18812"
wine python -m mt5linux --host 0.0.0.0 --port 18812 &
sleep 8

# 5) FastAPI on Linux python (talks to mt5linux RPyC server local)
echo "[ENTRYPOINT] starting FastAPI on :5001"
exec uvicorn --app-dir /app app:app --host 0.0.0.0 --port 5001
