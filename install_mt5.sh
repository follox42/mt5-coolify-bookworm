#!/bin/bash
# Runtime installer: Wine prefix + MT5 + Wine Python + MetaTrader5 lib.
# Called by entrypoint.sh on first boot. DISPLAY/Xvfb already set up by entrypoint.

set -e

WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export DISPLAY="${DISPLAY:-:99}"
export WINEARCH=win64

# Make sure DISPLAY is up; if not, bring up our own
if ! xdpyinfo >/dev/null 2>&1; then
    echo "[install] no DISPLAY — starting our own Xvfb on :99"
    Xvfb :99 -screen 0 1280x1024x16 -ac &
    XVFB_OWN_PID=$!
    sleep 3
fi

echo "[install] init Wine prefix"
wineboot --init
sleep 5

echo "[install] verifying Wine prefix has kernel32.dll"
ls "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" || { echo "[install] FAIL: kernel32.dll missing after wineboot"; exit 1; }

echo "[install] set Wine to win10 mode"
wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

echo "[install] download MT5 Windows installer"
wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /tmp/mt5setup.exe
ls -la /tmp/mt5setup.exe

echo "[install] disk free + mem before MT5 install:"
df -h "$WINEPREFIX" | tail -1
free -m | head -2

echo "[install] install MT5 silently (poll up to 15 min for terminal64.exe)"
wine /tmp/mt5setup.exe /auto &
MT5_PID=$!
MT5_BIN="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
MT5_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

# Poll up to 15 min, log progress every 60s
for i in $(seq 1 180); do
    if [ -f "$MT5_BIN" ]; then
        echo "[install] MT5 ready after ${i}*5s"
        break
    fi
    if [ $((i % 12)) -eq 0 ]; then
        elapsed=$((i * 5))
        echo "[install] still waiting (${elapsed}s)..."
        ls -la "$MT5_DIR" 2>/dev/null | head -5 || echo "  (MT5 dir not yet created)"
        ps -p $MT5_PID > /dev/null 2>&1 && echo "  (installer process alive)" || echo "  (installer process DEAD)"
    fi
    sleep 5
done

# Don't kill aggressively — let installer finish if it's almost done
if [ ! -f "$MT5_BIN" ]; then
    echo "[install] FAIL after 15 min: MT5 install timeout (terminal64.exe not found)"
    echo "[install] last state of MT5 dir:"
    ls -la "$MT5_DIR" 2>/dev/null || echo "  (does not exist)"
    echo "[install] last 50 lines of dmesg (OOM check):"
    dmesg 2>/dev/null | tail -50 || true
    kill -9 $MT5_PID 2>/dev/null || true
    exit 1
fi

# Wait a few seconds for installer to fully write files
sleep 5
kill -9 $MT5_PID 2>/dev/null || true

echo "[install] download Python 3.9 for Wine"
wget -q https://www.python.org/ftp/python/3.9.13/python-3.9.13-amd64.exe -O /tmp/python.exe

echo "[install] install Python in Wine (silent)"
wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1
sleep 20

echo "[install] verify Wine Python"
wine python --version

echo "[install] install MetaTrader5 + rpyc + mt5linux in Wine Python"
wine python -m pip install --upgrade pip wheel setuptools
wine python -m pip install MetaTrader5 rpyc==5.3.1 mt5linux==0.1.9

echo "[install] cleanup"
rm -f /tmp/mt5setup.exe /tmp/python.exe
[ -n "$XVFB_OWN_PID" ] && kill $XVFB_OWN_PID 2>/dev/null || true

echo "[install] done — MT5 stack ready"
ls -la "$MT5_BIN"
