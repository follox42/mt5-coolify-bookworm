FROM gmag11/metatrader5_vnc:latest

# gmag11/metatrader5_vnc baked-in:
#   - linuxserver/baseimage-kasmvnc (real X server via KasmVNC)
#   - wine-stable + mono + Python in Wine + MetaTrader5 + rpyc + mt5linux
#   - VNC web server on port 3000 (browser access to MT5 GUI)
#   - mt5linux RPyC server on port 8001
#   - first-boot install of MT5 via Wine (proven working, 306+ stars)
#
# Env vars expected (set in Coolify):
#   CUSTOM_USER, PASSWORD       — KasmVNC web auth
#   MT5_CMD_OPTIONS             — passed to MT5 terminal at startup
#
# Volumes (Coolify):
#   /config                     — MT5 prefix + persistent state (Wine prefix lives here)

EXPOSE 3000 8001
