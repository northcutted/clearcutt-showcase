"""Run the catalog service: python3 -m catalog."""

import os

import uvicorn

from catalog import _feeds
from catalog.app import app

if __name__ == "__main__":
    compiled, loaded = _feeds.libxml_version()
    print(f"catalog: libxml2 compiled {compiled}, loaded {loaded}", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), log_level="info")
