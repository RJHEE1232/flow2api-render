"""Install a minimal curl_cffi.requests.Session shim backed by httpx if missing."""
from __future__ import annotations

import sys
import types


def main() -> None:
    try:
        import curl_cffi  # noqa: F401
        print("[shim] curl_cffi present")
        return
    except Exception:
        pass

    try:
        import httpx
    except Exception as e:
        print("[shim] httpx missing, cannot shim:", e)
        return

    m = types.ModuleType("curl_cffi")
    req = types.ModuleType("curl_cffi.requests")

    class Session:
        def __init__(self, *a, **k):
            self._c = httpx.Client(timeout=60.0, follow_redirects=True)

        def request(self, method, url, **k):
            headers = k.get("headers")
            data = k.get("data")
            json_body = k.get("json")
            timeout = k.get("timeout", 60)
            r = self._c.request(
                method,
                url,
                headers=headers,
                content=data,
                json=json_body,
                timeout=timeout,
            )

            class Resp:
                def __init__(self, r):
                    self.status_code = r.status_code
                    self.text = r.text
                    self.content = r.content
                    self.headers = r.headers
                    self.url = str(r.url)

                def json(self):
                    return r.json()

            return Resp(r)

        def get(self, url, **k):
            return self.request("GET", url, **k)

        def post(self, url, **k):
            return self.request("POST", url, **k)

        def close(self):
            self._c.close()

    req.Session = Session
    m.requests = req
    sys.modules["curl_cffi"] = m
    sys.modules["curl_cffi.requests"] = req
    print("[shim] installed httpx-backed curl_cffi shim")


if __name__ == "__main__":
    main()
