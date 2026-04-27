#!/bin/bash
# Build-time installer: Wine prefix + MT5 + Wine Python + MetaTrader5 lib.
# Base: scottyhardy/docker-wine — Wine staging deja installe et fonctionnel.

set -e

WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export DISPLAY=:99
export WINEARCH=win64

echo "[install] starting Xvfb on :99"
Xvfb :99 -screen 0 1280x1024x16 -ac &
XVFB_PID=$!
sleep 3

echo "[install] init Wine prefix"
wineboot --init
sleep 5

echo "[install] verifying Wine prefix has kernel32.dll"
ls "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" || { echo "[install] FAIL: kernel32.dll missing after wineboot"; exit 1; }

echo "[install] set Wine to win10 mode"
wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

echo "[install] download MT5 Windows installer"
wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /tmp/mt5setup.exe

echo "[install] install MT5 silently (poll up to 6 min for terminal64.exe)"
wine /tmp/mt5setup.exe /auto &
MT5_PID=$!
MT5_BIN="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
for i in $(seq 1 72); do
    if [ -f "$MT5_BIN" ]; then
        echo "[install] MT5 ready after ${i}*5s"
        break
    fi
    sleep 5
done
kill -9 $MT5_PID 2>/dev/null || true
sleep 3

if [ ! -f "$MT5_BIN" ]; then
    echo "[install] FAIL: MT5 install timeout (terminal64.exe not found)"
    exit 1
fi

echo "[install] download Python 3.9 for Wine"
wget -q https://www.python.org/ftp/python/3.9.13/python-3.9.13-amd64.exe -O /tmp/python.exe

echo "[install] install Python in Wine (silent)"
wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1
sleep 15

echo "[install] verify Wine Python"
wine python --version

echo "[install] install MetaTrader5 + rpyc + mt5linux in Wine Python"
wine python -m pip install --upgrade pip wheel setuptools
wine python -m pip install MetaTrader5 rpyc==5.3.1 mt5linux==0.1.9

echo "[install] cleanup"
rm -f /tmp/mt5setup.exe /tmp/python.exe
kill $XVFB_PID 2>/dev/null || true

echo "[install] done — MT5 stack ready"
ls -la "$MT5_BIN"
