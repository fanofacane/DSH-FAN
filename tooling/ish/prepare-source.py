#!/usr/bin/env python3
"""Apply the shared, reviewed iSH patches to an isolated export, never the upstream clone."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint_tree(root):
    values = {}
    for path in sorted(root.rglob("*")):
        if path.name == ".probe-patches.json" or not (path.is_file() or path.is_symlink()):
            continue
        value = "link:" + os.readlink(path) if path.is_symlink() else digest(path)
        values[path.relative_to(root).as_posix()] = value
    return values


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()


def export(source, revision, destination):
    destination.mkdir(parents=True, exist_ok=True)
    archive = subprocess.Popen(["git", "-C", str(source), "archive", revision], stdout=subprocess.PIPE)
    try:
        subprocess.run(["tar", "-xf", "-", "-C", str(destination)], stdin=archive.stdout, check=True)
    finally:
        archive.stdout.close()
    if archive.wait():
        raise RuntimeError("git archive failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    upstream, destination = args.upstream.resolve(), args.destination.resolve()
    patch_dir = Path(__file__).resolve().parents[2] / "runtime/ios/patches"
    manifest = json.loads((patch_dir / "series.json").read_text())
    if upstream == destination or upstream in destination.parents:
        parser.error("patched export must be outside the upstream clone")
    if git(upstream, "rev-parse", "HEAD") != manifest["baseRevision"]:
        parser.error("unexpected upstream revision")
    if git(upstream, "status", "--porcelain", "--untracked-files=normal"):
        parser.error("upstream clone must be clean")
    for patch in manifest["patches"]:
        if digest(patch_dir / patch["path"]) != patch["sha256"]:
            parser.error("patch SHA-256 mismatch: " + patch["path"])
    for name, hashes in manifest["files"].items():
        if digest(upstream / name) != hashes["before"]:
            parser.error("upstream input SHA-256 mismatch: " + name)
    expected = {"manifestSha256": digest(patch_dir / "series.json")}
    stamp = destination / ".probe-patches.json"
    previous = json.loads(stamp.read_text()) if stamp.exists() else {}
    if previous.get("manifestSha256") == expected["manifestSha256"] and "files" in previous:
        if fingerprint_tree(destination) != previous["files"]:
            parser.error("isolated source changed outside the checked patch series")
        for name, hashes in manifest["files"].items():
            if digest(destination / name) != hashes["after"]:
                parser.error("patched source changed outside patches: " + name)
        print(destination)
        return
    # Only remove an earlier export that this script marked, never an arbitrary directory.
    if destination.exists():
        if not stamp.exists():
            parser.error("refusing to replace an unmarked source directory")
        shutil.rmtree(destination)
    export(upstream, manifest["baseRevision"], destination)
    # Mark our export before applying patches, so a failed build can be retried.
    stamp.write_text(json.dumps(expected) + "\n")
    # libarchive is the only submodule needed by the static runtime.
    module = upstream / "deps/libarchive"
    module_rev = git(upstream, "rev-parse", "HEAD:deps/libarchive")
    if git(module, "rev-parse", "HEAD") != module_rev or git(module, "status", "--porcelain"):
        parser.error("libarchive submodule must match its clean pinned revision")
    export(module, module_rev, destination / "deps/libarchive")
    for patch in manifest["patches"]:
        path = str(patch_dir / patch["path"])
        # An export inside dsh-fan must not discover the parent repository: git
        # otherwise silently skips patches whose paths are outside that subdir.
        env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(destination.parent))
        subprocess.run(["git", "-C", str(destination), "apply", "--check", path], check=True, env=env)
        subprocess.run(["git", "-C", str(destination), "apply", path], check=True, env=env)
    for name, hashes in manifest["files"].items():
        if digest(destination / name) != hashes["after"]:
            parser.error("patched output SHA-256 mismatch: " + name)
    expected["files"] = fingerprint_tree(destination)
    stamp.write_text(json.dumps(expected, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
