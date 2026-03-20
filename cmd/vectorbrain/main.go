// VectorBrain — the cognitive layer for Anki Vector.
// This binary connects to Vector robots via the SDK, streams all events,
// holds persistent behavior control, and bridges the physical robot
// to the Python mind running at --python-url.
//
// "The creature is waiting. Let's build it right." — MACHINA_ANIMA
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/infraax/vectorbrain/internal/config"
	"github.com/infraax/vectorbrain/internal/logging"
	"github.com/infraax/vectorbrain/pkg/api"
)

const version = "0.1.0-milestone0"

func main() {
	configPath := flag.String("config", "configs/default.json", "path to config JSON file")
	flag.Parse()

	// Logging must be first — everything after uses slog.
	logging.Init(logging.IsDev())

	slog.Info("vectorbrain starting", "version", version)

	cfg, err := config.Load(*configPath)
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	mux := buildRouter(cfg)

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown on SIGINT/SIGTERM
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		slog.Info("api server listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	slog.Info("shutdown signal received")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
	}
	slog.Info("vectorbrain stopped")
}

func buildRouter(cfg *config.Config) *http.ServeMux {
	mux := http.NewServeMux()

	// GET /health — liveness check. Returns robot connection status.
	// Python calls this; monitoring tools call this; developers call this.
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		resp := api.HealthResponse{
			Status:    "ok",
			Timestamp: time.Now(),
			Robots:    make(map[string]string),
			Python:    "not_checked", // will be filled by brain registry in Milestone 1
			Version:   version,
		}
		for _, robot := range cfg.Robots {
			resp.Robots[robot.ESN] = "configured" // "connected" once brain is initialized
		}
		writeJSON(w, http.StatusOK, resp)
	})

	// GET /api/v1/robots — list configured robots and their connection state.
	mux.HandleFunc("GET /api/v1/robots", func(w http.ResponseWriter, r *http.Request) {
		robots := make([]api.RobotSummary, 0, len(cfg.Robots))
		for _, rc := range cfg.Robots {
			robots = append(robots, api.RobotSummary{
				ESN:       rc.ESN,
				Name:      rc.Name,
				Connected: false, // will be true once brain connects in Milestone 1
				IP:        rc.IP,
			})
		}
		writeJSON(w, http.StatusOK, robots)
	})

	return mux
}

// writeJSON serialises v to JSON and writes it with the given status code.
// Logs a warning if serialisation fails (should never happen with our types).
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Warn("failed to write JSON response", "error", err)
	}
}
