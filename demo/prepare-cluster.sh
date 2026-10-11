#!/usr/bin/env bash
set -euo pipefail

NUMAPLANE_REPO="${NUMAPLANE_REPO:-$HOME/Documents/Projects/numaplane}"
DEMO_REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="numaplane-controller:atomic-chain-rollback"

branch="$(git -C "$NUMAPLANE_REPO" branch --show-current)"
if [[ "$branch" != "feat/atomic-chain-rollback" ]]; then
  echo "Expected $NUMAPLANE_REPO on feat/atomic-chain-rollback; found '$branch'." >&2
  exit 1
fi

echo "Building Numaplane from stacked PR branch (PR #1051 + PR #1052)..."
(
  cd "$NUMAPLANE_REPO"
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o manager-linux cmd/main.go
  docker build -f Dockerfile.local -t "$IMAGE" .
)

echo "Installing CRDs from the same branch..."
# Apply only Numaplane's CRDs. The config/crd kustomization also references an old Numaflow
# minimal-CRD bundle, which must not replace the cluster's installed Numaflow CRDs.
kubectl apply -f "$NUMAPLANE_REPO/config/crd/bases"

echo "Deploying the locally built controller..."
kubectl -n numaplane-system set image deployment/numaplane-controller-manager manager="$IMAGE"
kubectl -n numaplane-system patch deployment numaplane-controller-manager --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Never"}]'
kubectl -n numaplane-system rollout restart deployment/numaplane-controller-manager
kubectl -n numaplane-system rollout status deployment/numaplane-controller-manager --timeout=180s

echo "Installing Argo CD health checks and restarting its controller..."
kubectl -n argocd patch configmap argocd-cm --type merge \
  --patch-file "$DEMO_REPO/argocd/argocd-cm-health-patch.yaml"
kubectl -n argocd rollout restart statefulset/argocd-application-controller
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=180s

echo "Resetting the demo application and namespace..."
kubectl -n argocd delete application numaplane-e2e --ignore-not-found
kubectl delete namespace numaplane-e2e --ignore-not-found --wait=true
kubectl apply -f "$DEMO_REPO/argocd/application.yaml"

cat <<'EOF'

Cluster preparation complete.

Open Argo CD, refresh numaplane-e2e, then Sync the baseline commit.
The application watches:
  https://github.com/rahulsgh21/numaplane.git
  branch: local-e2e-scenarios
  path: scenarios
EOF
