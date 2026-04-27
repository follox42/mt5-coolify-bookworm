FROM gmag11/metatrader5_vnc:latest

# gmag11's start.sh uses `-w wine python.exe` switch which was removed in
# mt5linux 1.0+. PyPI latest is 1.0.3 → server fails with "Unknown switch -w".
# Pin both Linux and Wine installs to mt5linux==0.1.9 (last version with -w).
RUN sed -i \
    -e 's|"mt5linux>=0.1.9"|"mt5linux==0.1.9"|g' \
    -e 's|--no-deps mt5linux\b|--no-deps mt5linux==0.1.9|g' \
    /Metatrader/start.sh && \
    grep -E "mt5linux" /Metatrader/start.sh

EXPOSE 3000 8001
