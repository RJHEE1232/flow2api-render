FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PORT=10000
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY main.py /app/main.py
COPY src /app/src
COPY static /app/static
COPY config /app/config
COPY entrypoint.sh /app/entrypoint.sh
COPY curl_cffi_shim.py /app/curl_cffi_shim.py
RUN chmod +x /app/entrypoint.sh && mkdir -p /app/data /app/tmp && cp /app/config/setting_example.toml /app/config/setting.toml
EXPOSE 10000
CMD ["/app/entrypoint.sh"]
