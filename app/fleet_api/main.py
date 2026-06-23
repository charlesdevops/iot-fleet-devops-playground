from contextlib import asynccontextmanager

from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI  # noqa: E402
from prometheus_fastapi_instrumentator import Instrumentator  # noqa: E402

from .logging import configure_logging  # noqa: E402
from .routers.devices import router as devices_router  # noqa: E402


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_logging()
    yield


app = FastAPI(
    title="Fleet Registry",
    description="Edge device & firmware registry service.",
    version="1.0.0",
    lifespan=lifespan,
)

# Expose Prometheus metrics at /metrics (request count, latency, in-progress, etc.).
Instrumentator().instrument(app).expose(app)

app.include_router(devices_router)


@app.get("/healthz", tags=["health"])
def health() -> dict[str, str]:
    """Liveness/readiness probe target."""
    return {"status": "ok"}
