# Progressive NumaflowController rollout demo

This demo runs the code from the stacked Numaplane pull requests:

- [#1051 — resource-chain assessment](https://github.com/numaproj/numaplane/pull/1051)
- [#1052 — atomic chain rollback and update gating](https://github.com/numaproj/numaplane/pull/1052)

PR #1052 is based on PR #1051, so building `feat/atomic-chain-rollback` includes both.
Argo CD watches `rahulsgh21/numaplane`, branch `local-e2e-scenarios`, path `scenarios`.

## One-time preparation

Prepare and publish the clean baseline:

```bash
cd ~/numaplane-local-e2e
chmod +x demo/*.sh
./demo/set-stage.sh baseline
git add scenarios/ demo/ argocd/
git commit -m "demo: prepare atomic controller-chain rollout"
git push fork local-e2e-scenarios
```

Build the stacked PR branch, install its CRDs, reset the demo namespace, and recreate the Argo CD application:

```bash
cd ~/numaplane-local-e2e
./demo/prepare-cluster.sh
```

In Argo CD, hard-refresh and sync `numaplane-e2e`. Wait until all four Rollouts and their
promoted children are Healthy. The baseline controller version is `1.7.5`.

Keep a terminal watcher available during recording:

```bash
cd ~/numaplane-local-e2e
./demo/watch.sh
```

## Recording sequence

### 1. Establish the baseline

Show the Argo CD resource tree:

- NumaflowControllerRollout `numaflow-controller` at `1.7.5`
- ISBServiceRollout `my-isbsvc`
- PipelineRollout `my-pipeline`
- MonoVertexRollout `my-monovertex`
- one promoted child for each Rollout

Explain that the Pipeline and MonoVertex are workloads bound to the promoted controller instance.

### 2. Happy-path controller upgrade

Publish the next desired state:

```bash
cd ~/numaplane-local-e2e
./demo/set-stage.sh happy
git add scenarios/
git commit -m "demo: upgrade controller from 1.7.5 to 1.8.3"
git push fork local-e2e-scenarios
```

In Argo CD:

1. Refresh the application.
2. Show that only the NumaflowControllerRollout is initially OutOfSync.
3. Sync the application.
4. Expand the resource tree.

Point out the new trial controller and the trial ISBService, Pipeline, and MonoVertex on its
controller instance. The controller remains trial until every member's resource assessment succeeds.
After all members are healthy, the complete chain is promoted and the previous chain becomes recyclable.

### 3. Failed trial and atomic rollback

Publish the deterministic failure stage:

```bash
cd ~/numaplane-local-e2e
./demo/set-stage.sh failure
git add scenarios/
git commit -m "demo: simulate pipeline incompatibility with controller 1.6.0"
git push fork local-e2e-scenarios
```

This stage changes the controller to `1.6.0` and uses an unavailable Pipeline UDF image as a
deterministic stand-in for a workload that cannot run with the trial controller. This is intentional:
Numaplane observes workload health; it does not infer compatibility from version strings.

In Argo CD:

1. Refresh and sync.
2. Show the new trial controller and dependent trial resources.
3. Expand the trial Pipeline and show that its UDF pod cannot start.
4. Wait for the Pipeline assessment window to expire.
5. Show the Pipeline failure propagating to the controller resource-chain assessment.
6. Show the entire trial chain marked failed while the previously promoted `1.8.3` chain continues serving.

The failed controller trial remains visible as the update gate. New dependent updates remain Pending until
the failed trial is resolved by reverting or force-promoting it.

### 4. Resolve the failed trial

Publish recovery:

```bash
cd ~/numaplane-local-e2e
./demo/set-stage.sh recovery
git add scenarios/
git commit -m "demo: resolve failed controller trial"
git push fork local-e2e-scenarios
```

Refresh and sync Argo CD. The desired controller once again matches the promoted `1.8.3` controller,
so the failed trial is discontinued/recycled and the healthy promoted chain remains active.

## Useful status commands

```bash
kubectl -n numaplane-e2e get numaflowcontrollerrollout numaflow-controller -o yaml
kubectl -n numaplane-e2e get pipelinerollout my-pipeline -o yaml
kubectl -n numaplane-e2e get numaflowcontrollers,isbsvc,pipelines,monovertices \
  -L numaplane.numaproj.io/upgrade-state,\
numaplane.numaproj.io/progressive-result-state,\
numaplane.numaproj.io/controller-instance-id
```
