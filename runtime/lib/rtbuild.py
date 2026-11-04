#!/usr/bin/env python3
"""Apply the pinned DSH patch chain for the iOS runtime and independent Host tests.

Downloaded package files are treated as data. The strict patch parser and hash
checks are shared with the session-deletion patch generator.
"""
import argparse
import hashlib
import json
import os
import sys


def parse_unified_diff(text):
    """[(relpath, [(old_lines, new_lines)])] for a plain unified diff (a/ b/ prefixes, no fuzz)."""
    files, cur, lines = [], None, text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("--- "):
            plus = lines[i + 1] if i + 1 < len(lines) else ""
            if not plus.startswith("+++ "):
                raise ValueError("'---' without '+++' at line %d" % (i + 1))
            path = plus[4:].split("\t", 1)[0].strip()
            path = path[2:] if path.startswith("b/") else path
            if path.startswith("/") or ".." in path.split("/"):
                raise ValueError("unsafe path in diff: " + path)
            cur = (path, [])
            files.append(cur)
            i += 2
            continue
        if line.startswith("@@"):
            if cur is None:
                raise ValueError("hunk before file header at line %d" % (i + 1))
            head = line.split("@@")[1].split()
            counts = [int(r.split(",")[1]) if "," in r else 1 for r in head]   # "-a,b +c,d"
            left_old, left_new = counts
            old, new = [], []
            i += 1
            while left_old > 0 or left_new > 0:
                if i >= len(lines):
                    raise ValueError("truncated hunk in %s" % cur[0])
                body = lines[i]
                i += 1
                if body.startswith("\\"):        # "\ No newline at end of file"
                    continue
                tag, rest = body[:1], body[1:]
                if body in ("\n", "\r\n"):        # context line whose leading space was stripped
                    tag, rest = " ", body
                if tag == " ":
                    old.append(rest)
                    new.append(rest)
                    left_old -= 1
                    left_new -= 1
                elif tag == "-":
                    old.append(rest)
                    left_old -= 1
                elif tag == "+":
                    new.append(rest)
                    left_new -= 1
                else:
                    raise ValueError("bad hunk line %d in %s: %r" % (i, cur[0], body[:40]))
            if left_old or left_new:
                raise ValueError("hunk line counts do not match its header in %s" % cur[0])
            cur[1].append(("".join(old), "".join(new)))
            continue
        i += 1
    return files


def apply_hunks(data, hunks, label):
    """Each hunk's old block (context + removed lines) must occur exactly once; no fuzz, any offset."""
    for n, (old, new) in enumerate(hunks, 1):
        count = data.count(old)
        if count != 1:
            raise SystemExit("%s: hunk %d matches %d places (needs exactly 1); the upstream file changed, "
                             "re-vet the patch" % (label, n, count))
        data = data.replace(old, new, 1)
    return data


def cmd_patch_dsh(args):
    """Apply runtime/patches/*.diff to a DSH npm prefix, refusing anything not pinned for this DSH version.

    pins.json maps patch -> DSH version -> file -> {before, after} sha256. Without --record the
    original must match `before` and the result `after`; files are replaced (write + rename), so a
    hard-linked tree is never modified in place. --record applies the hunks strictly and writes the
    observed hashes for this DSH version (use after reviewing the upstream file and the patch)."""
    pins_path = os.path.join(args.patches, "pins.json")
    pins = json.load(open(pins_path)) if os.path.isfile(pins_path) else {"schema": 1, "patches": {}}
    names = sorted(n for n in os.listdir(args.patches) if n.endswith(".diff"))
    if not names:
        sys.exit("no patches in " + args.patches)
    # Several independently reviewed patches may touch the same file. Their
    # pins must form one ordered chain, and a fully patched tree is a valid
    # idempotent input. Never accept an arbitrary intermediate/custom hash.
    terminal = {}
    if not args.record:
        for name in names:
            for rel, pin in pins["patches"].get(name, {}).get(args.dsh_version, {}).items():
                if rel in terminal and terminal[rel] != pin["before"]:
                    sys.exit("%s: broken patch hash chain for %s" % (name, rel))
                terminal[rel] = pin["after"]
    applied = []
    for name in names:
        diff = parse_unified_diff(open(os.path.join(args.patches, name)).read())
        want = pins["patches"].get(name, {}).get(args.dsh_version)
        if want is None and not args.record:
            sys.exit("patch %s has no pin for DSH %s: review the upstream files it touches, then run\n"
                     "  python3 -I runtime/lib/rtbuild.py patch-dsh --prefix <dsh-prefix> --dsh-version %s --record"
                     % (name, args.dsh_version, args.dsh_version))
        observed = {}
        for rel, hunks in diff:
            path = os.path.join(args.prefix, rel)
            raw = open(path, "rb").read()
            before = hashlib.sha256(raw).hexdigest()
            pin = (want or {}).get(rel)
            if not args.record:
                if pin is None:
                    sys.exit("%s: no pin for %s" % (name, rel))
                if before == pin["after"] or before == terminal.get(rel):
                    print("%s: %s already patched" % (name, rel))
                    observed[rel] = pin
                    continue
                if before != pin["before"]:
                    sys.exit("%s: %s sha256 %s differs from the vetted DSH %s original %s"
                             % (name, rel, before, args.dsh_version, pin["before"]))
            out = apply_hunks(raw.decode("utf-8"), hunks, "%s %s" % (name, rel)).encode("utf-8")
            after = hashlib.sha256(out).hexdigest()
            if not args.record and after != pin["after"]:
                sys.exit("%s: %s patched sha256 %s != pinned %s" % (name, rel, after, pin["after"]))
            mode = os.stat(path).st_mode & 0o777
            tmp = path + ".dsh-app-patch"
            with open(tmp, "wb") as f:
                f.write(out)
            os.chmod(tmp, mode)
            os.replace(tmp, path)
            observed[rel] = {"before": before, "after": after}
            print("%s: patched %s (%s -> %s)" % (name, rel, before[:12], after[:12]))
        if args.record:
            pins["patches"].setdefault(name, {})[args.dsh_version] = observed
        applied.append(name)
    if args.record:
        with open(pins_path, "w") as f:
            json.dump(pins, f, indent=2, sort_keys=True)
            f.write("\n")
        print("recorded pins for DSH %s in %s" % (args.dsh_version, pins_path))
    if "zzzzzz-session-deletion.diff" in applied:
        # Source-owned companion module, installed only alongside the vetted rc4 seam.
        source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "session-deletion", "core.mjs")
        target = os.path.join(args.prefix, "node_modules", "@deepseek-ai", "dsh-session-persistence-jsonl", "lib", "dsh-fan-deletion.mjs")
        tmp = target + ".dsh-app-patch"
        with open(source, "rb") as src, open(tmp, "wb") as dst:
            dst.write(src.read())
        os.chmod(tmp, 0o644)
        os.replace(tmp, target)
    if args.out:
        with open(args.out, "w") as f:
            json.dump(applied, f)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("patch-dsh")
    p.add_argument("--prefix", required=True, help="npm --prefix tree holding node_modules/@deepseek-ai/...")
    p.add_argument("--dsh-version", required=True)
    p.add_argument("--patches", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "patches"))
    p.add_argument("--record", action="store_true", help="write the observed hashes as this version's pins")
    p.add_argument("--out", help="write the applied patch names (JSON list) here")
    p.set_defaults(fn=cmd_patch_dsh)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
