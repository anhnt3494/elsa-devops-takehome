# syntax=docker/dockerfile:1.7
FROM python:3.14.9-alpine3.24 AS deps
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --require-hashes --target /deps -r requirements.txt

FROM python:3.14.9-alpine3.24
ENV PYTHONPATH=/deps \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=deps /deps /deps
COPY main.py /app/main.py
RUN python -m compileall -q /deps /app
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["python", "/app/main.py"]
