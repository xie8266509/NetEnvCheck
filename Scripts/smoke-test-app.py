#!/usr/bin/env python3
"""Exercise GUI startup and the first network probe on a logged-in macOS desktop.

Quit other copies of NetEnvCheck first. This uses the current user's app settings
and network, and adds a normal report to app history. Test with notifications
both enabled and disabled to exercise authorization and probe completion.

No system network settings are changed. App output is discarded rather than
printing potentially sensitive diagnostics. Only this test's process is stopped.
"""
import argparse
import math
import pathlib
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--seconds", type=float, default=45)
    args = parser.parse_args()
    if not math.isfinite(args.seconds) or args.seconds <= 0:
        parser.error("--seconds must be a finite positive number")

    exe = args.app.resolve() / "Contents/MacOS/NetEnvCheck"
    if not exe.is_file():
        parser.error("The app bundle does not contain a NetEnvCheck executable")
    running = subprocess.run(
        ["pgrep", "-x", "NetEnvCheck"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if running.returncode == 0:
        parser.error("Quit other copies of NetEnvCheck before running this test")
    if running.returncode != 1:
        parser.error("Could not check for an existing NetEnvCheck process")

    history = pathlib.Path.home() / "Library/Application Support/NetEnvCheck/history.json"
    original = history.read_bytes() if history.exists() else None
    proc = subprocess.Popen(
        [str(exe), "-ApplePersistenceIgnoreState", "YES"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    deadline = time.monotonic() + args.seconds
    completed_probe = False
    try:
        while time.monotonic() < deadline:
            code = proc.poll()
            if code is not None:
                print(f"FAIL: app exited prematurely with code {code}")
                return 1
            if history.exists() and history.read_bytes() != original:
                completed_probe = True
            time.sleep(0.2)
        if proc.poll() is not None:
            print("FAIL: app exited before the observation period ended")
            return 1
        if not completed_probe:
            print("FAIL: app survived but no completed probe was saved")
            return 1
        print(f"PASS: survived {args.seconds:g}s and saved a new probe report")
        return 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


if __name__ == "__main__":
    sys.exit(main())
