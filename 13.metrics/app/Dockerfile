FROM python:3.12-slim
RUN useradd --system --uid 10001 --no-create-home appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
USER 10001
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
