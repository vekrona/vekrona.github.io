#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SITE_ROOT="${1:-$SITE_REPO}"
[ -d "$SITE_ROOT" ] || fail "$SITE_ROOT is not a directory"

require_commands python3 ffprobe

python3 - "$SITE_ROOT" <<'PY'
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

root = Path(sys.argv[1])
pages = ["index.html", "404.html"]
other_sources = [*sorted(root.glob("assets/css/*.css")), *sorted(root.glob("assets/js/*.js")), root / "site.webmanifest"]
image_path = re.compile(r"/?(assets/img/[A-Za-z0-9._-]+)")
descriptor = re.compile(r"[0-9]+w")

problems = []
references = {}
candidates_checked = 0


def note_reference(path, source):
    references.setdefault(path, source)


def pixel_width(path):
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width", "-of", "csv=p=0", str(path)],
        capture_output=True,
        text=True,
    )
    output = result.stdout.strip()
    return int(output) if result.returncode == 0 and output.isdigit() else None


def check_candidate(candidate, page):
    global candidates_checked
    candidates_checked += 1
    parts = candidate.split()
    match = image_path.fullmatch(parts[0]) if len(parts) == 2 else None
    if match is None or not descriptor.fullmatch(parts[1]):
        problems.append(f"{page}: cannot parse srcset candidate '{candidate}'")
        return
    path = match.group(1)
    note_reference(path, page)
    if not (root / path).is_file():
        return
    actual = pixel_width(root / path)
    declared = int(parts[1][:-1])
    if actual is None:
        problems.append(f"{page}: cannot read the width of {path}")
    elif actual != declared:
        problems.append(f"{page}: {path} is {actual}px wide, but the srcset says {declared}w")


class ImageReferences(HTMLParser):
    def __init__(self, page):
        super().__init__()
        self.page = page

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if value is None:
                continue
            if name == "srcset":
                for candidate in value.split(","):
                    if candidate.strip():
                        check_candidate(candidate.strip(), self.page)
            else:
                for path in image_path.findall(value):
                    note_reference(path, self.page)


for page in pages:
    if not (root / page).is_file():
        problems.append(f"missing {root / page}")
        continue
    parser = ImageReferences(page)
    parser.feed((root / page).read_text(encoding="utf-8"))
    parser.close()

for source in other_sources:
    if source.is_file():
        for path in image_path.findall(source.read_text(encoding="utf-8")):
            note_reference(path, source.relative_to(root).as_posix())

for path, source in sorted(references.items()):
    if not (root / path).is_file():
        problems.append(f"{source} names {path}, which does not exist")

image_dir = root / "assets" / "img"
if image_dir.is_dir():
    for file in sorted(image_dir.iterdir()):
        if file.is_file() and not file.name.startswith(".") and f"assets/img/{file.name}" not in references:
            problems.append(f"assets/img/{file.name} is not referenced by the pages, stylesheets, scripts or manifest")
else:
    problems.append(f"missing {image_dir}")

for problem in problems:
    print(f"check-images.sh: {problem}", file=sys.stderr)
if problems:
    print(f"check-images.sh: {len(problems)} problem(s) between assets/img and the pages", file=sys.stderr)
    sys.exit(1)
print(f"check-images.sh: {candidates_checked} srcset candidates exist with the declared width, every image in assets/img is referenced")
PY
