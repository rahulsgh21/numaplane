#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLLER="$ROOT/scenarios/numaflowcontrollerrollout.yaml"
PIPELINE="$ROOT/scenarios/pipelinerollout.yaml"

case "${1:-}" in
  baseline)
    version="1.7.5"
    pipeline_image="quay.io/numaio/numaflow-go/map-cat:stable"
    ;;
  happy)
    version="1.8.3"
    pipeline_image="quay.io/numaio/numaflow-go/map-cat:stable"
    ;;
  failure)
    version="1.6.0"
    # Deterministic stand-in for a Pipeline workload that cannot run under the trial controller.
    pipeline_image="quay.io/numaio/numaflow-go/map-cat:does-not-exist"
    ;;
  recovery)
    version="1.8.3"
    pipeline_image="quay.io/numaio/numaflow-go/map-cat:stable"
    ;;
  *)
    echo "usage: $0 {baseline|happy|failure|recovery}" >&2
    exit 2
    ;;
esac

python3 - "$CONTROLLER" "$PIPELINE" "$version" "$pipeline_image" <<'PY'
from pathlib import Path
import re
import sys

controller_path, pipeline_path, version, pipeline_image = sys.argv[1:]

controller = Path(controller_path)
text = controller.read_text()
text, count = re.subn(r'(version:\s*)"[0-9.]+"', rf'\g<1>"{version}"', text, count=1)
if count != 1:
    raise SystemExit(f"could not update controller version in {controller}")
controller.write_text(text)

pipeline = Path(pipeline_path)
text = pipeline.read_text()
text, count = re.subn(
    r'image:\s*quay\.io/numaio/numaflow-go/map-cat:[^\s]+',
    f'image: {pipeline_image}',
    text,
    count=1,
)
if count != 1:
    raise SystemExit(f"could not update Pipeline image in {pipeline}")
pipeline.write_text(text)
PY

echo "Prepared '$1' stage:"
echo "  controller version: $version"
echo "  Pipeline image:     $pipeline_image"
echo
echo "Review and publish this stage:"
echo "  git diff -- scenarios/"
echo "  git add scenarios/"
echo "  git commit -m \"demo: $1 progressive controller rollout\""
echo "  git push fork local-e2e-scenarios"
