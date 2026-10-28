"""FastAPI front door: counts visits in Redis, stores jobs in PostgreSQL, queues work for Celery."""

import os
import socket

import db
import redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from worker import celery

app = FastAPI(title="Compose demo")
cache = redis.Redis.from_url(os.environ["REDIS_URL"], decode_responses=True)


@app.on_event("startup")
def startup():
    db.init_schema()


class JobIn(BaseModel):
    n: int


@app.get("/")
def home():
    return {"served_by": socket.gethostname(), "visits": cache.incr("visits")}


@app.post("/jobs", status_code=202)
def create_job(job: JobIn):
    with db.connect() as conn:
        job_id = conn.execute(
            "INSERT INTO jobs (n) VALUES (%s) RETURNING id", (job.n,)
        ).fetchone()[0]
    celery.send_task("sum_of_squares", args=[job_id, job.n])
    return {"id": job_id, "status": "hi bro"}


@app.get("/jobs/{job_id}")
def get_job(job_id: int):
    with db.connect() as conn:
        row = conn.execute(
            "SELECT id, n, status, result FROM jobs WHERE id = %s", (job_id,)
        ).fetchone()
    if row is None:
        raise HTTPException(404, "no such job")
    return dict(zip(("id", "n", "status", "result"), row))
