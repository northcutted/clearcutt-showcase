"""HTTP API: product listing plus supplier feed validation."""

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

# Imported at startup on purpose: if the run image lacks the libxml2 this was
# built against, the service fails to start (and the smoke test fails).
from catalog import _feeds

PRODUCTS = [
    {"sku": "TEA-001", "name": "Sencha", "cents": 1250},
    {"sku": "TEA-002", "name": "Hojicha", "cents": 1400},
    {"sku": "MUG-001", "name": "Stoneware mug", "cents": 2200},
]


async def healthz(request: Request) -> JSONResponse:
    compiled, loaded = _feeds.libxml_version()
    return JSONResponse({"status": "ok", "service": "catalog", "libxml2": {"compiled": compiled, "loaded": loaded}})


async def products(request: Request) -> JSONResponse:
    return JSONResponse(PRODUCTS)


async def validate_feed(request: Request) -> JSONResponse:
    ok, detail = _feeds.validate(await request.body())
    if ok:
        return JSONResponse({"valid": True, "items": detail})
    return JSONResponse({"valid": False, "error": detail.strip()}, status_code=422)


app = Starlette(
    routes=[
        Route("/healthz", healthz),
        Route("/products", products),
        Route("/feeds/validate", validate_feed, methods=["POST"]),
    ]
)
