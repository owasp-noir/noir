"""Refresh the runtime manifests with each app's pinned container."""

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


APPS = Path(__file__).resolve().parent / "apps"
NAMES = ("express", "hono", "fastapi", "gin")


def generate(name, staging):
    image_id = staging / "image.id"
    subprocess.run(["docker", "build", "--iidfile", image_id, APPS / name], check=True)
    run = ["docker", "run", "--rm", "--network", "none", image_id.read_text().strip()]
    rows = json.loads(subprocess.check_output(run))
    if not isinstance(rows, list) or not rows:
        raise ValueError(f"{name}: expected a nonempty route table")
    for row in rows:
        if (not isinstance(row, dict) or row.keys() != {"method", "path"}
                or not all(isinstance(s, str) and s for s in row.values())):
            raise ValueError(f"{name}: invalid route {row!r}")
    keys = [(row["path"], row["method"]) for row in rows]
    if keys != sorted(set(keys)):
        raise ValueError(f"{name}: route table contains duplicate or unsorted rows")

    version = subprocess.check_output([*run, "--version"], text=True).strip()
    if not version or len(version.splitlines()) != 1:
        raise ValueError(f"{name}: expected one framework version")
    provenance = {
        "framework": name,
        "version": version,
        "date": datetime.now(timezone.utc).date().isoformat(),
    }
    for filename, data in [("routes.json", rows), ("provenance.json", provenance)]:
        (staging / filename).write_text(json.dumps(data, indent=2) + "\n")


def main():
    # Finish every build, dump and validation before replacing existing files.
    with TemporaryDirectory(dir=APPS.parent) as tmp:
        for name in NAMES:
            staging = Path(tmp) / name
            staging.mkdir()
            generate(name, staging)
        for name in NAMES:
            for filename in ("provenance.json", "routes.json"):
                (Path(tmp) / name / filename).replace(APPS / name / filename)


if __name__ == "__main__":
    main()
