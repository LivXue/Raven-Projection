"""Install the Raven screen app and update its state using the local device API."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import ProxyHandler, Request, build_opener


APP_ID = "raven_display"
REMOTE_DIRECTORY = f"/sd/apps/{APP_ID}"
STATES = ("idle", "thinking", "working", "waiting", "error", "offline")
PACKAGE = Path(__file__).resolve().parent / "package"


class Device:
    """Communicate directly with a Cubic device without a system HTTP proxy."""

    def __init__(self, host: str) -> None:
        self.base = "http://" + host
        self.opener = build_opener(ProxyHandler({}))

    def request(self, path: str, method: str = "GET", data: bytes | None = None,
                content_type: str = "application/octet-stream") -> bytes:
        request = Request(self.base + path, data=data, method=method,
                          headers={"Content-Type": content_type, "Connection": "close"})
        try:
            with self.opener.open(request, timeout=20) as response:
                return response.read()
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")[:500]
            raise RuntimeError(f"{method} {path}: HTTP {error.code}: {detail}") from error

    def api(self, path: str, method: str = "GET", value: dict | None = None) -> dict:
        body = json.dumps(value).encode("utf-8") if value is not None else None
        raw = self.request(path, method, body, "application/json")
        try:
            result = json.loads(raw)
        except ValueError as error:
            raise RuntimeError(f"{path} is not ready: expected a JSON response") from error
        if not isinstance(result, dict):
            raise RuntimeError(f"{path} returned an unexpected response")
        if result.get("ok") is False:
            raise RuntimeError(result.get("error", "Device request failed"))
        return result

    def file(self, path: str) -> bytes:
        return self.request("/api/system/fs/file?" + urlencode({"path": path}))

    def route(self) -> str:
        system = self.api("/api/system/state")
        if (system.get("current_app") or {}).get("id") != APP_ID:
            raise RuntimeError("Raven is not running. Run the start command first.")
        return system.get("current_route_base") or f"/{APP_ID}"

    def start(self) -> dict:
        launch_path = "/api/system/launch?" + urlencode({"id": APP_ID})
        try:
            self.api(launch_path, "POST")
        except RuntimeError as error:
            if "app not found" not in str(error):
                raise
            self.rescan()
            self.api(launch_path, "POST")
        deadline = time.monotonic() + 15
        last_error = None
        while time.monotonic() < deadline:
            try:
                result = self.api(self.route() + "/api/state")
                if result.get("app") == APP_ID:
                    return result
            except (RuntimeError, URLError, TimeoutError) as error:
                last_error = error
            time.sleep(0.5)
        diagnostic = self.file(f"{REMOTE_DIRECTORY}/last_error.txt").decode("utf-8", errors="replace")
        if diagnostic.strip():
            raise RuntimeError(f"Raven startup failed: {diagnostic.strip()}")
        raise RuntimeError(f"Raven did not become ready: {last_error}")

    def rescan(self) -> None:
        helper = self.file("/sd/apps/devrun/main.lua").strip()
        if helper != b"app.rescan()":
            raise RuntimeError("Rescan apps in the device launcher, then run the start command")
        print("Refreshing app discovery with the device's existing rescan helper")
        self.api("/api/system/launch?id=devrun", "POST")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            system = self.api("/api/system/state")
            if any(item["id"] == APP_ID for item in system.get("apps", [])):
                return
            time.sleep(0.5)
        raise RuntimeError("The device did not discover the new Raven app")


def install(device: Device) -> dict:
    """Upload only this app's files, verify every byte, and launch it."""
    names = ("raven.png", "main.png", "main.lua", "app.info")
    for name in names:
        if not (PACKAGE / name).is_file():
            raise RuntimeError(f"Missing {name}; run build-assets.ps1 first")

    current = device.api("/api/system/state")
    listing_path = "/api/system/fs/list?" + urlencode({"path": "/sd/apps"})
    existing = any(entry["name"] == APP_ID for entry in device.api(listing_path)["entries"])
    if existing:
        info = device.file(f"{REMOTE_DIRECTORY}/app.info").decode("utf-8")
        if "description = Raven portrait and live status display" not in info:
            raise RuntimeError("The device app directory belongs to a different app")
        backup = Path(__file__).resolve().parent / "backups" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup.mkdir(parents=True)
        for name in names:
            (backup / name).write_bytes(device.file(f"{REMOTE_DIRECTORY}/{name}"))
        print(f"Saved previous package to {backup}")
    else:
        device.api("/api/system/fs/mkdir?" + urlencode({"path": REMOTE_DIRECTORY}), "POST")

    if (current.get("current_app") or {}).get("id") == APP_ID:
        device.api("/api/system/exit", "POST")
        time.sleep(0.5)

    for name in names:
        payload = (PACKAGE / name).read_bytes()
        path = f"{REMOTE_DIRECTORY}/{name}"
        result = json.loads(device.request("/api/system/fs/upload?" + urlencode({"path": path}),
                                           "PUT", payload))
        if result.get("ok") is False:
            raise RuntimeError(f"Upload failed for {name}: {result}")
        actual = device.file(path)
        if hashlib.sha256(actual).digest() != hashlib.sha256(payload).digest():
            raise RuntimeError(f"Uploaded bytes differ for {name}")
        print(f"Verified {name}: {len(payload)} bytes")
    return device.start()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=os.environ.get("RAVEN_DISPLAY_HOST"),
                        help="Device IP or hostname; defaults to RAVEN_DISPLAY_HOST")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("install", help="Install the bundled app and start it")
    commands.add_parser("start", help="Start the installed app")
    commands.add_parser("get", help="Read the app's state")
    state_command = commands.add_parser("state", help="Update the displayed state")
    state_command.add_argument("status", choices=STATES)
    state_command.add_argument("--progress", type=int, choices=range(101), metavar="0..100")
    snapshot_command = commands.add_parser("snapshot", help="Read a rendered device screenshot")
    snapshot_command.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "screen.png")
    snapshot_command.add_argument("--phase-ms", type=int, choices=range(4800), metavar="0..4799",
                                  help="Capture an exact idle animation phase")
    args = parser.parse_args()
    if not args.device:
        parser.error("pass --device or set RAVEN_DISPLAY_HOST")
    device = Device(args.device)
    try:
        if args.command == "install":
            result = install(device)
        elif args.command == "start":
            result = device.start()
        elif args.command == "get":
            result = device.api(device.route() + "/api/state")
        elif args.command == "state":
            value = {"status": args.status}
            if args.progress is not None:
                value["progress"] = args.progress
            result = device.api(device.route() + "/api/state", "POST", value)
        else:
            capture_path = device.route() + "/api/snapshot"
            if args.phase_ms is not None:
                capture_path += "?" + urlencode({"phase_ms": args.phase_ms})
            result = device.api(capture_path, "POST")
            image = device.file(result["path"])
            if not image.startswith(b"\x89PNG\r\n\x1a\n"):
                raise RuntimeError("The device did not return a PNG screenshot")
            args.output.write_bytes(image)
            result = {"ok": True, "screenshot": str(args.output.resolve()), "bytes": len(image)}
        print(json.dumps(result, ensure_ascii=True, indent=2))
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
