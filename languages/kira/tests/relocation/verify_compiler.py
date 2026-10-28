"""Exercise cross-workspace reuse with real Kira library and executable builds."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

probe = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="tessera-real-compile-") as temporary:
    root = Path(temporary)
    alias = root / "workspace-alias"
    alias.symlink_to(root, target_is_directory=True)
    env = {**os.environ, "KIRA_BUILD_CACHE": str(root / "cache"), "FIXTURE_COMPILER": "yes"}
    for workspace in ("development", "worktree"):
        for package in ("library", "consumer", "unrelated"):
            directory = root / workspace / package
            (directory / "app").mkdir(parents=True)
            kind = "Library" if package == "library" else "App"
            module = '    let moduleRoot: String = "Probe"\n' if package == "library" else ""
            dependency = '    let dependencies: [Dependency] = [Dependency { name: "Probe", path: "../library" }]\n' if package == "consumer" else ""
            (directory / "package.kira").write_text(
                f'construct Probe{package.title()} extends Package {{\n'
                f'    let version: String = "0.1.0"\n'
                f'    let kind: PackageKind = .{kind}\n{module}{dependency}'
                '}\n'
            )
            source = {
                "library": 'import Foundation\npublic function probeValue() -> Number { return 1 }\n',
                "consumer": 'import Foundation\nimport Probe\n@Main\nfunction main() -> Number { print(probeValue()) return 0 }\n',
                "unrelated": 'import Foundation\n@Main\nfunction main() -> Number { print("unrelated") return 0 }\n',
            }[package]
            (directory / "app/Main.kira").write_text(source)

    def run(workspace):
        result = subprocess.run(
            [probe], env={**env, "FIXTURE_ROOT": str((alias if workspace == "worktree" else root) / workspace)},
            capture_output=True, text=True, timeout=180,
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        return re.findall(r"\[\d+/\d+\] compile (library|consumer|unrelated)", output)

    assert run("development") == ["library", "consumer", "unrelated"]
    assert run("worktree") == []
    consumer = root / "worktree/.kira-build/out/all/consumer"
    assert subprocess.check_output([str(consumer)], text=True, timeout=10).strip() == "1"
    source = root / "worktree/library/app/Main.kira"
    source.write_text(source.read_text().replace("return 1", "return 2"))
    changed = run("worktree")
    assert changed == ["library", "consumer"], changed
    assert subprocess.check_output([str(consumer)], text=True, timeout=10).strip() == "2"
    assert run("development") == []
    print("PASS: real Kira compiles reused across workspaces; library edit rebuilt library + consumer only")
