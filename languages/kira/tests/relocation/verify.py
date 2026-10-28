"""Run with the compiled relocation probe path. Uses an isolated temporary store."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

probe = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="tessera-train-probe-") as temporary:
    root = Path(temporary)
    alias = root / "workspace-alias"
    alias.symlink_to(root, target_is_directory=True)
    env = {**os.environ, "KIRA_BUILD_CACHE": str(root / "cache")}
    for name in ("development", "worktree", "capture", "imported", "shared"):
        directory = root / name
        directory.mkdir()
        (directory / "library.txt").write_text("library v1\n")
        (directory / "unrelated.txt").write_text("unrelated v1\n")
        (directory / "anchor.txt").write_text("stable anchor\n")
        (directory / "discovered.txt").write_text("dependency v1\n")

    def run(name, **extra):
        result = subprocess.run(
            [probe], env={**env, "FIXTURE_ROOT": str((alias if name == "worktree" else root) / name), **extra},
            capture_output=True, text=True, timeout=30,
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        return output

    def ran(output):
        return re.findall(r"\[\d+/\d+\] (compile \w+)", output)

    assert ran(run("development")) == ["compile library", "compile dependent", "compile unrelated", "compile discovered"]
    assert ran(run("worktree")) == []
    (root / "worktree/library.txt").write_text("library v2\n")
    assert ran(run("worktree")) == ["compile library", "compile dependent"]
    assert ran(run("development")) == []
    (root / "worktree/discovered.txt").write_text("dependency v2\n")
    assert ran(run("worktree")) == ["compile discovered"]
    # A second dependency variant must not evict the base workspace's result.
    assert ran(run("development")) == []
    assert ran(run("worktree")) == []
    before_variants = {p.name for p in (root / "cache/variants").glob("*/*") if p.is_file()}
    assert len(before_variants) == 2
    captured = run("capture", FIXTURE_CAPTURE="yes")
    snapshot = re.search(r"snapshot ([0-9a-f]{64})", captured).group(1)
    pin = root / "cache/snapshots" / snapshot
    original = pin.read_bytes()
    assert not (root / "capture/.kira-build/out").exists()
    first_views = run("shared", FIXTURE_SNAPSHOT=snapshot, FIXTURE_SHARED="yes")
    second_views = run("imported", FIXTURE_SNAPSHOT=snapshot, FIXTURE_SHARED="yes")
    assert re.findall(r"shared (.+)", first_views) == re.findall(r"shared (.+)", second_views)
    assert not (root / "shared/.kira-build/out").exists()
    assert not (root / "imported/.kira-build/out").exists()
    for name in ("development", "worktree", "capture", "shared"):
        shutil.rmtree(root / name)
    imported = run("imported", FIXTURE_SNAPSHOT=snapshot, FIXTURE_FORCE_SWEEP="yes")
    assert ran(imported) == []
    assert (root / "imported/.kira-build/out/all/library").read_text() == "library v1\n"
    assert pin.read_bytes() == original
    after_variants = {p.name for p in (root / "cache/variants").glob("*/*") if p.is_file()}
    assert len(after_variants) == 1 and after_variants < before_variants
    # Collection ran after the originating workspaces disappeared. Reimport
    # proves the immutable pin retained its complete artifacts.
    shutil.rmtree(root / "imported/.kira-build")
    run("imported", FIXTURE_SNAPSHOT=snapshot)
    assert (root / "imported/.kira-build/out/all/dependent").read_text() == "library v1\n"
    print("PASS: cross-workspace reuse; dependency-only rebuild; discovered-input variants; immutable capture; shared views; import after forced GC")
