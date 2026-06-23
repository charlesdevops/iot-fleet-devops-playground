from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration, sourced from environment variables (or a .env file)."""

    aws_region: str = "us-east-1"
    dynamodb_table: str = "devices"
    s3_bucket: str = "fleet-firmware"
    aws_endpoint_url: str | None = None

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
