"""A small FastAPI app that shuts down gracefully when Docker sends SIGTERM."""

import asyncio
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI

STARTED = time.time()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Runs once at startup: open database connections, load models, ...
    print("startup: ready for traffic", flush=True)
    yield
    # Runs once at shutdown, AFTER uvicorn has stopped accepting new connections
    # and let in-flight requests finish. Close connections, flush buffers here.
    print("shutdown: closing connections, flushing logs", flush=True)
    await asyncio.sleep(0.5)  # pretend cleanup
    print("shutdown: done, bye", flush=True)


app = FastAPI(lifespan=lifespan)


@app.get("/")
def home():
    return {
        "message": "Hello from a production-ready container",
        "uptime_seconds": round(time.time() - STARTED, 1),
    }


@app.get("/slow")
async def slow(seconds: float = 5):
    """A request that takes a while, to show that a graceful shutdown lets it finish."""
    await asyncio.sleep(seconds)
    return {"finished": True, "took": seconds}


@app.get("/health")
def health():
    return {"status": "ok"}
