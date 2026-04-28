FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# mt5linux 0.1.9 has very tight version pins; use --no-deps and provide compatible deps separately
RUN pip install --no-cache-dir \
        fastapi==0.115.0 \
        "uvicorn[standard]==0.32.0" \
        pydantic==2.9.0 \
        rpyc==5.0.1 \
        plumbum==1.7.0 \
    && pip install --no-cache-dir --no-deps mt5linux==0.1.9

COPY app.py /app/app.py

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
