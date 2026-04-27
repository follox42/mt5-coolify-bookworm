#!/bin/bash
# Runtime installer modeled on gmag11/MetaTrader5-Docker (proven working).
# Critical fix vs previous attempts: install wine-mono FIRST, before MT5 setup.
# MT5 setup hangs without Mono (calls mscoree.dll that doesn't exist).

set -e

WINEPREFIX="${WINEPREFIX:-/root/.wine}"
export DISPLAY="${DISPLAY:-:99}"
export WINEARCH=win64
export WINEDEBUG=-all

echo "[install] === ENV INFO ==="
echo "[install] wine version: $(wine --version 2>&1)"
echo "[install] which wine: $(which wine)"
echo "[install] WINEPREFIX: $WINEPREFIX"
echo "[install] DISPLAY: $DISPLAY"
echo "[install] CPU flags: $(grep -oE 'avx[0-9]*|bmi[0-9]*|fma' /proc/cpuinfo | sort -u | tr '\n' ' ')"
echo "[install] ================="

MONO_URL="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
PYTHON_URL="https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
MT5_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

MT5_BIN="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

# Make sure DISPLAY is up
if ! xdpyinfo >/dev/null 2>&1; then
    echo "[install] no DISPLAY — starting our own Xvfb on :99"
    Xvfb :99 -screen 0 1280x1024x16 -ac &
    XVFB_OWN_PID=$!
    sleep 3
fi

# ---- [1/5] Install wine-mono (CRITICAL — without it MT5 setup hangs silently) ----
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    echo "[install] [1/5] downloading wine-mono..."
    curl -L -o /tmp/mono.msi "$MONO_URL"
    ls -la /tmp/mono.msi
    echo "[install] [1/5] installing wine-mono via msiexec /qn (this initializes Wine prefix too)..."
    WINEDLLOVERRIDES=mscoree=d wine msiexec /i /tmp/mono.msi /qn
    rm -f /tmp/mono.msi
    echo "[install] [1/5] wine-mono installed."
else
    echo "[install] [1/5] wine-mono already present, skipping."
fi

# Verify Wine prefix is healthy
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
    echo "[install] FAIL: kernel32.dll missing after Mono install"
    exit 1
fi
echo "[install] Wine prefix OK (kernel32.dll present)"

# ---- [2/5] Set Wine to win10 mode ----
wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
echo "[install] [2/5] Wine version set to win10"

# ---- [2.5/5] winetricks deps (corefonts + vcrun2019 — required by MT5 stub) ----
if [ ! -f "$WINEPREFIX/.winetricks-done" ]; then
    echo "[install] [2.5/5] installing winetricks deps (corefonts vcrun2019)..."
    winetricks -q corefonts vcrun2019 2>&1 | tail -20 || echo "  winetricks had warnings (continuing)"
    touch "$WINEPREFIX/.winetricks-done"
else
    echo "[install] [2.5/5] winetricks deps already done, skipping."
fi

# ---- [3/5] Install MT5 ----
if [ ! -f "$MT5_BIN" ]; then
    echo "[install] [3/5] downloading MT5 setup..."
    curl -sSL -o /tmp/mt5setup.exe "$MT5_URL"
    ls -la /tmp/mt5setup.exe

    echo "[install] [3/5] connectivity probe to MQL5 CDN:"
    curl -sS -m 8 -o /dev/null -w "  HTTP=%{http_code} time=%{time_total}s\n" "$MT5_URL"

    echo "[install] [3/5] installing MT5 via wine /auto (capture stderr)..."
    # Capture wine output to /tmp/wine-mt5.log so we see WHY it exits early
    wine /tmp/mt5setup.exe /auto >/tmp/wine-mt5.log 2>&1 &
    MT5_PID=$!
    # gmag11 uses simple `wait` — let installer finish naturally
    # We add a 20-min safety timeout + log every 60s
    for i in $(seq 1 240); do
        if ! ps -p $MT5_PID > /dev/null 2>&1; then
            echo "[install] MT5 installer process exited after $((i * 5))s"
            break
        fi
        if [ -f "$MT5_BIN" ]; then
            echo "[install] terminal64.exe appeared after $((i * 5))s"
            break
        fi
        if [ $((i % 12)) -eq 0 ]; then
            elapsed=$((i * 5))
            rss=$(ps -o rss= -p $MT5_PID 2>/dev/null | awk '{print int($1/1024)}')
            echo "[install] still installing ${elapsed}s (PID $MT5_PID: ${rss}MB RSS)"
        fi
        sleep 5
    done
    # Cleanup if still running
    kill -9 $MT5_PID 2>/dev/null || true
    rm -f /tmp/mt5setup.exe
    sleep 3

    if [ ! -f "$MT5_BIN" ]; then
        echo "[install] FAIL: terminal64.exe still missing after MT5 install"
        echo "[install] === wine stderr/stdout from MT5 install ==="
        cat /tmp/wine-mt5.log 2>/dev/null | tail -100 || echo "  (no wine log)"
        echo "[install] === Program Files contents ==="
        ls -la "$WINEPREFIX/drive_c/Program Files/" 2>/dev/null || echo "  (Program Files dir missing)"
        echo "[install] === Wine prefix recent files ==="
        find "$WINEPREFIX/drive_c" -newer /tmp/mt5setup.exe -type f 2>/dev/null | head -20
        exit 1
    fi
    echo "[install] [3/5] MT5 installed at $MT5_BIN"
else
    echo "[install] [3/5] MT5 already installed, skipping."
fi

# ---- [4/5] Install Python in Wine ----
if ! wine python --version >/dev/null 2>&1; then
    echo "[install] [4/5] downloading Python 3.9 for Wine..."
    curl -L -o /tmp/python.exe "$PYTHON_URL"
    echo "[install] [4/5] installing Python (silent)..."
    wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1
    rm -f /tmp/python.exe
    sleep 10
    wine python --version
    echo "[install] [4/5] Python in Wine installed"
else
    echo "[install] [4/5] Python in Wine already present, skipping."
fi

# ---- [5/5] Install MetaTrader5 + rpyc + mt5linux in Wine Python ----
echo "[install] [5/5] installing MetaTrader5 + rpyc + mt5linux in Wine Python..."
wine python -m pip install --upgrade --no-cache-dir pip wheel setuptools
wine python -m pip install --no-cache-dir MetaTrader5 rpyc==5.3.1 "mt5linux>=0.1.9"

[ -n "$XVFB_OWN_PID" ] && kill $XVFB_OWN_PID 2>/dev/null || true
echo "[install] DONE — MT5 stack ready"
ls -la "$MT5_BIN"
