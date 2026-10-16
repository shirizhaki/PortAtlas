#!/usr/bin/env python3
"""Package Git-visible source, rejecting common private files and secret markers."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check-git-history", action="store_true",
                    help="Also require anonymous author/committer metadata in every commit reachable from HEAD.")
options = parser.parse_args()
root = Path(__file__).resolve().parent.parent
anonymous_name = "PortAtlas contributors"
anonymous_email = "contributors" + "@" + "portatlas.invalid"
email_pattern = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
patterns = [
    re.compile(rb"/(?:Users|home)/[^/\s]+"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(rb"\bsk-proj-[A-Za-z0-9_-]{20,}\b"),
]
forbidden_dirs = {"build", ".build", ".git", ".codex", ".agents", ".ssh", ".aws", "LocalCaptures", "LocalSettings", "xcuserdata"}
forbidden_names = {"ports.json", "presentation.json", ".DS_Store", ".netrc", ".gitconfig", ".git-credentials"}
forbidden_suffixes = {".ioreg", ".spx", ".p12", ".pfx", ".pem", ".key", ".log"}

with tempfile.TemporaryDirectory(prefix="portatlas-source-") as folder:
    index = Path(folder) / "index.git"
    subprocess.run(["git", "init", "--bare", "--quiet", str(index)], check=True)
    command = ["git", "--git-dir=" + str(index), "--work-tree=" + str(root)]
    subprocess.run(command + ["add", "--all"], cwd=root, check=True)
    names = [n for n in subprocess.check_output(command + ["ls-files", "-z"], cwd=root).decode().split("\0") if n]
    # Also catch sensitive files that were already tracked before .gitignore was added.
    tracked = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True)
    if tracked.returncode == 0:
        names = sorted(set(names) | {n for n in tracked.stdout.decode().split("\0") if n and (root / n).exists()})
    issues = []
    for name in names:
        path = Path(name)
        source = root / path
        if (source.is_symlink() or any(part in forbidden_dirs for part in path.parts)
                or path.name in forbidden_names or path.suffix in forbidden_suffixes
                or path.name == ".env" or path.name.startswith(".env.") and path.name != ".env.example"):
            issues.append(name + ": private file or symlink")
            continue
        data = source.read_bytes()
        if any(pattern.search(data) for pattern in patterns):
            issues.append(name + ": possible personal path or credential")
        if any(match.group() != anonymous_email.encode() for match in email_pattern.finditer(data)):
            issues.append(name + ": email-like text requires review")
    if options.check_git_history:
        # Read raw commit headers rather than mailmap-rewritten display identities.
        commits = subprocess.check_output(["git", "-C", str(root), "rev-list", "HEAD"], text=True).splitlines()
        expected_identity = f"{anonymous_name} <{anonymous_email}> ".encode()
        for commit in commits:
            raw = subprocess.check_output(["git", "-C", str(root), "cat-file", "commit", commit])
            headers = raw.split(b"\n\n", 1)[0].splitlines()
            for field in (b"author ", b"committer "):
                values = [line[len(field):] for line in headers if line.startswith(field)]
                if len(values) != 1 or not values[0].startswith(expected_identity):
                    issues.append(commit[:12] + ": nonanonymous commit " + field.decode().strip())
            if any(pattern.search(raw) for pattern in patterns) or any(
                    match.group() != anonymous_email.encode() for match in email_pattern.finditer(raw)):
                issues.append(commit[:12] + ": commit text contains an email, personal path, or credential marker")
    if issues:
        raise SystemExit("Source package blocked; review these files:\n" + "\n".join(issues))
    output = root / "build" / "PortAtlas-source.zip"
    output.parent.mkdir(exist_ok=True)
    staged = Path(folder) / "PortAtlas-source.zip"
    with zipfile.ZipFile(staged, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            # Do not disclose local modification timestamps or inherited file metadata.
            source = root / name
            entry = zipfile.ZipInfo("PortAtlas/" + name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (0o100755 if source.stat().st_mode & 0o111 else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, source.read_bytes())
    staged.replace(output)
    print(f"Packaged {len(names)} source files in build/PortAtlas-source.zip")
    print("Pattern checks passed. Review the package before sharing; scans cannot detect every kind of private information.")
