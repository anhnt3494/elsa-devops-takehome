# Part 5a — Karpenter for GPU inference

Target: **Karpenter v1.15.0**, APIs `karpenter.sh/v1` and `karpenter.k8s.aws/v1`
(the only versions the v1.15 CRDs serve). Verified against the v1.15.0 CRDs
and docs, not from memory — `./scripts/55-validate-karpenter.sh` installs those
CRDs into the local cluster and runs a server-side dry run, so schema **and**
CEL rules are enforced. The same check rejects the usual stale-API mistakes:

```text
karpenter.sh/v1beta1            -> no matches for kind "NodePool" in version "karpenter.sh/v1beta1"
consolidationPolicy: WhenUnderutilized
                                -> Unsupported value: supported values: "WhenEmpty", "WhenEmptyOrUnderutilized", "Balanced"
budget schedule without duration -> 'schedule' must be set with 'duration'
```

| File | What |
|---|---|
| `ec2nodeclass-gpu.yaml` | AL2023 pinned to `v20261019` (alias resolves the NVIDIA variant), IMDSv2 hop 1, local NVMe as RAID0 for images/model cache |
| `nodepool-gpu-spot.yaml` | weight **100**, spot only, `WhenEmpty`, 16-GPU limit |
| `nodepool-gpu-on-demand.yaml` | weight **10**, on-demand fallback, 4-GPU limit, moves back to spot only in a nightly window |
| `example-inference.yaml` | the pod side: selector + toleration, GPU request, graceful termination, PDB |

## Design

**Spot preferred, on-demand fallback.** Two NodePools on one EC2NodeClass.
Karpenter evaluates pools by weight, so pending GPU pods get spot first; when
no spot offering in g5/g6/g6e across the AZs can launch, Karpenter marks those
offerings unavailable and the on-demand pool (weight 10) takes over. Separate
pools also give separate `limits`: a spot shortage can cost at most 4
on-demand GPUs, not an open-ended bill.

**Taint.** Both pools taint `nvidia.com/gpu:NoSchedule`, so only pods that
tolerate it (and request `nvidia.com/gpu`) land there. Nodes carry
`acme.io/node-type: gpu` — the same label the local cluster uses in Part 3, so
workloads select GPU nodes the same way locally and in EKS.

**Consolidation that does not cut requests.**
- `gpu-spot` uses `consolidationPolicy: WhenEmpty`: Karpenter only removes a
  node once no inference pod is left on it; it never evicts a running pod to
  repack. With single-GPU instance types (`instance-gpu-count: 1`) a node holds
  one GPU pod, so "underutilized" is effectively "empty" — `WhenEmpty` gives up
  almost no savings here. `consolidateAfter: 10m` keeps a warm node through
  short traffic dips; a GPU cold start (multi-GB image + loading weights) costs
  more than ten idle minutes.
- `gpu-on-demand` uses `WhenEmptyOrUnderutilized`, because otherwise fallback
  capacity stays on-demand forever after spot comes back. That move evicts
  pods, so a budget blocks `Underutilized` except 02:00–04:00 ICT.
- Drift (AMI/config changes) is blocked 08:00–22:00 ICT by budget on both pools.
- Forceful paths are bounded rather than blocked: `expireAfter: 720h` and
  `terminationGracePeriod: 1h`. I deliberately do **not** use
  `karpenter.sh/do-not-disrupt` on inference pods: it does not stop
  expiration, spot interruption or node repair anyway, and without a
  `terminationGracePeriod` it can block expiry forever (per the v1.15 docs).
  Pods instead get `terminationGracePeriodSeconds: 110`, a `preStop` delay,
  readiness that drops on SIGTERM, and a PDB.

**Not shown** (outside Karpenter's YAML): the interruption SQS queue +
EventBridge rules (`--interruption-queue`), the node IAM role and Pod Identity
for the controller, and the NVIDIA device plugin DaemonSet.

## Spot vs on-demand for AI inference

Spot GPUs are typically 60–70% cheaper, but the trade-off is harsher than for
CPU web services: GPU spot pools are shallow and in demand, so interruptions
and launch failures are more frequent, and the replacement cost is high — an
inference pod's cold start (pulling a 10–20 GB image and loading weights into
GPU memory) often takes several minutes, longer than the 2-minute spot notice.
A reclaim therefore removes capacity for minutes, and any request or streaming
generation longer than the notice is cut and must be retried. Spot fits
stateless, retry-safe inference with bounded request time, diversified across
instance families and AZs, with some headroom so one reclaim does not breach
latency SLOs. Latency-critical or long-session traffic should keep a baseline on
on-demand (ideally covered by Savings Plans or a capacity reservation, which
this EC2NodeClass could target via `capacityReservationSelectorTerms`) and use
spot for burst. This design is spot-first with a capped on-demand fallback; for
a strict SLO I would add a fixed on-demand baseline deployment on top.
