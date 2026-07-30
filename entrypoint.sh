#!/usr/bin/env bash
set -euo pipefail
cd /app

# Install shim into THIS process tree's python path permanently via sitecustomize-like file
python /app/curl_cffi_shim.py || true
# Persist shim for child imports: write a tiny bootstrap module import path
python - <<'PY'
import sys
from pathlib import Path
# Ensure shim runs as early import hook for subsequent python -c / uvicorn workers
sitecustomize = Path("/usr/local/lib/python3.11/site-packages/sitecustomize.py")
hook = '''
try:
    import curl_cffi  # noqa: F401
except Exception:
    try:
        import runpy
        runpy.run_path("/app/curl_cffi_shim.py", run_name="__main__")
    except Exception as e:
        print("[sitecustomize] curl_cffi shim failed:", e)
'''
# append once
text = sitecustomize.read_text(encoding="utf-8") if sitecustomize.exists() else ""
if "curl_cffi_shim" not in text and "curl_cffi shim" not in text:
    sitecustomize.write_text(text + "\n" + hook, encoding="utf-8")
    print("[render-entrypoint] sitecustomize hook installed")
else:
    print("[render-entrypoint] sitecustomize hook already present")
PY

python - <<'PY'
from pathlib import Path
import os

port = int(os.environ.get("PORT", "10000"))
admin_user = os.environ.get("ADMIN_USERNAME", "admin")
admin_pass = os.environ.get("ADMIN_PASSWORD", "admin")
api_key = os.environ.get("API_KEY", os.environ.get("FLOW2API_KEY", "han1234"))
captcha = os.environ.get("CAPTCHA_METHOD", "yescaptcha")
yes_key = os.environ.get("YESCAPTCHA_API_KEY", "")
cap_key = os.environ.get("CAPSOLVER_API_KEY", "")
proxy_url = os.environ.get("FLOW2API_PROXY", os.environ.get("PROXY_URL", ""))
proxy_enabled = "true" if proxy_url else "false"

def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

text = f"""
[global]
api_key = {q(api_key)}
admin_username = {q(admin_user)}
admin_password = {q(admin_pass)}

[flow]
labs_base_url = "https://labs.google/fx/api"
api_base_url = "https://aisandbox-pa.googleapis.com/v1"
timeout = 120
max_retries = 3
image_request_timeout = 40
image_timeout_retry_count = 1
image_timeout_retry_delay = 0.8
image_timeout_use_media_proxy_fallback = true
image_prefer_media_proxy = false
image_slot_wait_timeout = 480
image_launch_soft_limit = 20
image_launch_wait_timeout = 480
image_launch_stagger_ms = 0
video_slot_wait_timeout = 480
video_launch_soft_limit = 20
video_launch_wait_timeout = 480
video_launch_stagger_ms = 0
poll_interval = 3.0
max_poll_attempts = 200

[server]
host = "0.0.0.0"
port = {port}

[debug]
enabled = false
log_requests = true
log_responses = true
mask_token = true

[proxy]
proxy_enabled = {proxy_enabled}
proxy_url = {q(proxy_url)}

[generation]
image_timeout = 300
video_timeout = 1500

[call_logic]
call_mode = "default"

[admin]
error_ban_threshold = 3

[cache]
enabled = false
timeout = 7200
base_url = ""

[captcha]
captcha_method = {q(captcha)}
browser_recaptcha_settle_seconds = 3.0
browser_count = 1
browser_captcha_max_retries = 5
browser_captcha_generation_retries = 6
personal_project_pool_size = 4
personal_max_resident_tabs = 5
browser_personal_fresh_restart_every_n_solves = 10
personal_idle_tab_ttl_seconds = 600
yescaptcha_api_key = {q(yes_key)}
yescaptcha_base_url = "https://api.yescaptcha.com"
yescaptcha_task_type = "RecaptchaV3TaskProxylessM1S9"
remote_browser_base_url = ""
remote_browser_api_key = ""
remote_browser_timeout = 60
capsolver_api_key = {q(cap_key)}
capsolver_base_url = "https://api.capsolver.com"
"""
Path("config").mkdir(parents=True, exist_ok=True)
Path("config/setting.toml").write_text(text.strip() + "\n", encoding="utf-8")
import tomli
tomli.loads(text)
print(f"[render-entrypoint] port={port} captcha={captcha} proxy={bool(proxy_url)}")
PY

# re-apply shim in case sitecustomize path differs
python /app/curl_cffi_shim.py || true

exec python - <<'PY'
# force shim before app import
import runpy
try:
    from curl_cffi.requests import AsyncSession  # noqa: F401
except Exception:
    runpy.run_path("/app/curl_cffi_shim.py", run_name="__main__")
    from curl_cffi.requests import AsyncSession  # noqa: F401

from src.core.config import config
import uvicorn
uvicorn.run("src.main:app", host=config.server_host, port=config.server_port, reload=False)
PY
