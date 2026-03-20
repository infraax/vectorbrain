"""
VectorBrain FastAPI application.

Three external interfaces:
  POST /event  — receives robot events from Go event bridge (non-blocking, drop if slow)
  POST /voice  — receives transcribed voice, returns spoken response text
  GET  /state  — returns world model snapshot (Go, MCP, and monitoring read this)
  GET  /health — liveness probe

Startup tasks (added at later milestones):
  - Mind loop background task (System 2, LLM-powered, adaptive 5-30s)
  - Fast loop background task (System 1, 10Hz, drive ticks + reflexes)
"""
from __future__ import annotations

import time
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from loguru import logger
from pydantic import BaseModel

from vectorbrain import __version__
from vectorbrain.cognition.world_model import WorldModel

# ── Global state ─────────────────────────────────────────────────────────────
# One world model per robot. Keyed by ESN.
# Populated lazily when events arrive — no robot config needed at startup.
_world_models: dict[str, WorldModel] = {}

_startup_time = time.time()


def _get_or_create_world_model(esn: str) -> WorldModel:
    """Return the world model for this ESN, creating it if it doesn't exist."""
    if esn not in _world_models:
        _world_models[esn] = WorldModel(esn=esn)
        logger.info("world model created", esn=esn)
    return _world_models[esn]


# ── Lifespan ──────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Startup: initialize background tasks.
    Shutdown: gracefully stop them.
    Mind loop and fast loop will be started here in Milestone 4.
    """
    logger.info("vectorbrain starting", version=__version__)
    yield
    logger.info("vectorbrain stopping")


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="VectorBrain",
    description="Cognitive layer for Anki Vector",
    version=__version__,
    lifespan=lifespan,
)


# ── Request/response models ────────────────────────────────────────────────────

class EventEnvelope(BaseModel):
    esn: str
    type: str
    timestamp: str
    payload: dict[str, Any] = {}


class VoiceRequest(BaseModel):
    esn: str
    text: str
    source: str = "wake_word"   # "wake_word" | "continuous_listen"


class VoiceResponse(BaseModel):
    text: str   # empty string = nothing to say


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    """Liveness probe. Always returns 200 if the app is running."""
    uptime_s = time.time() - _startup_time
    return {
        "status": "ok",
        "version": __version__,
        "uptime_s": round(uptime_s, 1),
        "timestamp": datetime.utcnow().isoformat(),
        "robots": list(_world_models.keys()),
    }


@app.post("/event", status_code=status.HTTP_204_NO_CONTENT)
async def receive_event(envelope: EventEnvelope):
    """
    Receive a robot event from Go's event bridge.

    Non-blocking contract: if we're slow, Go drops the event rather than waiting.
    This endpoint must return quickly. Heavy processing goes in background tasks.
    Events update the world model, which the mind loop reads asynchronously.
    """
    wm = _get_or_create_world_model(envelope.esn)

    # Route to the appropriate world model update.
    # Full event handling implemented in perception/event_handler.py (Milestone 3).
    event_type = envelope.type
    payload = envelope.payload

    async with wm._lock:
        wm.last_updated = datetime.utcnow()

        if event_type == "robot_state":
            _apply_robot_state(wm, payload)
        elif event_type == "face_observed":
            _apply_face_observed(wm, payload)
        elif event_type == "wake_word":
            logger.debug("wake word detected", esn=envelope.esn)
        elif event_type == "touch":
            wm.interaction.last_touch_type = payload.get("touch_type")
            wm.interaction.last_event_time = datetime.utcnow()
        elif event_type == "stimulation_info":
            wm.affect.stimulation = payload.get("stimulation", wm.affect.stimulation)
        # Unknown event types are silently accepted — we will encounter new ones in Stage 1


@app.post("/voice", response_model=VoiceResponse)
async def receive_voice(req: VoiceRequest):
    """
    Receive a transcribed voice utterance and return the response text.

    Go's router calls this after WirePod STT produces a transcript.
    Response text is played on the robot by Go's executor.

    Voice handler (voice.py) will call the 3B LLM — implemented in Milestone 2.
    For now, returns a placeholder so the pipeline can be tested end-to-end.
    """
    wm = _get_or_create_world_model(req.esn)

    async with wm._lock:
        wm.interaction.last_voice_input = req.text
        wm.interaction.conversation_turn += 1
        wm.interaction.last_event_time = datetime.utcnow()

    logger.info("voice input received", esn=req.esn, text=req.text[:80])

    # Placeholder — voice.py (Milestone 2) replaces this with real LLM call
    response_text = f"I heard you say: {req.text}. My mind is still waking up."

    async with wm._lock:
        wm.interaction.last_response = response_text

    return VoiceResponse(text=response_text)


@app.get("/state")
async def get_state(esn: str | None = None):
    """
    Return world model snapshot(s).

    If esn is provided, returns snapshot for that robot.
    If not, returns snapshots for all known robots.
    """
    if esn:
        if esn not in _world_models:
            raise HTTPException(status_code=404, detail=f"robot {esn} not seen yet")
        return _world_models[esn].snapshot()
    return {esn: wm.snapshot() for esn, wm in _world_models.items()}


# ── Private helpers ────────────────────────────────────────────────────────────

def _apply_robot_state(wm: WorldModel, payload: dict) -> None:
    """Apply a robot_state event to the world model. Called within the lock."""
    battery = payload.get("battery", {})
    if battery:
        wm.battery.voltage = battery.get("voltage", wm.battery.voltage)
        wm.battery.level = battery.get("level", wm.battery.level)
        wm.battery.is_charging = battery.get("is_charging", wm.battery.is_charging)
        wm.battery.is_on_charger = battery.get("is_on_charger", wm.battery.is_on_charger)

    pose = payload.get("pose", {})
    if pose:
        wm.pose.x = pose.get("x", wm.pose.x)
        wm.pose.y = pose.get("y", wm.pose.y)
        wm.pose.angle_rad = pose.get("angle_rad", wm.pose.angle_rad)

    wm.has_sdk_control = payload.get("has_sdk_control", wm.has_sdk_control)


def _apply_face_observed(wm: WorldModel, payload: dict) -> None:
    """Apply a face_observed event. Called within the lock."""
    from vectorbrain.cognition.world_model import FaceState

    face_id = payload.get("face_id", 0)
    name = payload.get("name", "")
    is_known = bool(name)

    # Update or add this face in the visible list
    existing = next((f for f in wm.faces_visible if f.face_id == face_id), None)
    if existing:
        existing.name = name
        existing.is_known = is_known
    else:
        wm.faces_visible.append(FaceState(
            face_id=face_id,
            name=name,
            is_known=is_known,
        ))

    if is_known:
        wm.interaction.last_face_seen = name
        wm.interaction.last_event_time = datetime.utcnow()
