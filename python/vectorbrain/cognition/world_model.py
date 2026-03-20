"""
World model — the central shared state for one Vector robot.

Perception writes here continuously. Cognition reads here to decide.
Expression reads here to communicate.

Thread-safety: asyncio.Lock protects all writes. Reads use a snapshot
method that returns an immutable copy, so callers don't hold the lock.

Design principle from Anki's TRM: Vector maintains a volatile occupancy
map of its immediate environment. We extend that concept upward into the
cognitive layer — the world model is that map, including the social and
emotional dimensions the firmware never got to fully implement.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class BatteryState:
    voltage: float = 0.0
    level: str = "unknown"   # "low" | "nominal" | "full"
    is_charging: bool = False
    is_on_charger: bool = True


@dataclass
class PoseState:
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    angle_rad: float = 0.0


@dataclass
class FaceState:
    face_id: int = 0
    name: str = ""
    is_known: bool = False
    last_seen_ms: int = 0


@dataclass
class AffectState:
    """
    5 dimensions bridged from Vector's firmware StimulationInfo events.
    Numeric range: -1.0 to +1.0 unless otherwise noted.

    These mirror Anki's emotional model from the TRM, plus extensions
    the firmware supported but never fully surfaced to the SDK.
    """
    valence: float = 0.0       # negative ↔ positive affect (-1 to +1)
    arousal: float = 0.0       # calm ↔ excited (-1 to +1)
    dominance: float = 0.0     # submissive ↔ dominant (-1 to +1)
    trust: float = 0.5         # 0–1, the only dimension that persists across restarts
    stimulation: float = 0.0   # raw stimulation level from firmware (0–1)


@dataclass
class DriveState:
    """
    5 motivational drives. Each increases over time, satisfied by actions.
    Range 0.0–1.0. Drives above their threshold exert pressure on the mind loop.
    """
    curiosity: float = 0.5     # increases with inactivity, satisfied by exploration
    social: float = 0.3        # increases with isolation, satisfied by interaction
    comfort: float = 0.8       # decreases when cold/low battery, satisfied by charger
    play: float = 0.3          # increases when idle, satisfied by games/animation
    self_expression: float = 0.2  # increases after prolonged silence, satisfied by speaking


@dataclass
class InteractionState:
    """Tracks the current conversational and physical interaction context."""
    last_voice_input: Optional[str] = None
    last_response: Optional[str] = None
    conversation_turn: int = 0
    last_face_seen: Optional[str] = None          # name of last recognized person
    last_touch_type: Optional[str] = None         # "pet" | "poke" | "sustained"
    is_being_held: bool = False
    last_event_time: Optional[datetime] = None


@dataclass
class WorldModel:
    """
    Complete world model snapshot for one Vector robot.

    Instantiate one per robot. Call update_*() from the perception event handler.
    Call snapshot() to get an immutable copy for cognition to reason over.
    """
    esn: str = ""
    last_updated: datetime = field(default_factory=datetime.utcnow)

    battery: BatteryState = field(default_factory=BatteryState)
    pose: PoseState = field(default_factory=PoseState)
    affect: AffectState = field(default_factory=AffectState)
    drives: DriveState = field(default_factory=DriveState)
    interaction: InteractionState = field(default_factory=InteractionState)

    faces_visible: list[FaceState] = field(default_factory=list)
    has_sdk_control: bool = False    # true when Go holds behavior control

    # Runtime lock — not included in snapshots
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock, init=False, repr=False)

    def snapshot(self) -> dict:
        """
        Return an immutable dict copy of the world state for the mind loop to reason over.
        Does NOT acquire the lock — callers should snapshot after acquiring if atomicity matters.
        This is acceptable: the mind loop tolerates slightly stale data.
        """
        return {
            "esn": self.esn,
            "timestamp": self.last_updated.isoformat(),
            "battery": {
                "voltage": self.battery.voltage,
                "level": self.battery.level,
                "is_charging": self.battery.is_charging,
                "is_on_charger": self.battery.is_on_charger,
            },
            "pose": {
                "x": self.pose.x,
                "y": self.pose.y,
                "angle_rad": self.pose.angle_rad,
            },
            "affect": {
                "valence": self.affect.valence,
                "arousal": self.affect.arousal,
                "dominance": self.affect.dominance,
                "trust": self.affect.trust,
                "stimulation": self.affect.stimulation,
            },
            "drives": {
                "curiosity": self.drives.curiosity,
                "social": self.drives.social,
                "comfort": self.drives.comfort,
                "play": self.drives.play,
                "self_expression": self.drives.self_expression,
            },
            "interaction": {
                "last_voice_input": self.interaction.last_voice_input,
                "last_response": self.interaction.last_response,
                "conversation_turn": self.interaction.conversation_turn,
                "last_face_seen": self.interaction.last_face_seen,
                "last_touch_type": self.interaction.last_touch_type,
                "is_being_held": self.interaction.is_being_held,
                "last_event_time": (
                    self.interaction.last_event_time.isoformat()
                    if self.interaction.last_event_time else None
                ),
            },
            "faces_visible": [
                {"face_id": f.face_id, "name": f.name, "is_known": f.is_known}
                for f in self.faces_visible
            ],
            "has_sdk_control": self.has_sdk_control,
        }
