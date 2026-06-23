import logging

import boto3
from botocore.exceptions import ClientError
from fastapi import HTTPException

from ..config import get_settings

logger = logging.getLogger(__name__)


def upload_firmware(file_bytes: bytes, filename: str, content_type: str) -> str:
    settings = get_settings()
    bucket = settings.s3_bucket
    region = settings.aws_region
    endpoint = settings.aws_endpoint_url

    kwargs = {"region_name": region}
    if endpoint:
        kwargs["endpoint_url"] = endpoint

    s3 = boto3.client("s3", **kwargs)

    try:
        s3.put_object(Bucket=bucket, Key=filename, Body=file_bytes, ContentType=content_type)
    except ClientError:
        logger.exception("S3 upload failed")
        raise HTTPException(status_code=500, detail="Storage error")

    if endpoint:
        return f"{endpoint}/{bucket}/{filename}"
    return f"https://{bucket}.s3.{region}.amazonaws.com/{filename}"
