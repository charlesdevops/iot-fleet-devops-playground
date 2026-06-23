from pydantic import BaseModel, Field


class DeviceIn(BaseModel):
    """Fields supplied by the client when registering a device."""

    device_id: str = Field(..., description="Unique device identifier", examples=["dev-001"])
    model: str = Field(..., description="Hardware model name", examples=["acme-edge-100"])


class Device(DeviceIn):
    """A registered device, including the location of its uploaded firmware blob."""

    firmware_url: str = Field(..., description="URL of the stored firmware/config blob")
