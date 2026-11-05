"""PostgreSQL helper. The password is read from a secret FILE, never from an environment variable."""
import os
import time

import psycopg


def db_url():
    with open(os.environ["DB_PASSWORD_FILE"]) as f:       # /run/secrets/db_password
        password = f.read().strip()
    return (f"postgresql://{os.environ['DB_USER']}:{password}"
            f"@{os.environ.get('DB_HOST', 'db')}:5432/{os.environ['DB_NAME']}")


def connect(retries=30):
    for attempt in range(1, retries + 1):
        try:
            return psycopg.connect(db_url(), autocommit=True)
        except psycopg.OperationalError as err:
            print(f"database not ready (attempt {attempt}): {err}".splitlines()[0], flush=True)
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
