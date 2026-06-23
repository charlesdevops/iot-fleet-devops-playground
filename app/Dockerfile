FROM python:3.12-slim AS builder

RUN pip install --no-cache-dir poetry==1.8.3

WORKDIR /build
COPY pyproject.toml poetry.lock* ./
RUN poetry export --without-hashes --without=dev -f requirements.txt -o requirements.txt

FROM python:3.12-slim

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=builder /build/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY fleet_api/ ./fleet_api/

EXPOSE 8000

USER 1000

CMD ["gunicorn", "fleet_api.main:app", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "30", "--access-logfile", "-"]
