import logging

import boto3
from botocore.exceptions import ClientError
from fastapi import HTTPException

from ..config import get_settings
from ..models.device import Device

logger = logging.getLogger(__name__)


def _get_table():
    settings = get_settings()
    kwargs = {"region_name": settings.aws_region}
    if settings.aws_endpoint_url:
        kwargs["endpoint_url"] = settings.aws_endpoint_url
    return boto3.resource("dynamodb", **kwargs).Table(settings.dynamodb_table)


def list_devices() -> list[Device]:
    try:
        response = _get_table().scan()
        return [
            Device(
                device_id=item["device_id"],
                model=item["model"],
                firmware_url=item["firmware_url"],
            )
            for item in response.get("Items", [])
        ]
    except ClientError:
        logger.exception("DynamoDB scan failed")
        raise HTTPException(status_code=500, detail="Storage error")


def create_device(device_id: str, model: str, firmware_url: str) -> Device:
    try:
        _get_table().put_item(
            Item={"device_id": device_id, "model": model, "firmware_url": firmware_url}
        )
        return Device(device_id=device_id, model=model, firmware_url=firmware_url)
    except ClientError:
        logger.exception("DynamoDB put_item failed")
        raise HTTPException(status_code=500, detail="Storage error")
