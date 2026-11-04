#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Run iOS smoke cases on the project's iPhone 18 Pro, checking final results."""
import argparse
import json
import re
import tempfile
from pathlib import Path
import shlex
import subprocess
import time

SIM = "51831DA4-9348-4053-A81C-54B3C995A73A"
BUNDLE = "io.github.fanofacane.dsh"
CASES = ("store", "t1", "t4", "t7", "t10", "t13", "t15", "chat", "menu")


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()


class EngineStartupFailure(RuntimeError):
    pass


def run_case(name):
    flags = ["-dsh-feature-smoke", name]
    filename = "feature-" + name + ".json"
    if name in ("chat", "menu"):
        flags = ["-dsh-" + name + "-smoke"]
        filename = name + "-smoke.json"
    flags.append("-dsh-dump-log")
    subprocess.run(["xcrun", "simctl", "terminate", SIM, BUNDLE],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    container = Path(simctl("get_app_container", SIM, BUNDLE, "data"))
    path = container / "Documents" / filename
    path.unlink(missing_ok=True)
    engine_log = container / "Documents" / "engine-log.txt"
    engine_log.unlink(missing_ok=True)
    # A system relaunch between terminate and launch must not reuse a process
    # that was started without the test arguments.
    launch = simctl("launch", "--terminate-running-process", SIM, BUNDLE, *flags)
    pid = int(launch.rsplit(":", 1)[1])
    command = subprocess.check_output(["ps", "-ww", "-p", str(pid), "-o", "command="], text=True).strip()
    args = shlex.split(command)
    if f"/Devices/{SIM}/" not in command or not any(
        args[i:i + len(flags)] == flags for i in range(len(args))
    ):
        raise RuntimeError(f"{name}: DSH device or smoke arguments do not match")
    print(f"{name}: ps verified PID {pid}, SIM={SIM}, arguments={flags}", flush=True)
    deadline = time.monotonic() + 720
    while time.monotonic() < deadline:
        try:
            result = json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            result = {}
        state = result.get("result")
        if state is not None and state != "RUNNING":
            print(name + ": " + json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
            if state != "PASS":
                raise RuntimeError(f"{name}: {state}")
            return
        # A startup failure never enters the smoke case, so there is no result JSON.
        # Preserve that attempt before an identical relaunch overwrites the dump.
        if not result and engine_log.exists():
            text = engine_log.read_text()
            failure = re.search(r"\[dsh-app\] (E_[A-Z0-9_]+)(?:$|\s)", text)
            if failure:
                saved = Path(tempfile.mkdtemp(prefix="dsh-smoke-" + name + "-")) / "engine-log.txt"
                saved.write_text(text)
                saved.chmod(0o600)
                raise EngineStartupFailure(f"{name}: {failure.group(1)}; saved {saved}")
        time.sleep(2)
    raise TimeoutError(f"{name}: no completed result after 720 seconds")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", nargs="*", metavar="CASE", help="Choices: " + ", ".join(CASES))
    args = parser.parse_args()
    if any(name not in CASES for name in args.cases):
        parser.error("Unknown case; choose from " + ", ".join(CASES))
    # Simulator apps share the Mac's loopback ports. Detect another DSH without
    # printing its arguments or touching any other simulator (including WOO).
    processes = subprocess.check_output(["ps", "-ww", "-axo", "pid=,comm="], text=True)
    for line in processes.splitlines():
        if "/DSH.app/DSH" in line and f"/Devices/{SIM}/" not in line:
            raise RuntimeError("Another simulator is running DSH; resolve the port conflict before testing")
    for name in args.cases or CASES:
        if name == "t4":
            import socket
            with socket.create_connection(("127.0.0.1", 38911), timeout=2):
                pass
        for attempt in range(2):
            try:
                run_case(name)
                break
            except EngineStartupFailure as failure:
                print(str(failure), flush=True)
                if attempt == 1:
                    raise
                print(name + ": retrying once with identical arguments", flush=True)


if __name__ == "__main__":
    main()
