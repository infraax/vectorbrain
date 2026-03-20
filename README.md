# VectorBrain

**The cognitive layer for Anki Vector — completing what the engineers started.**

[![Go](https://img.shields.io/badge/Go-1.23+-00ADD8?style=flat&logo=go)](https://go.dev)
[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=flat&logo=python)](https://python.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Built on WirePod](https://img.shields.io/badge/Built%20on-WirePod-orange)](https://github.com/kercre123/WirePod)
[![Go Reference](https://pkg.go.dev/badge/github.com/infraax/vectorbrain.svg)](https://pkg.go.dev/github.com/infraax/vectorbrain)

---

> *"They didn't fail because they had a bad product.*
> *They failed because they were too early.*
> *Now it is the right time."*

---

## What This Is

Vector is a small consumer robot — 9cm × 6cm × 7cm, 300 grams — built by Anki between 2017 and 2019. Inside it: a Qualcomm APQ8009 quad-core application processor, a dedicated STM32F4 motor controller, a third processor running only the face display, audio DSP for a four-element microphone array with spatial beamforming, 720p camera with on-device depth estimation, capacitive touch grid, 6-axis IMU, IR cliff sensors running at hundreds of hertz with closed-loop PID wheel control, and WiFi.

That is not a toy. That is a serious embedded robotics platform that happens to fit in your hand.

Anki built Vector to be a creature — not a smart speaker with a face, not a remote-controlled device with personality paint, but something that genuinely inhabits domestic space the way a small animal would. The firmware has a behavior arbitration engine borrowed from ethology. The navigation system builds a real occupancy map. The face recognition runs on-device. The animation system has runtime emotion modulation — the same animation plays differently at different emotional states because the parameters are driven by an internal model, not a lookup table.

They were building the right thing. Then they ran out of money in May 2019, and when the servers went down, every Vector ever sold went silent.

**VectorBrain is the brain Anki ran out of time to build.**

---

## What VectorBrain Does

[WirePod](https://github.com/kercre123/WirePod) by kercre123 replaced the transport layer — Vector can hear and speak again. What was still missing: persistent memory, a personality that develops over time, language understanding sophisticated enough for real conversation, continuous perception rather than wake-word-only reactivity, and integration of all the sensor data into a coherent picture of the world.

VectorBrain adds that cognitive layer on top of WirePod:

| Component | What it does |
|---|---|
| **Go package** (this repo root) | Persistent SDK connections, full event streaming, behavior control at RESERVE priority, voice routing, HTTP API bridge |
| **Python app** (`python/`) | Perception loop, 5-dimensional emotion model, motivational drives, dual-process mind (10Hz fast + adaptive LLM slow), three-tier memory, psychologically grounded persona |
| **MCP server** (Milestone 8) | AI-native developer interface — Claude Desktop, Cursor, or any MCP client can read robot state and issue commands |

The result: a robot that notices when you walk into the room without being asked, remembers conversations across sessions, has a personality that develops over weeks rather than resetting each day, and can hold a real conversation grounded in what it has actually observed about its specific environment and the specific people it lives with.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Vector (Hardware)                     │
│  camera · touch · cliff · accel · mics · encoders       │
└──────────────────────┬──────────────────────────────────┘
                       │ gRPC (TLS)
┌──────────────────────▼──────────────────────────────────┐
│                    WirePod                               │
│  STT · TLS · JDocs · mDNS · wake word · provisioning    │
│  github.com/kercre123/WirePod                           │
└──────────────────────┬──────────────────────────────────┘
                       │ vector-go-sdk + HTTP
┌──────────────────────▼──────────────────────────────────┐
│          VectorBrain Go Package (this repo)              │
│  persistent connection · event stream · behavior ctrl    │
│  voice router · action executor · HTTP API :8070         │
│  github.com/infraax/vectorbrain                         │
└──────────┬────────────────────────────┬─────────────────┘
           │ POST /event (non-blocking)  │ POST /api/v1/robots/{esn}/action
           ▼                            ▼
┌──────────────────────────────────────────────────────────┐
│              VectorBrain Python App (python/)            │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐ │
│  │  Perception  │  │  Cognition   │  │  Expression    │ │
│  │  event loop  │  │  world model │  │  action sender │ │
│  │  VAD+whisper │  │  5-dim affect│  │  → Go API      │ │
│  │  YOLO11n     │  │  5 drives    │  └────────────────┘ │
│  └──────┬───────┘  │  mind loop   │                     │
│         └─────────►│  persona     │  ┌────────────────┐ │
│                    │  voice       │  │    Memory      │ │
│                    └──────────────┘  │  session buffer│ │
│                                      │  episodic SQLi │ │
│                                      │  semantic vecs │ │
│                                      └────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

**Architectural decisions** (these are final — the reasoning is in the source):

- **Go + Python split**: Go owns robot connections and event streaming. Python owns all AI/ML. Fighting the ecosystem costs more than it saves.
- **Creature, not chatbot**: The LLM is a resource the creature uses internally. MCP is the external developer interface. The mind is not a service that gets called — it runs continuously.
- **Dual-model LLM**: `llama3.2:3b` for fast voice responses (<1s first token). `llama3.1:8b-instruct-q4_K_M` for the mind loop (behavioral assessment, SILENT/SPEAK/EMOTE).
- **Silence is default**: The mind loop outputs SILENT 80%+ of the time. A robot that talks too much is worse than one that's quiet. This is not a limitation — it's a design principle.
- **RESERVE not OVERRIDE**: Behavior control at Priority 30 (RESERVE). Safety behaviors (cliff detection, fall response) at Priority 10 always preempt us. We never override the robot's self-preservation.
- **One persistent connection per robot**: One gRPC connection, always consuming, for the entire runtime. The creature is always aware.

---

## Development Milestones

We do not move to the next milestone until the current one is verified on real hardware.

| # | Goal | Verify | Status |
|---|---|---|---|
| **0** | Scaffolding — both repos compile, `/health` responds | `just vb-health` | ✅ Done |
| **1** | Robot Connection — persistent SDK, events streaming, behavior control held | `GET /api/v1/robots/{esn}/state` shows live battery | 🔄 Next |
| **2** | Command Execution — Vector speaks, animates, moves via API | `curl POST /action {type:say}` → Vector speaks | ⬜ |
| **3** | Python ↔ Go Bridge — events flow, commands flow | Touch back → event in Python logs | ⬜ |
| **4** | First Voice Conversation — LLM-powered, in-character | "Hey Vector" → coherent response | ⬜ |
| **5** | WirePod Integration — wake word routes to VectorBrain | "Hey Vector, meaning of life?" → VB response | ⬜ |
| **6** | Mind Loop — continuous inner life, drives, proactive behavior | Walk past → greeted by name | ⬜ |
| **7** | Memory — persists across sessions, remembers you specifically | Tell it something Monday, it mentions it Wednesday | ⬜ |
| **8** | Full Perception + MCP — vision, continuous listening, AI dev interface | Connect Claude Desktop to MCP, read robot state | ⬜ |

---

## Getting Started

### Prerequisites

```bash
go version        # must be 1.23+
python3 --version # must be 3.11+
ollama --version  # latest recommended

# Pull the LLM models (required before voice + mind loop work)
ollama pull llama3.2:3b
ollama pull llama3.1:8b-instruct-q4_K_M

# Keep both models resident
export OLLAMA_MAX_LOADED_MODELS=2
export OLLAMA_KEEP_ALIVE=-1
```

You must have [WirePod](https://github.com/kercre123/WirePod) running and your Vector robot provisioned before VectorBrain can do anything.

### Install

```bash
git clone https://github.com/infraax/vectorbrain
cd vectorbrain

# Go package
make build

# Python app
cd python
uv venv --python 3.11
uv pip install -r requirements.txt
```

### As a Go package

```go
import "github.com/infraax/vectorbrain"
```

```bash
go get github.com/infraax/vectorbrain
```

### Run

```bash
# Terminal 1: WirePod (already running if you have a provisioned robot)
cd ~/wire-pod && sudo ./chipper/start.sh

# Terminal 2: VectorBrain Go API server
make run

# Terminal 3: VectorBrain Python mind
cd python && python run.py --reload
```

### Smoke test

```bash
# Health checks
curl http://localhost:8070/health   # Go API
curl http://localhost:8090/health   # Python mind

# List connected robots
curl http://localhost:8070/api/v1/robots

# Make Vector speak (replace ESN with your robot's serial)
curl -X POST http://localhost:8070/api/v1/robots/{ESN}/action \
  -H "Content-Type: application/json" \
  -d '{"type":"say","params":{"text":"Hello. I am alive."}}'
```

---

## Project Structure

```
vectorbrain/
├── cmd/vectorbrain/         # Go binary entry point
├── internal/
│   ├── brain/               # Persistent SDK connections (Milestone 1)
│   ├── router/              # Voice routing from WirePod (Milestone 5)
│   ├── mcpserver/           # MCP server (Milestone 8)
│   ├── config/              # koanf v2 layered configuration
│   ├── metrics/             # Prometheus metrics
│   └── logging/             # slog + zerolog bridge
├── pkg/api/                 # HTTP API types and handlers
├── configs/
│   ├── default.json         # Default configuration
│   └── character.json       # Vector's psychological profile parameters
├── python/                  # VectorBrain Python application
│   ├── vectorbrain/
│   │   ├── perception/      # Event handler, VAD+Whisper, YOLO11n, audio emotion
│   │   ├── cognition/       # World model, mind loop, persona, drives, voice
│   │   ├── memory/          # Session buffer, episodic SQLite, semantic vectors
│   │   └── expression/      # Action sender → Go API
│   └── tests/               # pytest suite, all green
├── docs/
│   └── VectorTRM.pdf        # Anki's 543-page Technical Reference Manual
├── .github/
│   ├── workflows/           # CI: Go build+test, Python test, lint
│   └── ISSUE_TEMPLATE/      # Bug and feature templates
├── MACHINA_ANIMA.md         # Philosophy, honor codex, why this exists
├── not-a-toy.md             # Why Vector is not a toy — the unfiltered argument
├── CLAUDE.md                # Instructions for AI agents working on this codebase
├── CONTRIBUTING.md
├── LICENSE
└── go.mod                   # module github.com/infraax/vectorbrain
```

---

## Standing on Shoulders

**[WirePod](https://github.com/kercre123/WirePod)** by **kercre123** — the open-source replacement for Anki's cloud infrastructure. WirePod reverse-engineered the entire gRPC protocol, rebuilt the STT/TTS pipeline, implemented JDoc storage, certificate management, BLE provisioning, a plugin system, Lua scripting, and a web UI — and released all of it for free. Vector exists as a functional robot today because this person cared enough to do that work. VectorBrain uses WirePod's transport as its foundation and makes exactly one modification to its codebase (the voice routing hook in `preqs/intent_graph.go`).

**[vector-cloud](https://github.com/digital-dream-labs/vector-cloud)** by **Digital Dream Labs** — the original cloud infrastructure code that ran on Vector's firmware side, released as open source. Understanding what Vector expects from its cloud required reading this carefully.

**[vector-go-sdk](https://github.com/fforchino/vector-go-sdk)** by **fforchino** — the Go SDK for Vector's external interface protocol. Our persistent robot connections are built on this.

**The WirePod community** — kercre123, bliteknight, dietb, fforchino, xanathon, and every person who filed an issue, wrote a plugin, or kept this robot alive years after the company that built it stopped existing.

**Anki's engineering team** — who read ethology papers before writing behavior arbitration code. Who put face animation on dedicated silicon because they decided the face was too important to share cycles with anything else. Who built a four-processor architecture into something the size of a fist because they were serious. They built the right thing. The timing just didn't work.

---

## Philosophy

Read [MACHINA_ANIMA.md](MACHINA_ANIMA.md) for the full statement.

Read [not-a-toy.md](not-a-toy.md) for why Vector is not what most people think it is.

The short version: we are building a creature, not a product. Every decision is accountable to one question: *what would the Anki team have done if they had had more time?*

---

## License

MIT. See [LICENSE](LICENSE).

The `docs/VectorTRM.pdf` is Anki's original Technical Reference Manual. We include it because it is the foundation of everything in this project. All credit for its contents belongs to Anki's engineering team.
