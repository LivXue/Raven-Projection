"""Encode an idle-loop GIF from exact frames rendered by the Cubic device."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path
from urllib.parse import urlencode

from raven_screen import Device


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=os.environ.get("RAVEN_DISPLAY_HOST"),
                        help="Device IP or hostname; defaults to RAVEN_DISPLAY_HOST")
    parser.add_argument("--frames", type=int, choices=(24, 48), default=24)
    parser.add_argument("--output", type=Path, default=Path("raven-idle-preview.gif"))
    args = parser.parse_args()
    if not args.device:
        parser.error("pass --device or set RAVEN_DISPLAY_HOST")

    import imageio_ffmpeg

    device = Device(args.device)
    route = device.route()
    before = device.api(route + "/api/state")
    if before["status"] != "idle" or not before["animation"]["running"]:
        raise RuntimeError("Set the display to idle before capturing the loop")
    period_ms = before["animation"]["period_ms"]
    phases = {period_ms * index // args.frames for index in range(args.frames)}
    for phase in before["animation"].get("blink_keyframes_ms", []):
        if isinstance(phase, int) and 0 <= phase < period_ms:
            phases.add(phase)
    phases = sorted(phases)
    directory = args.output.resolve().parent / (args.output.stem + "-frames")
    directory.mkdir(parents=True, exist_ok=True)
    digests = set()
    started = time.monotonic()

    captured_opacities = []
    captured_positions = []
    for index, phase_ms in enumerate(phases):
        result = device.api(route + "/api/snapshot?" + urlencode({"phase_ms": phase_ms}), "POST")
        data = device.file(result["path"])
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise RuntimeError(f"Frame {index} is not a PNG")
        (directory / f"{index:03d}.png").write_bytes(data)
        digests.add(hashlib.sha256(data).hexdigest())
        captured_opacities.append(result.get("blink_opacity", 0))
        captured_positions.append({"x": result.get("x"), "y": result.get("y")})
        print(f"Captured frame {index + 1}/{len(phases)}, phase {phase_ms} ms", flush=True)

    if len(digests) < args.frames // 2:
        raise RuntimeError("Too few distinct frames: the idle animation may be frozen")
    after = device.api(route + "/api/state")
    if not after["animation"]["running"] or after["animation"]["ticks"] <= before["animation"]["ticks"]:
        raise RuntimeError("Idle playback stopped during capture")

    timeline = ["ffconcat version 1.0"]
    for index, phase_ms in enumerate(phases):
        next_phase = phases[index + 1] if index + 1 < len(phases) else period_ms
        timeline.extend([
            f"file '{index:03d}.png'", "option framerate 100",
            f"duration {(next_phase - phase_ms) / 1000:.3f}",
        ])
    timeline.extend([f"file '{len(phases) - 1:03d}.png'", "option framerate 100"])
    manifest = directory / "timeline.ffconcat"
    manifest.write_text("\n".join(timeline) + "\n", encoding="utf-8")
    subprocess.run([
        imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y",
        "-f", "concat", "-safe", "0", "-i", str(manifest),
        "-filter_complex",
        "[0:v]split[a][b];[a]palettegen=stats_mode=full[p];"
        "[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
        "-fps_mode", "vfr", "-t", str(period_ms / 1000),
        "-final_delay", str((period_ms - phases[-1]) // 10),
        "-loop", "0", str(args.output.resolve()),
    ], check=True)
    summary = {
        "frames": len(phases),
        "distinct_frames": len(digests),
        "period_ms": period_ms,
        "capture_elapsed_seconds": round(time.monotonic() - started, 2),
        "animation_ticks_before": before["animation"]["ticks"],
        "animation_ticks_after": after["animation"]["ticks"],
        "phases_ms": phases,
        "blink_opacities": captured_opacities,
        "positions": captured_positions,
        "output": str(args.output.resolve()),
    }
    args.output.with_suffix(".json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
