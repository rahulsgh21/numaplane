#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-numaplane-e2e}"

watch -n 2 \
  "kubectl -n '$namespace' get \
numaflowcontrollerrollouts,isbservicerollouts,pipelinerollouts,monovertexrollouts,\
numaflowcontrollers,interstepbufferservices,pipelines,monovertices \
-L numaplane.numaproj.io/upgrade-state,\
numaplane.numaproj.io/progressive-result-state,\
numaplane.numaproj.io/controller-instance-id"
