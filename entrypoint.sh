#!/bin/bash
# Runtime: Xvfb + MT5 terminal (auto-login si MT5_LOGIN set) + mt5linux RPyC server + FastAPI

set +e
echo "[ENTRYPOINT] $(date) — starting MT5 stack"

export DISPLAY=:99
export WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export WINEARCH=win64
export WINEDEBUG=-all,err-toolbar,fixme-all

# 1) Xvfb
Xvfb :99 -screen 0 1280x1024x16 -ac &
sleep 3
echo "[ENTRYPOINT] Xvfb up"

# 2) Verify MT5 binary (build-time install must have succeeded)
MT5_BIN="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
if [ ! -f "$MT5_BIN" ]; then
    echo "[ENTRYPOINT] FATAL: MT5 not installed (build-time install failed)."
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
