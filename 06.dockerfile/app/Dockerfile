# 1. Base Image
FROM python:3.12-slim

ARG APP_VERSION

# 2. Environemnt Variables
ENV APP_ENV=${APP_VERSION} \
    GREETING="Hello Docker"

# 3. Working Directory inside the container.
WORKDIR /application



# 4. Copy Installation files.
COPY requirements.txt .

# 5. Install . Only during image build.
RUN pip install -r requirements.txt

# 6. Project files
COPY app.py .

# 7. Expose the port. Its for another developer.
EXPOSE 5111

# 8. Run the Application : Only for container
# # PID - 1
CMD ["python", "app.py"]
