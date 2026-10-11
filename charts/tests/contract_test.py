#!/usr/bin/env python3
"""Contract tests for the umbrella charts under charts/.

For every umbrella chart (type: application) and every service shape values/<svc>.yaml it
renders the service with a minimal synthetic environment and checks the invariants every
service must keep, whatever its values:

  * exactly one Deployment, named after the service;
  * the Deployment selector matches its pod labels;
  * every Service selects those pods and targets a port the container declares;
  * the image is pinned by digest;
  * pods run as non-root, without privilege escalation, with a read-only root filesystem and
    without an auto-mounted ServiceAccount token.

It also checks that the chart refuses what must never deploy:

  * no activeApp                -> render fails (one render = one service);
  * an unknown values key       -> render fails (values.schema.json, additionalProperties);
  * an image without a digest   -> render fails.

Run from the repository root:  python3 charts/tests/contract_test.py
Requires: helm (3.8+), PyYAML.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

CHARTS = Path(__file__).resolve().parent.parent
FAKE_DIGEST = "sha256:" + "0" * 64


def helm(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["helm", *args], capture_output=True, text=True)


def env_overlay(service: str) -> dict:
    """The smallest environment file that makes a service renderable: an image."""
    return {"applications": {service: {"image": {
        "repository": f"example.invalid/contract/{service}", "tag": "test", "digest": FAKE_DIGEST}}}}


def render(chart: Path, service: str, extra: list[str], overlay: dict | None) -> subprocess.CompletedProcess:
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as handle:
        yaml.safe_dump(overlay or {}, handle)
    args = ["template", service, str(chart), "--namespace", "contract",
            "-f", str(chart / "values" / f"{service}.yaml"), "-f", handle.name, *extra]
    return helm(*args)


def subset(selector: dict, labels: dict) -> bool:
    return bool(selector) and all(labels.get(k) == v for k, v in selector.items())


def check_service(chart: Path, service: str) -> list[str]:
    errors: list[str] = []
    result = render(chart, service, ["--set", f"activeApp={service}"], env_overlay(service))
    if result.returncode != 0:
        return [f"render failed: {result.stderr.strip()}"]
    docs = [d for d in yaml.safe_load_all(result.stdout) if d]

    deployments = [d for d in docs if d["kind"] == "Deployment"]
    if len(deployments) != 1:
        return [f"expected exactly one Deployment, found {len(deployments)}"]
    deploy = deployments[0]
    if deploy["metadata"]["name"] != service:
        errors.append(f"Deployment is named {deploy['metadata']['name']!r}, expected {service!r}")

    pod = deploy["spec"]["template"]
    labels = pod["metadata"]["labels"]
    if not subset(deploy["spec"]["selector"]["matchLabels"], labels):
        errors.append("Deployment selector does not match its pod labels")

    spec = pod["spec"]
    if spec.get("automountServiceAccountToken") is not False:
        errors.append("automountServiceAccountToken must be false")
    if (spec.get("securityContext") or {}).get("runAsNonRoot") is not True:
        errors.append("pod securityContext.runAsNonRoot must be true")

    ports = set()
    for container in spec["containers"]:
        if "@sha256:" not in container["image"]:
            errors.append(f"container {container['name']}: image is not pinned by digest")
        sc = container.get("securityContext") or {}
        if sc.get("allowPrivilegeEscalation") is not False:
            errors.append(f"container {container['name']}: allowPrivilegeEscalation must be false")
        if sc.get("readOnlyRootFilesystem") is not True:
            errors.append(f"container {container['name']}: readOnlyRootFilesystem must be true")
        for port in container.get("ports", []):
            ports.update({port.get("name"), port["containerPort"]})

    for svc in (d for d in docs if d["kind"] == "Service"):
        name = svc["metadata"]["name"]
        if not subset(svc["spec"].get("selector", {}), labels):
            errors.append(f"Service {name} does not select the Deployment's pods")
        for port in svc["spec"]["ports"]:
            if port.get("targetPort", port["port"]) not in ports:
                errors.append(f"Service {name}: targetPort {port.get('targetPort')} is not declared by the container")
    return errors


def expect_failure(chart: Path, service: str, why: str, extra: list[str], overlay: dict | None, pattern: str) -> list[str]:
    """The render must fail, and for the expected reason.

    `pattern` is a case-insensitive regex, not a literal: Helm 3 and Helm 4 validate the schema
    with different JSON Schema libraries and word the same error differently
    ("Additional property replica is not allowed" vs "additional properties 'replica' not allowed").
    """
    result = render(chart, service, extra, overlay)
    if result.returncode == 0:
        return [f"{why}: render succeeded, it must fail"]
    if not re.search(pattern, result.stderr, re.IGNORECASE):
        return [f"{why}: failed, but not matching /{pattern}/: {result.stderr.strip()}"]
    return []


def main() -> int:
    umbrellas = [c.parent for c in sorted(CHARTS.glob("*/Chart.yaml"))
                 if yaml.safe_load(c.read_text()).get("type", "application") == "application"]
    if not umbrellas:
        print("no umbrella charts found", file=sys.stderr)
        return 1

    failures = 0
    for chart in umbrellas:
        build = helm("dependency", "build", str(chart))
        if build.returncode != 0:
            print(f"FAIL {chart.name}: helm dependency build: {build.stderr.strip()}")
            failures += 1
            continue
        services = sorted(p.stem for p in (chart / "values").glob("*.yaml"))
        if not services:
            print(f"FAIL {chart.name}: no values/<service>.yaml shapes")
            failures += 1
            continue
        for service in services:
            no_digest = env_overlay(service)
            del no_digest["applications"][service]["image"]["digest"]
            errors = check_service(chart, service)
            errors += expect_failure(chart, service, "no activeApp", [], env_overlay(service), "activeApp")
            errors += expect_failure(chart, service, "unknown values key",
                                     ["--set", f"activeApp={service}", "--set", f"applications.{service}.replica=2"],
                                     env_overlay(service), r"additional propert(y|ies).{0,3}replica.{0,3}(is )?not allowed")
            errors += expect_failure(chart, service, "image without digest",
                                     ["--set", f"activeApp={service}"], no_digest, "digest")
            status = "FAIL" if errors else "ok  "
            print(f"{status} {chart.name}/{service}")
            for error in errors:
                print(f"     - {error}")
            failures += bool(errors)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
