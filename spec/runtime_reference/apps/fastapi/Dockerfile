FROM python:3.12.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --no-deps -r requirements.txt && pip check
COPY src ./src
COPY dump.py .
ENV PYTHONPATH=/app/src
ENTRYPOINT ["python", "dump.py"]
