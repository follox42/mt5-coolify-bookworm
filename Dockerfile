FROM gmag11/metatrader5_vnc:latest

# gmag11's start.sh runs `mt5linux ... -w wine python.exe` but the -w switch
# was REMOVED in mt5linux 1.0+. PyPI latest = 1.0.3 → "Unknown switch -w".
# Pin to 0.1.9 (last with -w) on BOTH Linux and Wine sides + force-reinstall
# (since the persistent /config volume already has 1.0.3 from previous boot).
RUN sed -i \
    -e 's/if ! is_python_package_installed "mt5linux"; then/if true; then/g' \
    -e 's/if ! is_wine_python_package_installed "mt5linux"; then/if true; then/g' \
    -e 's/"mt5linux>=0.1.9"/"mt5linux==0.1.9" --force-reinstall/g' \
    -e 's/--no-deps mt5linux\b/--no-deps --force-reinstall mt5linux==0.1.9/g' \
    /Metatrader/start.sh && \
    grep -E "mt5linux|is_.*_installed" /Metatrader/start.sh | head -10

EXPOSE 3000 8001
