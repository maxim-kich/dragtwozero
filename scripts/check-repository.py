#!/usr/bin/env python3
"""Check publishable files without printing potential secret values."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
names = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
).decode().split("\0")
patterns = [
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{50,}\b"),
    re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
]
blocked_dirs = {".local", "output", "handoff", ".build", "dist"}
approved_media = {"assets/Onboarding/Background.mp4"}
problems = []
for name in sorted(set(names)):
    path = root / name
    if not name or not path.is_file():
        continue
    relative = Path(name)
    if relative.parts[0] in blocked_dirs or (path.suffix.lower() in {".p12", ".p8", ".key", ".mobileprovision", ".mov", ".mp4"} and name not in approved_media):
        problems.append((name, "private/build artifact in publication set"))
    if path.name.startswith(".env") and path.name != ".env.example":
        problems.append((name, "environment file in publication set"))
    data = path.read_bytes()
    if any(pattern.search(data) for pattern in patterns):
        problems.append((name, "possible credential; inspect privately"))
    if len(data) > 10 * 1024 * 1024:
        problems.append((name, "unexpected file over 10 MiB"))
for name, reason in problems:
    print(f"FAIL {name}: {reason}")
if problems:
    raise SystemExit(1)
print("Publication file checks passed. This is a limited pattern scan, not a security audit.")
