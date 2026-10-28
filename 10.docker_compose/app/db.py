"""Tiny PostgreSQL helper shared by the API and the worker."""

import os
import time

import psycopg

DB_URL = os.environ["DATABASE_URL"]


def connect(retries=30):
    """Open a connection; wait for the database if it is still starting."""
    for attempt in range(1, retries + 1):
        try:
            return psycopg.connect(DB_URL, autocommit=True)
        except psycopg.OperationalError as err:
            print(
                f"database not ready (attempt {attempt}): {err}".splitlines()[0],
                flush=True,
            )
            time.sleep(1)
    raise RuntimeError("database never became ready")


def init_schema():
    with connect() as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS jobs (
                   id SERIAL PRIMARY KEY,
                   n INTEGER NOT NULL,
                   status TEXT NOT NULL DEFAULT 'queued',
                   result BIGINT
               )"""
        )
