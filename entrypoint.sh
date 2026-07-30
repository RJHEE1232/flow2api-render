#!/usr/bin/env bash
set -euo pipefail
cd /app

# Ensure curl_cffi import won't crash if package absent
python /app/curl_cffi_shim.py || true

python - <<'PY'
from pathlib import Path
import os, re

p = Path("config/setting.toml")
example = Path("config/setting_example.toml")
if not p.exists():
    p.write_text(example.read_text(encoding="utf-8"), encoding="utf-8")
text = p.read_text(encoding="utf-8")

def set_key(src: str, key: str, value: str) -> str:
    pat = rf"(?m)^(\s*{re.escape(key)}\s*=\s*).*$"
    if re.search(pat, src):
        return re.sub(pat, rf"\1{value}", src, count=1)
    return src

def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

port = os.environ.get("PORT", "10000")
admin_user = os.environ.get("ADMIN_USERNAME", "admin")
admin_pass = os.environ.get("ADMIN_PASSWORD", "admin")
api_key = os.environ.get("API_KEY", os.environ.get("FLOW2API_KEY", "han1234"))
captcha = os.environ.get("CAPTCHA_METHOD", "yescaptcha")
yes_key = os.environ.get("YESCAPTCHA_API_KEY", "")
cap_key = os.environ.get("CAPSOLVER_API_KEY", "")
proxy_url = os.environ.get("FLOW2API_PROXY", os.environ.get("PROXY_URL", ""))

text = set_key(text, "admin_username", q(admin_user))
text = set_key(text, "admin_password", q(admin_pass))
text = set_key(text, "api_key", q(api_key))
text = set_key(text, "host", q("0.0.0.0"))
text = set_key(text, "port", str(int(port)))
text = set_key(text, "captcha_method", q(captcha))
if yes_key:
    text = set_key(text, "yescaptcha_api_key", q(yes_key))
if cap_key:
    text = set_key(text, "capsolver_api_key", q(cap_key))
if proxy_url:
    text = set_key(text, "proxy_enabled", "true")
    text = set_key(text, "proxy_url", q(proxy_url))
else:
    text = set_key(text, "proxy_enabled", "false")

p.write_text(text, encoding="utf-8")
print(f"[render-entrypoint] port={port} captcha={captcha} proxy={bool(proxy_url)}")
PY

exec python - <<'PY'
from src.core.config import config
import uvicorn
uvicorn.run("src.main:app", host=config.server_host, port=config.server_port, reload=False)
PY
