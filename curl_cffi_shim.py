"""Install curl_cffi.requests.AsyncSession shim backed by httpx if curl_cffi is missing.

flow2api imports `from curl_cffi.requests import AsyncSession` at module load.
On free Render we may omit native curl_cffi wheels; this keeps boot working.
TLS fingerprinting will be weaker than real curl_cffi — still enough for admin + health.
"""
from __future__ import annotations

import sys
import types
from typing import Any, Optional


def main() -> None:
    try:
        from curl_cffi.requests import AsyncSession as _  # noqa: F401

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

    class _Resp:
        def __init__(self, r: Any):
            self.status_code = r.status_code
            self.text = r.text
            self.content = r.content
            self.headers = r.headers
            self.url = str(r.url)
            self.cookies = getattr(r, "cookies", {})

        def json(self):
            return self._raw.json()

        # keep ref for json()
        @property
        def _raw(self):
            return self.__dict__.get("__raw")

    def _wrap(r: Any) -> _Resp:
        out = _Resp(r)
        out.__dict__["__raw"] = r
        return out

    class Session:
        def __init__(self, *a, **k):
            # ignore impersonate / proxies kwargs used by curl_cffi
            timeout = k.get("timeout", 60.0)
            self._c = httpx.Client(timeout=timeout, follow_redirects=True, trust_env=False)

        def request(self, method, url, **k):
            k.pop("impersonate", None)
            k.pop("proxies", None)
            proxy = k.pop("proxy", None)
            headers = k.get("headers")
            data = k.get("data")
            json_body = k.get("json")
            timeout = k.get("timeout", 60)
            content = k.get("content", data)
            params = k.get("params")
            files = k.get("files")
            cookies = k.get("cookies")
            client = self._c
            if proxy:
                client = httpx.Client(
                    timeout=timeout,
                    follow_redirects=True,
                    trust_env=False,
                    proxy=proxy,
                )
            try:
                r = client.request(
                    method,
                    url,
                    headers=headers,
                    content=content,
                    json=json_body,
                    params=params,
                    files=files,
                    cookies=cookies,
                    timeout=timeout,
                )
                return _wrap(r)
            finally:
                if proxy and client is not self._c:
                    client.close()

        def get(self, url, **k):
            return self.request("GET", url, **k)

        def post(self, url, **k):
            return self.request("POST", url, **k)

        def put(self, url, **k):
            return self.request("PUT", url, **k)

        def delete(self, url, **k):
            return self.request("DELETE", url, **k)

        def close(self):
            self._c.close()

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            self.close()

    class AsyncSession:
        def __init__(self, *a, **k):
            timeout = k.get("timeout", 60.0)
            self._timeout = timeout
            self._client: Optional[httpx.AsyncClient] = None

        async def __aenter__(self):
            self._client = httpx.AsyncClient(
                timeout=self._timeout,
                follow_redirects=True,
                trust_env=False,
            )
            return self

        async def __aexit__(self, *exc):
            if self._client is not None:
                await self._client.aclose()
                self._client = None

        async def request(self, method, url, **k):
            assert self._client is not None, "AsyncSession used outside async with"
            k.pop("impersonate", None)
            k.pop("proxies", None)
            proxy = k.pop("proxy", None)
            headers = k.get("headers")
            data = k.get("data")
            json_body = k.get("json")
            timeout = k.get("timeout", self._timeout)
            content = k.get("content", data)
            params = k.get("params")
            files = k.get("files")
            cookies = k.get("cookies")

            if proxy:
                async with httpx.AsyncClient(
                    timeout=timeout,
                    follow_redirects=True,
                    trust_env=False,
                    proxy=proxy,
                ) as c:
                    r = await c.request(
                        method,
                        url,
                        headers=headers,
                        content=content,
                        json=json_body,
                        params=params,
                        files=files,
                        cookies=cookies,
                        timeout=timeout,
                    )
                    return _wrap(r)

            r = await self._client.request(
                method,
                url,
                headers=headers,
                content=content,
                json=json_body,
                params=params,
                files=files,
                cookies=cookies,
                timeout=timeout,
            )
            return _wrap(r)

        async def get(self, url, **k):
            return await self.request("GET", url, **k)

        async def post(self, url, **k):
            return await self.request("POST", url, **k)

        async def put(self, url, **k):
            return await self.request("PUT", url, **k)

        async def delete(self, url, **k):
            return await self.request("DELETE", url, **k)

        async def close(self):
            if self._client is not None:
                await self._client.aclose()
                self._client = None

    req.Session = Session
    req.AsyncSession = AsyncSession
    m.requests = req
    sys.modules["curl_cffi"] = m
    sys.modules["curl_cffi.requests"] = req
    print("[shim] installed httpx-backed curl_cffi AsyncSession shim")


if __name__ == "__main__":
    main()
