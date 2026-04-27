#!/bin/bash
# Build-time installer: prepares Wine prefix, installs Wine Python, MetaTrader5 lib, and MT5.
# Runs inside Docker build under root, with a virtual X (Xvfb) on :99.

set -e

WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export DISPLAY=:99
export WINEARCH=win64

echo "[install] starting Xvfb"
Xvfb :99 -screen 0 1280x1024x16 &
XVFB_PID=$!
sleep 2

echo "[install] init Wine prefix"
wine wineboot --init || true
sleep 5

echo "[install] set Wine to win10 mode"
wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f || true

echo "[install] download MT5 Windows installer"
wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /tmp/mt5setup.exe

echo "[install] install MT5 via Wine (/auto mode)"
wine /tmp/mt5setup.exe /auto &
MT5_INSTALLER_PID=$!
# Poll up to 6 min for terminal64.exe presence
for i in $(seq 1 72); do
    if [ -f "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
        echo "[install] MT5 installed after ${i}*5s"
        break
    fi
    sleep 5
done
kill -9 $MT5_INSTALLER_PID 2>/dev/null || true

echo "[install] download Python 3.9 for Wine"
wget -q https://www.python.org/ftp/python/3.9.13/python-3.9.13-amd64.exe -O /tmp/python.exe

echo "[install] install Python inside Wine (silent)"
wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1 || true
sleep 10

echo "[install] install MetaTrader5 + rpyc + mt5linux inside Wine Python"
wine python -m pip install --upgrade pip wheel setuptools 2>/dev/null || true
wine python -m pip install MetaTrader5 rpyc==5.3.1 mt5linux==0.1.9 2>/dev/null || true

echo "[install] cleanup"
rm -f /tmp/mt5setup.exe /tmp/python.exe
kill $XVFB_PID 2>/dev/null || true

echo "[install] done"
ls -la "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" 2>/dev/null || \
    echo "[install] WARNING: terminal64.exe not found — runtime will retry"
