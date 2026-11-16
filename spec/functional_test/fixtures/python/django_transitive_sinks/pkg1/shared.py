import subprocess


def run_dup(q):
    return subprocess.run(f"echo {q}", shell=True)
