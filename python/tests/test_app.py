"""
Tests for the VectorBrain FastAPI application.
Milestone 0 — scaffolding verification.
"""
import pytest
from fastapi.testclient import TestClient

from vectorbrain.app import app

client = TestClient(app)


class TestHealth:
    def test_health_returns_200(self):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_returns_ok_status(self):
        data = client.get("/health").json()
        assert data["status"] == "ok"

    def test_health_contains_version(self):
        data = client.get("/health").json()
        assert "version" in data
        assert data["version"].startswith("0.1.0")

    def test_health_contains_uptime(self):
        data = client.get("/health").json()
        assert "uptime_s" in data
        assert data["uptime_s"] >= 0

    def test_health_robots_initially_empty(self):
        # Fresh TestClient — no events received yet
        fresh_client = TestClient(app)
        data = fresh_client.get("/health").json()
        assert isinstance(data["robots"], list)


class TestState:
    def test_state_no_esn_returns_empty_dict(self):
        fresh_client = TestClient(app)
        response = fresh_client.get("/state")
        assert response.status_code == 200
        assert response.json() == {}

    def test_state_unknown_esn_returns_404(self):
        response = client.get("/state?esn=deadbeef")
        assert response.status_code == 404


class TestEventReceiver:
    def test_event_returns_204(self):
        response = client.post("/event", json={
            "esn": "test123",
            "type": "robot_state",
            "timestamp": "2026-03-20T00:00:00",
            "payload": {},
        })
        assert response.status_code == 204

    def test_event_creates_world_model(self):
        fresh_client = TestClient(app)
        fresh_client.post("/event", json={
            "esn": "abc001",
            "type": "robot_state",
            "timestamp": "2026-03-20T00:00:00",
            "payload": {},
        })
        state = fresh_client.get("/state?esn=abc001").json()
        assert state["esn"] == "abc001"

    def test_event_unknown_type_accepted(self):
        """Unknown event types must not crash the endpoint."""
        response = client.post("/event", json={
            "esn": "test123",
            "type": "some_future_event_type_we_dont_know_yet",
            "timestamp": "2026-03-20T00:00:00",
            "payload": {"foo": "bar"},
        })
        assert response.status_code == 204

    def test_battery_update_persists(self):
        fresh_client = TestClient(app)
        fresh_client.post("/event", json={
            "esn": "bat001",
            "type": "robot_state",
            "timestamp": "2026-03-20T00:00:00",
            "payload": {
                "battery": {
                    "voltage": 3.85,
                    "level": "nominal",
                    "is_charging": False,
                    "is_on_charger": False,
                }
            },
        })
        state = fresh_client.get("/state?esn=bat001").json()
        assert state["battery"]["voltage"] == pytest.approx(3.85)
        assert state["battery"]["level"] == "nominal"


class TestVoiceEndpoint:
    def test_voice_returns_200(self):
        response = client.post("/voice", json={
            "esn": "test123",
            "text": "Hello Vector",
            "source": "wake_word",
        })
        assert response.status_code == 200

    def test_voice_returns_text_field(self):
        response = client.post("/voice", json={
            "esn": "test123",
            "text": "Hello Vector",
        })
        data = response.json()
        assert "text" in data
        assert isinstance(data["text"], str)
        assert len(data["text"]) > 0

    def test_voice_increments_conversation_turn(self):
        fresh_client = TestClient(app)
        esn = "conv001"
        for i in range(3):
            fresh_client.post("/voice", json={"esn": esn, "text": f"message {i}"})
        state = fresh_client.get(f"/state?esn={esn}").json()
        assert state["interaction"]["conversation_turn"] == 3
