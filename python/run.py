"""
VectorBrain entry point.

Run: python run.py [--port 8090] [--reload]
"""
import argparse
import sys

import uvicorn


def main():
    parser = argparse.ArgumentParser(description="VectorBrain Python application")
    parser.add_argument("--port", type=int, default=8090, help="Port to listen on")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload (dev only)")
    args = parser.parse_args()

    uvicorn.run(
        "vectorbrain.app:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info",
    )


if __name__ == "__main__":
    main()
