import os

import boto3
import pytest
from moto import mock_aws

TABLE_NAME = "test-devices"
BUCKET_NAME = "test-firmware"


@pytest.fixture
def client():
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"

    # A developer's local app/.env (or load_dotenv() in main.py) may point
    # AWS_ENDPOINT_URL at LocalStack. An explicit env var takes precedence over the
    # .env file, so force it empty to keep boto3 calls inside moto during tests.
    prev_endpoint = os.environ.get("AWS_ENDPOINT_URL")
    os.environ["AWS_ENDPOINT_URL"] = ""
    os.environ["DYNAMODB_TABLE"] = TABLE_NAME
    os.environ["S3_BUCKET"] = BUCKET_NAME
    os.environ["AWS_REGION"] = "us-east-1"

    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[{"AttributeName": "device_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "device_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=BUCKET_NAME)

        # Import after env + mocks are in place so the cached Settings pick up the
        # test table/bucket and boto3 calls are intercepted by moto.
        from fastapi.testclient import TestClient

        from fleet_api.config import get_settings
        from fleet_api.main import app

        get_settings.cache_clear()

        yield TestClient(app)

        get_settings.cache_clear()

    if prev_endpoint is not None:
        os.environ["AWS_ENDPOINT_URL"] = prev_endpoint
    else:
        os.environ.pop("AWS_ENDPOINT_URL", None)
