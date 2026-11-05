#!/usr/bin/env python3
"""Measure active-Kira package scaling with an executable cross-package graph."""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
import statistics
import subprocess
import time
from functools import lru_cache
from pathlib import Path


DEFAULT_COUNTS = (1, 10, 100, 1_000, 10_000)
COMMON_PACKAGES = 3


def package_name(index: int) -> str:
    return f"BenchPackage{index:05d}"


def function_targets(function: int, total: int) -> tuple[int, int, int, int]:
    return (
        (function + 1) % total,
        (function * 7_919 + 17) % total,
        (function * 10_007 + 31) % total,
        (function * 12_289 + 47) % total,
    )


def function_package(function: int, count: int, sources: int, per_file: int) -> int:
    source = function // per_file
    return min(source * count // sources, count - 1)


def package_functions(index: int, count: int, sources: int, per_file: int) -> range:
    first = index * sources // count * per_file
    after = (index + 1) * sources // count * per_file
    return range(first, after)


def package_dependencies(index: int, count: int, sources: int, per_file: int) -> list[int]:
    if count == 1:
        return []
    dependencies = {(index + 1) % count, (index - 1) % count}
    dependencies.update(target for target in range(min(COMMON_PACKAGES, count)) if target != index)
    total = sources * per_file
    for function in package_functions(index, count, sources, per_file):
        for target in function_targets(function, total):
            other = function_package(target, count, sources, per_file)
            if other != index:
                dependencies.add(other)
    return sorted(dependencies)


def source_imports(source: int, owner: int, count: int, sources: int, per_file: int) -> list[int]:
    if count == 1:
        return []
    imports = {(owner + 1) % count, (owner - 1) % count}
    imports.update(target for target in range(min(COMMON_PACKAGES, count)) if target != owner)
    for function in range(source * per_file, (source + 1) * per_file):
        for target in function_targets(function, sources * per_file):
            other = function_package(target, count, sources, per_file)
            if other != owner:
                imports.add(other)
    return sorted(imports)


def routed_value(value: int, depth: int) -> tuple[int, int]:
    mixed = value * 7 + depth * 3 + 11
    folded = mixed * (value + 5) + depth * 13
    return folded + mixed * 2 + value, folded


def expected_result(total: int) -> int:
    @lru_cache(maxsize=None)
    def evaluate(function: int, value: int, depth: int) -> int:
        routed, folded = routed_value(value, depth)
        if depth == 0:
            return routed
        targets = function_targets(function, total)
        return (
            evaluate(targets[0], routed, depth - 1)
            + evaluate(targets[1], routed + 1, depth - 1)
            + evaluate(targets[2], routed + 2, depth - 1)
            + evaluate(targets[3], routed + 3, depth - 1)
            + folded
        )

    return evaluate(total - 1, 3, 2)


def package_manifest(index: int, count: int, sources: int, per_file: int, dependencies: list[int] | None = None) -> str:
    kind = "App" if index == count - 1 else "Library"
    rows = [
        f"construct Bench{index:05d} extends Package {{",
        f"    let kind: PackageKind = .{kind}",
        f'    let moduleRoot: String = "{package_name(index)}"',
    ]
    if dependencies is None:
        dependencies = package_dependencies(index, count, sources, per_file)
    if dependencies:
        rows.append("    let dependencies: [Dependency] = [")
        for position, target in enumerate(dependencies):
            if index == count - 1:
                path = f"packages/pkg-{target:05d}"
            elif target == count - 1:
                path = "../.."
            else:
                path = f"../pkg-{target:05d}"
            comma = "," if position + 1 < len(dependencies) else ""
            rows.append(
                f'        Dependency {{ name: "{package_name(target)}", path: "{path}" }}{comma}'
            )
        rows.append("    ]")
    rows.append("}")
    return "\n".join(rows) + "\n"


def function_source(function: int, total: int) -> str:
    local, first, second, third = function_targets(function, total)
    return "\n".join(
        [
            f"public function layer_{function:05d}(value: Number, depth: Number) -> Number {{",
            "    let mixed = value * 7 + depth * 3 + 11",
            "    let folded = mixed * (value + 5) + depth * 13",
            "    let routed = folded + mixed * 2 + value",
            "    if depth == 0 { return routed }",
            f"    let local = layer_{local:05d}(routed, depth - 1)",
            f"    let left = layer_{first:05d}(routed + 1, depth - 1)",
            f"    let middle = layer_{second:05d}(routed + 2, depth - 1)",
            f"    let right = layer_{third:05d}(routed + 3, depth - 1)",
            "    return local + left + middle + right + folded",
            "}",
            "",
        ]
    )


def source_text(
    source: int, owner: int, count: int, sources: int, per_file: int, package_imports: list[int] | None = None
) -> tuple[str, int]:
    imports = ["import Foundation"]
    imported_packages = source_imports(source, owner, count, sources, per_file) if package_imports is None else package_imports
    imports.extend(f"import {package_name(index)}" for index in imported_packages)
    bodies = [function_source(source * per_file + offset, sources * per_file) for offset in range(per_file)]
    if owner == count - 1 and source == sources - 1:
        entry = sources * per_file - 1
        bodies.extend(
            [
                "@Main function main() {",
                f"    let result: Number = layer_{entry:05d}(3, 2)",
                "}",
                "",
            ]
        )
    function_bytes = sum(len(body.encode()) for body in bodies)
    return "\n".join(imports + [""] + bodies), function_bytes


def test_source(total: int) -> str:
    entry = total - 1
    return "\n".join(
        [
            "import Foundation",
            "",
            "@Test",
            "function packageGraphComputesExpectedResult() {",
            f"    let result: Number = layer_{entry:05d}(3, 2)",
            f"    expect!(result == {expected_result(total)})",
            "}",
            "",
        ]
    )


def write_project(root: Path, count: int, sources: int, per_file: int) -> dict[str, int]:
    if root.exists():
        raise RuntimeError(f"preserving existing benchmark project directory: {root}")
    total = sources * per_file
    metrics = {
        "source_bytes": 0,
        "function_body_bytes": 0,
        "manifest_bytes": 0,
        "dependency_edges": 0,
        "dependency_imports": 0,
        "common_dependency_imports": 0,
        "minimum_common_dependency_importers": 0,
        "cyclic_dependency_edges": 0,
        "cross_package_calls": 0,
    }
    common_importers = [0] * min(COMMON_PACKAGES, count)
    for owner in range(count):
        directory = root if owner == count - 1 else root / "packages" / f"pkg-{owner:05d}"
        directory.mkdir(parents=True, exist_ok=True)
        dependencies = package_dependencies(owner, count, sources, per_file)
        manifest = package_manifest(owner, count, sources, per_file, dependencies)
        (directory / "package.kira").write_text(manifest)
        metrics["manifest_bytes"] += len(manifest.encode())
        metrics["dependency_edges"] += len(dependencies)
        metrics["cyclic_dependency_edges"] += int(count > 1 and (owner + 1) % count in dependencies)
        for target in range(min(COMMON_PACKAGES, count)):
            if target != owner and target in dependencies:
                common_importers[target] += 1
        first = owner * sources // count
        after = (owner + 1) * sources // count
        for source in range(first, after):
            imports = source_imports(source, owner, count, sources, per_file)
            text, body_bytes = source_text(source, owner, count, sources, per_file, imports)
            destination = directory / "app" / f"Source{source:05d}.kira"
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text)
            metrics["source_bytes"] += len(text.encode())
            metrics["function_body_bytes"] += body_bytes
            metrics["dependency_imports"] += len(imports)
            for function in range(source * per_file, (source + 1) * per_file):
                metrics["cross_package_calls"] += sum(
                    function_package(target, count, sources, per_file) != owner
                    for target in function_targets(function, total)
                )
    metrics["common_dependency_imports"] = sum(common_importers)
    metrics["minimum_common_dependency_importers"] = min(common_importers, default=0)
    if count > 1:
        if metrics["minimum_common_dependency_importers"] < (count - 1) * 0.95:
            raise RuntimeError("shared packages are no longer imported by nearly every package")
        if metrics["cyclic_dependency_edges"] != count:
            raise RuntimeError("generated package dependencies no longer contain the package cycle")
        if metrics["cross_package_calls"] == 0:
            raise RuntimeError("generated functions no longer call across package boundaries")
    tests = test_source(total)
    test_path = root / "tests" / "PackageScaling.kira"
    test_path.parent.mkdir(parents=True, exist_ok=True)
    test_path.write_text(tests)
    metrics["source_bytes"] += len(tests.encode())
    metrics["functions"] = total
    metrics["source_files"] = sources
    metrics["packages"] = count
    return metrics


def parse_time(text: str, name: str) -> float | None:
    match = re.search(rf"([0-9.]+)\s+{re.escape(name)}\b", text)
    return float(match.group(1)) if match else None


def parse_count(text: str, name: str) -> int | None:
    match = re.search(rf"([0-9]+)\s+{re.escape(name)}\b", text)
    return int(match.group(1)) if match else None


def measure(
    kira: Path,
    root: Path,
    entry: Path,
    cache: Path | None,
    output: Path | None,
    phase: str,
    environment: dict[str, str],
    allow_noop: bool = False,
) -> dict[str, object]:
    command = ["/usr/bin/time", "-l", str(kira), phase, str(entry)]
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        command.extend(["--emit", "bin", "-o", str(output)])
    command.append("--timings")
    env = environment.copy()
    env["KLF_CACHE"] = str(cache) if cache is not None else ""
    started = time.perf_counter()
    result = subprocess.run(command, cwd=root, env=env, text=True, capture_output=True)
    wall_ms = (time.perf_counter() - started) * 1_000
    transcript = result.stdout + "\n" + result.stderr
    if result.returncode:
        raise RuntimeError(f"kira {phase} failed in {root}:\n{transcript[-6000:]}")
    phase_lines = re.findall(r"^\s*([0-9.]+)ms\s+(parse|elaborate|lower|link|verify|merge|units)\b", transcript, re.MULTILINE)
    graph = re.search(r"(?:compilation|incremental) graph units=([0-9]+) phase_runners=([0-9]+)", transcript)
    if not graph and allow_noop and "program cache validation" in transcript:
        graph_units = 0
        phase_runners = None
    elif graph:
        graph_units = int(graph.group(1))
        phase_runners = int(graph.group(2))
    else:
        # Some active Kira builds report per-stage timings but not scheduler
        # counters. Each parse timing represents one input compilation unit;
        # a units-only cache hit still represents the single request graph.
        graph_units = sum(stage == "parse" for _, stage in phase_lines)
        if graph_units == 0 and any(stage == "units" for _, stage in phase_lines):
            graph_units = 1
        phase_runners = None
    validation = re.search(
        r"program cache validation paths=([0-9]+) files=([0-9]+) directories=([0-9]+) "
        r"app_directories=([0-9]+) tests_directories=([0-9]+) package_directories=([0-9]+) "
        r"other_directories=([0-9]+) content_reads=([0-9]+) content_hashes=([0-9]+) directory_lists=([0-9]+)",
        transcript,
    )
    query_validation = re.search(
        r"query cache validation paths=([0-9]+) files=([0-9]+) directories=([0-9]+) "
        r"content_reads=([0-9]+) content_hashes=([0-9]+) directory_lists=([0-9]+) contract_reads=([0-9]+)",
        transcript,
    )
    if validation:
        validation_counts = [int(value) for value in validation.groups()]
        contract_reads = 0
    elif query_validation:
        paths, files, directories, reads, hashes, lists, contract_reads = (
            int(value) for value in query_validation.groups()
        )
        validation_counts = [paths, files, directories, None, None, None, None, reads, hashes, lists]
    else:
        # Do not report missing instrumentation as zero filesystem work.
        validation_counts = [None] * 10
        contract_reads = None
    cache_validation = re.search(r"([0-9.]+)ms\s+(?:program|query) cache validation\b", transcript)
    build_cache_hit = re.search(r"([0-9.]+)ms\s+build cache hit\b", transcript)
    stage_ms = {
        name: sum(float(duration) for duration, stage in phase_lines if stage == name)
        for name in ("units", "parse", "elaborate", "lower", "verify", "merge", "link")
    }
    return {
        "compilation_graph_units": graph_units,
        "phase_runners": phase_runners,
        "wall_ms": wall_ms,
        "user_s": parse_time(result.stderr, "user"),
        "system_s": parse_time(result.stderr, "sys"),
        "max_rss_bytes": parse_count(result.stderr, "maximum resident set size"),
        "block_input_operations": parse_count(result.stderr, "block input operations"),
        "block_output_operations": parse_count(result.stderr, "block output operations"),
        "filesystem_validation_paths": validation_counts[0],
        "filesystem_validation_files": validation_counts[1],
        "filesystem_validation_directories": validation_counts[2],
        "filesystem_validation_app_directories": validation_counts[3],
        "filesystem_validation_tests_directories": validation_counts[4],
        "filesystem_validation_package_directories": validation_counts[5],
        "filesystem_validation_other_directories": validation_counts[6],
        "filesystem_content_reads": validation_counts[7],
        "filesystem_content_hashes": validation_counts[8],
        "filesystem_directory_lists": validation_counts[9],
        "filesystem_validation_contract_reads": contract_reads,
        "cache_validation_ms": float(cache_validation.group(1)) if cache_validation else None,
        "build_cache_hit_ms": float(build_cache_hit.group(1)) if build_cache_hit else None,
        "parse_runs": sum(name == "parse" for _, name in phase_lines),
        "elaborate_runs": sum(name == "elaborate" for _, name in phase_lines),
        "lower_runs": sum(name == "lower" for _, name in phase_lines),
        "link_runs": sum(name == "link" for _, name in phase_lines),
        **{f"{name}_ms": duration for name, duration in stage_ms.items()},
    }


def summarize(samples: list[dict[str, object]]) -> dict[str, object]:
    result = dict(samples[0])
    counts = {"max_rss_bytes", "block_input_operations", "block_output_operations", "parse_runs", "elaborate_runs", "lower_runs", "link_runs", "compilation_graph_units", "phase_runners"}
    for key in result:
        values = [sample[key] for sample in samples]
        present = [value for value in values if isinstance(value, (int, float))]
        if not present:
            continue
        result[key] = max(present) if key in counts else statistics.median(present)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kira", required=True, type=Path, help="active Kira compiler built from languages/klf-kira")
    parser.add_argument("--klf-home", type=Path)
    parser.add_argument("--counts", default=",".join(map(str, DEFAULT_COUNTS)))
    parser.add_argument("--source-files", type=int, default=10_000)
    parser.add_argument("--functions-per-file", type=int, default=1)
    parser.add_argument("--cold-samples", type=int, default=2)
    parser.add_argument("--warm-samples", type=int, default=2)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    kira = args.kira.expanduser().resolve()
    if not kira.is_file():
        parser.error(f"active Kira compiler does not exist: {kira}")
    counts = [int(value) for value in args.counts.split(",") if value]
    if not counts or min(counts) < 1 or max(counts) > args.source_files:
        parser.error("each package count must be between 1 and --source-files")
    if args.cold_samples < 1 or args.warm_samples < 1:
        parser.error("sample counts must be positive")
    run_id = f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    workspace = (
        args.work_dir.expanduser().resolve()
        if args.work_dir
        else Path(__file__).resolve().parents[1] / "target" / "package-scaling-runs" / run_id
    )
    if workspace.exists() and any(workspace.iterdir()):
        parser.error(f"refusing to overwrite benchmark workspace: {workspace}")
    workspace.mkdir(parents=True, exist_ok=True)
    output_csv = (
        args.output.expanduser().resolve()
        if args.output
        else workspace / f"package-scaling-{run_id}.csv"
    )
    if output_csv.exists():
        parser.error(f"refusing to overwrite benchmark output: {output_csv}")
    environment = os.environ.copy()
    environment.setdefault("KLF_USE_SYSTEM_LINKER", "1")
    if args.klf_home:
        environment["KLF_HOME"] = str(args.klf_home.expanduser().resolve())
    temporary = workspace / "tmp"
    temporary.mkdir(parents=True, exist_ok=True)
    environment["TMPDIR"] = str(temporary)
    rows: list[dict[str, object]] = []
    headers = ["packages", "source_files", "functions", "dependency_edges", "dependency_imports", "common_dependency_imports", "minimum_common_dependency_importers", "cyclic_dependency_edges", "cross_package_calls", "source_bytes", "function_body_bytes", "manifest_bytes", "phase", "samples", "wall_ms", "wall_overhead_ms", "wall_overhead_pct", "user_s", "system_s", "cpu_overhead_s", "max_rss_bytes", "peak_rss_overhead_bytes", "block_input_operations", "block_output_operations", "block_io_overhead_operations", "filesystem_validation_paths", "filesystem_validation_files", "filesystem_validation_directories", "filesystem_validation_app_directories", "filesystem_validation_tests_directories", "filesystem_validation_package_directories", "filesystem_validation_other_directories", "filesystem_content_reads", "filesystem_content_hashes", "filesystem_directory_lists", "filesystem_validation_contract_reads", "cache_validation_ms", "build_cache_hit_ms", "compilation_graph_units", "phase_runners", "parse_runs", "elaborate_runs", "lower_runs", "link_runs", "units_ms", "parse_ms", "elaborate_ms", "lower_ms", "verify_ms", "merge_ms", "link_ms"]
    output_csv.parent.mkdir(parents=True, exist_ok=True)

    def record(row: dict[str, object]) -> None:
        rows.append(row)
        baseline = next(
            (prior for prior in rows[:-1] if prior["packages"] == counts[0] and prior["phase"] == row["phase"]),
            row,
        )
        baseline_cpu = (baseline["user_s"] or 0) + (baseline["system_s"] or 0)
        row_cpu = (row["user_s"] or 0) + (row["system_s"] or 0)
        baseline_io = (baseline["block_input_operations"] or 0) + (baseline["block_output_operations"] or 0)
        row_io = (row["block_input_operations"] or 0) + (row["block_output_operations"] or 0)
        wall_overhead = row["wall_ms"] - baseline["wall_ms"]
        row["wall_overhead_ms"] = wall_overhead
        row["wall_overhead_pct"] = wall_overhead * 100 / baseline["wall_ms"] if baseline["wall_ms"] else 0
        row["cpu_overhead_s"] = row_cpu - baseline_cpu
        row["peak_rss_overhead_bytes"] = row["max_rss_bytes"] - baseline["max_rss_bytes"]
        row["block_io_overhead_operations"] = row_io - baseline_io
        with output_csv.open("w", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

    canonical_bodies: int | None = None
    for count in counts:
        project = workspace / f"packages-{count:05d}"
        metrics = write_project(project, count, args.source_files, args.functions_per_file)
        entry = project / "app"
        if canonical_bodies is None:
            canonical_bodies = metrics["function_body_bytes"]
        elif metrics["function_body_bytes"] != canonical_bodies:
            raise RuntimeError("package layout changed the generated function bodies")
        cache_root = workspace / "cache" / f"{count:05d}"
        shared_cache = cache_root / "shared"
        output = workspace / "outputs" / f"{count:05d}" / "program"

        checks = [measure(kira, project, entry, None, None, "check", environment) for _ in range(args.cold_samples)]
        record({**metrics, "phase": "check-cold", "samples": args.cold_samples, **summarize(checks)})
        measure(kira, project, entry, shared_cache, None, "check", environment)
        warm_checks = [measure(kira, project, entry, shared_cache, None, "check", environment) for _ in range(args.warm_samples)]
        record({**metrics, "phase": "check-warm", "samples": args.warm_samples, **summarize(warm_checks)})

        tests = [measure(kira, project, entry, None, None, "test", environment) for _ in range(args.cold_samples)]
        record({**metrics, "phase": "test-cold", "samples": args.cold_samples, **summarize(tests)})
        # A warm test can reuse its already-built test executable without
        # entering the compilation graph at all.
        warm_tests = [measure(kira, project, entry, shared_cache, None, "test", environment, True) for _ in range(args.warm_samples)]
        record({**metrics, "phase": "test-warm", "samples": args.warm_samples, **summarize(warm_tests)})

        cold_builds = [measure(kira, project, entry, None, output.with_name(f"program-{sample}"), "build", environment) for sample in range(args.cold_samples)]
        record({**metrics, "phase": "build-cold", "samples": args.cold_samples, **summarize(cold_builds)})
        warm_outputs = [output.with_name(f"program-warm-{sample}") for sample in range(args.warm_samples)]
        warm_builds = [measure(kira, project, entry, shared_cache, warm_output, "build", environment, True) for warm_output in warm_outputs]
        record({**metrics, "phase": "build-warm", "samples": args.warm_samples, **summarize(warm_builds)})
        edited = project / "app" / f"Source{args.source_files - 1:05d}.kira"
        original = edited.read_text()
        changed = original.replace("depth * 3 + 11", "depth * 3 + 12", 1)
        if changed == original:
            raise RuntimeError(f"no function body to edit in {edited}")
        edited.write_text(changed)
        incremental = measure(kira, project, entry, shared_cache, warm_outputs[-1], "build", environment)
        edited.write_text(original)
        record({**metrics, "phase": "build-incremental", "samples": 1, **incremental})
        settled = measure(kira, project, entry, shared_cache, warm_outputs[-1], "build", environment, True)
        record({**metrics, "phase": "build-restore", "samples": 1, **settled})
        noops = [measure(kira, project, entry, shared_cache, warm_outputs[-1], "build", environment, True) for _ in range(args.warm_samples)]
        record({**metrics, "phase": "build-noop-restored", "samples": args.warm_samples, **summarize(noops)})
        print(f"measured {count} packages: {metrics['functions']} functions, {metrics['dependency_edges']} dependency edges", flush=True)

    for row in rows:
        if row["phase"] == "build-noop-restored" and row["compilation_graph_units"] != 0:
            raise RuntimeError(f"{row['phase']} ran {row['compilation_graph_units']} compilation graph units for {row['packages']} packages")
        if row["phase"] == "test-warm" and row["compilation_graph_units"] not in (0, 1):
            raise RuntimeError(f"warm test ran {row['compilation_graph_units']} compilation graph units for {row['packages']} packages")
        if row["phase"] not in ("build-warm", "build-restore", "build-noop-restored", "test-warm") and row["compilation_graph_units"] != 1:
            raise RuntimeError(f"package graph created {row['compilation_graph_units']} units for {row['packages']} packages during {row['phase']}, expected 1")
    phase_keys = ("compilation_graph_units", "phase_runners", "parse_runs", "elaborate_runs", "lower_runs", "link_runs")
    measured_phases = (
        "check-cold", "check-warm", "test-cold", "test-warm",
        "build-cold", "build-warm", "build-restore", "build-noop-restored", "build-incremental",
    )
    for phase in measured_phases:
        baseline = next(row for row in rows if row["packages"] == counts[0] and row["phase"] == phase)
        for row in rows:
            if row["phase"] != phase:
                continue
            for key in phase_keys:
                if row[key] != baseline[key]:
                    raise RuntimeError(f"package count added {key} work for {phase}: {baseline[key]} -> {row[key]} at {row['packages']} packages")
            baseline_cpu = (baseline["user_s"] or 0) + (baseline["system_s"] or 0)
            row_cpu = (row["user_s"] or 0) + (row["system_s"] or 0)
            baseline_io = (baseline["block_input_operations"] or 0) + (baseline["block_output_operations"] or 0)
            row_io = (row["block_input_operations"] or 0) + (row["block_output_operations"] or 0)
            wall_overhead = row["wall_ms"] - baseline["wall_ms"]
            row["wall_overhead_ms"] = wall_overhead
            row["wall_overhead_pct"] = wall_overhead * 100 / baseline["wall_ms"] if baseline["wall_ms"] else 0
            row["cpu_overhead_s"] = row_cpu - baseline_cpu
            row["peak_rss_overhead_bytes"] = row["max_rss_bytes"] - baseline["max_rss_bytes"]
            row["block_io_overhead_operations"] = row_io - baseline_io

    with output_csv.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {output_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
                                                                                                                                                    
