import logging

from pythonjsonlogger import jsonlogger


def configure_logging(level: int = logging.INFO) -> None:
    """Emit structured single-line JSON logs on stdout.

    Replaces the default uvicorn/root handlers so every log line is machine-parsable
    (suitable for shipping to Loki/CloudWatch/ELK).
    """
    handler = logging.StreamHandler()
    handler.setFormatter(
        jsonlogger.JsonFormatter(
            "%(asctime)s %(levelname)s %(name)s %(message)s",
            rename_fields={"asctime": "timestamp", "levelname": "level"},
        )
    )

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)

    # Route uvicorn's own loggers through the JSON handler too.
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        log = logging.getLogger(name)
        log.handlers = [handler]
        log.propagate = False
