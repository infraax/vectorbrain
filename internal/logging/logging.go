// Package logging configures structured logging for VectorBrain.
// In production, logs are JSON via zerolog — machine-parseable, zero-allocation.
// In dev mode (VB_LOG_DEV=true), logs are colored console output.
// We use slog as the interface so callers don't depend on zerolog directly.
package logging

import (
	"log/slog"
	"os"
	"time"

	"github.com/rs/zerolog"
	slogzerolog "github.com/samber/slog-zerolog/v2"
)

// Init configures the global slog logger. Call once at startup.
// dev=true enables human-readable colored output. dev=false uses JSON.
func Init(dev bool) {
	zerolog.TimeFieldFormat = time.RFC3339

	var zl zerolog.Logger
	if dev {
		// Console writer: color-coded, human-readable for development
		zl = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: "15:04:05"}).
			With().Timestamp().Logger()
	} else {
		// JSON output for production — parseable by log aggregators
		zl = zerolog.New(os.Stderr).With().Timestamp().Logger()
	}

	handler := slogzerolog.Option{Logger: &zl}.NewZerologHandler()
	slog.SetDefault(slog.New(handler))
}

// IsDev returns true if VB_LOG_DEV is set to "true" in the environment.
func IsDev() bool {
	return os.Getenv("VB_LOG_DEV") == "true"
}
