from fastapi import APIRouter, File, Form, UploadFile, status

from ..models.device import Device
from ..services import dynamodb as db_service
from ..services import s3 as s3_service

router = APIRouter(tags=["devices"])


@router.get("/devices", response_model=list[Device])
def list_devices() -> list[Device]:
    """Return every registered device."""
    return db_service.list_devices()


@router.post("/devices", response_model=Device, status_code=status.HTTP_201_CREATED)
async def register_device(
    device_id: str = Form(..., description="Unique device identifier"),
    model: str = Form(..., description="Hardware model name"),
    firmware: UploadFile = File(..., description="Firmware or config blob"),
) -> Device:
    """Register a device and store its firmware/config blob in object storage."""
    firmware_url = s3_service.upload_firmware(
        file_bytes=await firmware.read(),
        filename=f"{device_id}/{firmware.filename}",
        content_type=firmware.content_type or "application/octet-stream",
    )
    return db_service.create_device(device_id=device_id, model=model, firmware_url=firmware_url)
