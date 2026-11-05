"""One-shot job: create the tables, then exit. Compose runs it before the API starts."""
import db

db.init_schema()
print("schema ready", flush=True)
