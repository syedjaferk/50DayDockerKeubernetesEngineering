FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# The same image runs the API and the worker. Compose picks the command.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
