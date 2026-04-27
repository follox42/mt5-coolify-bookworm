#!/bin/bash
# Runtime entrypoint:
#   1. Start Xvfb (virtual display, headless)
#   2. Start MT5 terminal64.exe under Wine (auto-login if MT5_LOGIN set)
#   3. Start mt5linux RPyC server (under Wine python) — port 18812
#   4. Start FastAPI (Linux python) — port 5000

set +e
echo "[ENTRYPOINT] $(date) — starting MT5 stack"

export DISPLAY=:99
export WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export WINEARCH=win64
export WINEDEBUG=-all,err-toolbar,fixme-all

# 1) Xvfb
Xvfb :99 -screen 0 1280x1024x16 &
sleep 2
echo "[ENTRYPOINT] Xvfb up"

# 2) Verify MT5 binary exists; if not (build-time install failed), retry now
MT5_BIN="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
if [ ! -f "$MT5_BIN" ]; then
    echo "[ENTRYPOINT] MT5 not found at build-time — installing at runtime"
    if [ ! -f /tmp/mt5setup.exe ]; then
        wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /tmp/mt5setup.exe
    fi
    wine /tmp/mt5setup.exe /auto &
    INSTALLER_PID=$!
    for i in $(seq 1 60); do
        [ -f "$MT5_BIN" ] && break
        sleep 5
    done
    kill -9 $INSTALLER_PID 2>/dev/null || true
fi

if [ -f "$MT5_BIN" ]; then
    echo "[ENTRYPOINT] launching MT5 terminal in background"
    if [ -n "$MT5_LOGIN" ] && [ -n "$MT5_PASSWORD" ] && [ -n "$MT5_SERVER" ]; then
        echo "[ENTRYPOINT] auto-login: $MT5_LOGIN @ $MT5_SERVER"
        wine "$MT5_BIN" /portable /login:"$MT5_LOGIN" /password:"$MT5_PASSWORD" /server:"$MT5_SERVER" &
    else
        echo "[ENTRYPOINT] no MT5_LOGIN env — starting without auto-login"
        wine "$MT5_BIN" /portable &
    fi
    sleep 15
else
    echo "[ENTRYPOINT] WARNING: MT5 still not installed — RPyC server will fail"
fi

# 3) mt5linux RPyC server (under Wine python — talks to local MT5 terminal)
echo "[ENTRYPOINT] starting mt5linux RPyC server on :18812"
wine python -m mt5linux --host 0.0.0.0 --port 18812 &
sleep 8

# 4) FastAPI on Linux python (talks to mt5linux RPyC server local)
echo "[ENTRYPOINT] starting FastAPI on :5000"
exec uvicorn --app-dir /app app:app --host 0.0.0.0 --port 5000
