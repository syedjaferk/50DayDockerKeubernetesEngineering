"""Celery worker: takes jobs from Redis, does the slow work, saves the answer in PostgreSQL."""

import os
import time

from celery import Celery
from db import connect

celery = Celery("worker", broker=os.environ["REDIS_URL"])


@celery.task(name="sum_of_squares")
def sum_of_squares(job_id: int, n: int) -> int:
    with connect() as conn:
        conn.execute("UPDATE jobs SET status = 'running' WHERE id = %s", (job_id,))
    time.sleep(3)  # pretend this is slow work
    result = sum(i * i for i in range(1, n + 1))
    with connect() as conn:
        conn.execute(
            "UPDATE jobs SET status = 'done', result = %s WHERE id = %s",
            (result, job_id),
        )
    return result
