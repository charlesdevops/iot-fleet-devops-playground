import io


def test_health(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_metrics_exposed(client):
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert "http_request" in resp.text


def test_list_devices_empty(client):
    resp = client.get("/devices")
    assert resp.status_code == 200
    assert resp.json() == []


def test_register_device(client):
    data = {"device_id": "dev-001", "model": "acme-edge-100"}
    files = {"firmware": ("fw.bin", io.BytesIO(b"fake-firmware-bytes"), "application/octet-stream")}
    resp = client.post("/devices", data=data, files=files)
    assert resp.status_code == 201
    body = resp.json()
    assert body["device_id"] == "dev-001"
    assert body["model"] == "acme-edge-100"
    assert "firmware_url" in body


def test_list_returns_registered_device(client):
    data = {"device_id": "dev-001", "model": "acme-edge-100"}
    files = {"firmware": ("fw.bin", io.BytesIO(b"fake-firmware-bytes"), "application/octet-stream")}
    client.post("/devices", data=data, files=files)

    resp = client.get("/devices")
    assert resp.status_code == 200
    devices = resp.json()
    assert len(devices) == 1
    assert devices[0]["device_id"] == "dev-001"


def test_register_device_missing_model(client):
    data = {"device_id": "dev-001"}
    files = {"firmware": ("fw.bin", io.BytesIO(b"bytes"), "application/octet-stream")}
    resp = client.post("/devices", data=data, files=files)
    assert resp.status_code == 422


def test_register_device_missing_device_id(client):
    data = {"model": "acme-edge-100"}
    files = {"firmware": ("fw.bin", io.BytesIO(b"bytes"), "application/octet-stream")}
    resp = client.post("/devices", data=data, files=files)
    assert resp.status_code == 422


def test_register_device_missing_firmware(client):
    data = {"device_id": "dev-001", "model": "acme-edge-100"}
    resp = client.post("/devices", data=data)
    assert resp.status_code == 422
