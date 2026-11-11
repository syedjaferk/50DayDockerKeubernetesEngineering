"""A small API that exposes its own numbers at /metrics for Prometheus."""
import asyncio
import random
import time

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

app = FastAPI()

REQUESTS = Counter("shop_http_requests_total", "Requests served", ["path", "status"])
LATENCY = Histogram("shop_http_request_seconds", "Request time in seconds", ["path"],
                    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5))
IN_FLIGHT = Gauge("shop_http_in_flight", "Requests being handled right now")


@app.middleware("http")
async def measure(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)
    IN_FLIGHT.inc()
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        IN_FLIGHT.dec()
        LATENCY.labels(request.url.path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.url.path, str(status)).inc()


@app.get("/")
async def home():
    return {"hello": "shop"}


@app.get("/slow")
async def slow():
    await asyncio.sleep(random.uniform(0.05, 0.9))
    return {"slept": True}


@app.get("/flaky")
async def flaky():
    if random.random() < 0.3:
        raise HTTPException(500, "random failure")
    return {"ok": True}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
