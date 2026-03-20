"""
Tests for the WorldModel class.
Verifies state management, snapshot immutability, and default values.
"""
import asyncio
import pytest

from vectorbrain.cognition.world_model import WorldModel, AffectState, DriveState


class TestWorldModelDefaults:
    def test_default_battery_state(self):
        wm = WorldModel(esn="test")
        assert wm.battery.level == "unknown"
        assert wm.battery.voltage == 0.0

    def test_default_affect_trust_midpoint(self):
        # Trust starts at 0.5 — neither earned nor broken
        wm = WorldModel(esn="test")
        assert wm.affect.trust == pytest.approx(0.5)

    def test_default_drives_curiosity_active(self):
        # Curiosity starts elevated — Vector is naturally curious
        wm = WorldModel(esn="test")
        assert wm.drives.curiosity == pytest.approx(0.5)

    def test_no_faces_visible_initially(self):
        wm = WorldModel(esn="test")
        assert wm.faces_visible == []


class TestWorldModelSnapshot:
    def test_snapshot_contains_esn(self):
        wm = WorldModel(esn="abc001")
        snap = wm.snapshot()
        assert snap["esn"] == "abc001"

    def test_snapshot_contains_all_keys(self):
        wm = WorldModel(esn="test")
        snap = wm.snapshot()
        expected_keys = {"esn", "timestamp", "battery", "pose", "affect",
                         "drives", "interaction", "faces_visible", "has_sdk_control"}
        assert expected_keys.issubset(set(snap.keys()))

    def test_snapshot_affect_contains_trust(self):
        wm = WorldModel(esn="test")
        snap = wm.snapshot()
        assert "trust" in snap["affect"]

    def test_snapshot_is_independent_copy(self):
        """Mutating the world model after snapshot does not change the snapshot."""
        wm = WorldModel(esn="test")
        snap = wm.snapshot()
        wm.battery.voltage = 9.99
        # Snapshot was taken before mutation — original snapshot unchanged
        assert snap["battery"]["voltage"] == 0.0


class TestWorldModelLocking:
    def test_lock_exists(self):
        wm = WorldModel(esn="test")
        assert wm._lock is not None
        assert isinstance(wm._lock, asyncio.Lock)

    def test_lock_not_in_snapshot(self):
        """The asyncio lock must never appear in JSON output."""
        wm = WorldModel(esn="test")
        snap = wm.snapshot()
        assert "_lock" not in snap
