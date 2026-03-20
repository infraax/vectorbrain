// Package api defines the HTTP API types shared between Go handlers and Python callers.
// All types are JSON-serializable. Naming follows Anki's conventions from the TRM
// (e.g., "affect_state" not "emotions", "drive_state" not "motivations").
package api

import "time"

// HealthResponse is returned by GET /health.
type HealthResponse struct {
	Status    string            `json:"status"`     // "ok" or "degraded"
	Timestamp time.Time         `json:"timestamp"`
	Robots    map[string]string `json:"robots"`     // ESN → "connected" | "disconnected"
	Python    string            `json:"python"`     // "reachable" | "unreachable"
	Version   string            `json:"version"`
}

// RobotSummary is returned in GET /api/v1/robots.
type RobotSummary struct {
	ESN       string `json:"esn"`
	Name      string `json:"name"`
	Connected bool   `json:"connected"`
	IP        string `json:"ip"`
}

// RobotState is the full world model snapshot for one robot.
// Returned by GET /api/v1/robots/{esn}/state.
// Python reads this; the mind loop uses it to decide what to do.
type RobotState struct {
	ESN         string      `json:"esn"`
	Timestamp   time.Time   `json:"timestamp"`
	Battery     BatteryInfo `json:"battery"`
	Pose        PoseInfo    `json:"pose"`
	Stimulation float32     `json:"stimulation"`   // 0.0–1.0, from firmware StimulationInfo
	FacesVisible []FaceInfo `json:"faces_visible"`
	IsOnCharger bool        `json:"is_on_charger"`
	IsPickedUp  bool        `json:"is_picked_up"`
	HasControl  bool        `json:"has_control"`   // true when SDK behavior control is held
}

// BatteryInfo mirrors Vector's battery state.
type BatteryInfo struct {
	Voltage      float32 `json:"voltage"`
	Level        string  `json:"level"`        // "low" | "nominal" | "full"
	IsCharging   bool    `json:"is_charging"`
	IsOnCharger  bool    `json:"is_on_charger"`
}

// PoseInfo is Vector's position and orientation in its local map.
type PoseInfo struct {
	X      float32 `json:"x"`
	Y      float32 `json:"y"`
	Z      float32 `json:"z"`
	Angle  float32 `json:"angle_rad"`
}

// FaceInfo represents a face currently visible to Vector's camera.
type FaceInfo struct {
	FaceID    int32  `json:"face_id"`
	Name      string `json:"name"`       // empty if unknown
	IsKnown   bool   `json:"is_known"`
	Timestamp int64  `json:"timestamp_ms"`
}

// ActionRequest is the body for POST /api/v1/robots/{esn}/action.
// Python sends these; the Go executor translates them to SDK calls.
type ActionRequest struct {
	// Type identifies the action. Must match a known executor action.
	// Known types: say, animate, animate_trigger, move, turn,
	//              set_head_angle, set_eye_color, drive, dock, camera_enable
	Type   string         `json:"type"   validate:"required"`
	Params map[string]any `json:"params"`
}

// ActionResponse is returned after an action is executed.
type ActionResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

// EventEnvelope wraps a robot event sent from Go to Python POST /event.
// Python's event_handler.py receives these and updates the world model.
type EventEnvelope struct {
	ESN       string         `json:"esn"`
	Type      string         `json:"type"`
	Timestamp time.Time      `json:"timestamp"`
	Payload   map[string]any `json:"payload"`
}

// VoiceRequest is the body for POST /voice (Python endpoint).
// Go router sends this when WirePod's STT produces a transcript for a VB robot.
type VoiceRequest struct {
	ESN    string `json:"esn"`
	Text   string `json:"text"`
	Source string `json:"source"` // "wake_word" | "continuous_listen"
}

// VoiceResponse is what Python returns from POST /voice.
type VoiceResponse struct {
	Text string `json:"text"` // The spoken response. Empty = nothing to say.
}

// ErrorResponse is the standard error body for all 4xx/5xx responses.
type ErrorResponse struct {
	Error   string `json:"error"`
	Details string `json:"details,omitempty"`
}
