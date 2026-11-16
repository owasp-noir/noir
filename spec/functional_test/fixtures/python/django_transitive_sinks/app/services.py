import subprocess
from shared import run_dup
from . import repo


def run_export(target):
    return subprocess.run(f"export.sh {target}", shell=True)


def build_report(name):
    rows = repo.find_rows(name)
    return ",".join(rows)


def call_ambiguous(q):
    return run_dup(q)


def ping_a(n):
    if n <= 0:
        return "done"
    return ping_b(n - 1)


def ping_b(n):
    return ping_a(n - 1)


def normalize(q):
    return (q or "").strip().lower()
