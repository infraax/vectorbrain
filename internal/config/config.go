// Package config loads and validates VectorBrain configuration.
// Uses koanf v2 for layered config: JSON file → environment overrides.
// All config keys are validated at startup — no silent misconfiguration.
package config

import (
	"fmt"
	"log/slog"

	"github.com/go-playground/validator/v10"
	"github.com/knadh/koanf/parsers/json"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

// Config is the root configuration for VectorBrain.
type Config struct {
	Server  ServerConfig  `koanf:"server"  validate:"required"`
	Python  PythonConfig  `koanf:"python"  validate:"required"`
	Robots  []RobotConfig `koanf:"robots"`
	Logging LoggingConfig `koanf:"logging"`
}

// ServerConfig controls the VectorBrain HTTP API server.
type ServerConfig struct {
	// Port is the port the API server listens on. Default: 8070.
	Port int `koanf:"port" validate:"required,min=1024,max=65535"`
	// MCPPort is the dedicated port for the MCP server. Default: 8071.
	MCPPort int `koanf:"mcp_port" validate:"required,min=1024,max=65535"`
}

// PythonConfig describes how to reach the Python VectorBrain app.
type PythonConfig struct {
	// BaseURL is the base URL of the Python FastAPI app. Default: http://localhost:8090
	BaseURL string `koanf:"base_url" validate:"required,url"`
	// EventTimeout is the max milliseconds to wait for Python to accept an event.
	// Events are non-blocking: if Python is slow, we drop rather than stall the event stream.
	EventTimeoutMS int `koanf:"event_timeout_ms" validate:"min=50,max=5000"`
}

// RobotConfig describes a single connected Vector robot.
type RobotConfig struct {
	ESN  string `koanf:"esn"  validate:"required"`
	IP   string `koanf:"ip"   validate:"required"`
	Name string `koanf:"name"`
}

// LoggingConfig controls logging behavior.
type LoggingConfig struct {
	// Dev enables colored console output when true. JSON when false.
	Dev bool `koanf:"dev"`
}

var validate = validator.New()

// Load reads config from the given JSON file path and validates it.
// Returns an error if the file is missing, malformed, or fails validation.
func Load(path string) (*Config, error) {
	k := koanf.New(".")

	if err := k.Load(file.Provider(path), json.Parser()); err != nil {
		return nil, fmt.Errorf("loading config from %s: %w", path, err)
	}

	var cfg Config
	if err := k.Unmarshal("", &cfg); err != nil {
		return nil, fmt.Errorf("unmarshalling config: %w", err)
	}

	if err := validate.Struct(&cfg); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	slog.Info("config loaded",
		"path", path,
		"api_port", cfg.Server.Port,
		"mcp_port", cfg.Server.MCPPort,
		"python_url", cfg.Python.BaseURL,
		"robots", len(cfg.Robots),
	)
	return &cfg, nil
}
