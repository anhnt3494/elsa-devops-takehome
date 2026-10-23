# AI usage

## Tools

**Claude Code** (Anthropic's terminal agent, Claude Opus model) for the whole
assignment. It read the brief and the provided package, proposed the plan, wrote
most of the code and docs, and ran everything against a real local cluster
(build, deploy, drill, troubleshooting, validation). I set direction, made the
decisions that were mine to make, and every commit, push, history rewrite and
registry deletion went through my explicit approval.

How I split the work:

| Mine | AI-assisted, then verified |
|---|---|
| Track choice (Part 5), language (Python), scope cuts | Code, manifests, scripts, docs |
| Commit identity (personal, not employer), what gets published | Diagnosis commands and their interpretation |
| Approving every commit / push / force-push / package deletion | Looking up current APIs in upstream docs and source |
| Part 7 answers drawn from my own incidents (PDB drain stalls, ExternalSecret OutOfSync in Argo CD) | Wording and trimming to the page limit |

## Prompts that moved things forward

My prompts were short and in Vietnamese; the agent did the legwork. Three
that changed the direction of the work (translated):

1. *"Read Rachel's email about the technical challenge and summarize the
   requirements."* → it pulled the brief and package, and flagged up front that
   `broken-app.yaml` and `legacy.gitlab-ci.yml` contain deliberate faults, and
   that the CI file carries AWS example keys a secret scanner would flag. That
   is why `ci/` never entered this repo.
2. *"Start planning the implementation."* → instead of a generic plan it
   checked my machine first (CPU/RAM, cgroup v2, missing `k3d`/`k6`/`gh`,
   registry reachability) and asked the three decisions that were mine:
   track, language, repo location.
3. *"Continue with Part 5."* — with the brief's warning about outdated
   Karpenter APIs in mind, the agent fetched the v1.15.0 CRDs, the disruption
   and NodeClass docs, and the AMI resolver source code before writing YAML,
   then proved the validation step works by feeding it known-stale variants.

## Where the AI was wrong or suboptimal, and how it was caught

Every item below was caught by *running* something, not by reading the output.

- **Silent failure in the toolbox Dockerfile.** First draft:
  `echo "$(curl …kubectl.sha256)  kubectl" | sha256sum -c -`. A failing `curl`
  inside `$(…)` does not trip `set -e`. A real connection reset during a build
  surfaced only as a confusing checksum mismatch. Fixed: download checksums to
  files, `pipefail`, curl retries.
- **Drill script died with no output (exit 141).** `grep … | head -1` under
  `pipefail`: `head` closes the pipe, `grep` gets SIGPIPE, `set -e` exits
  silently. Caught on the first run; replaced with a loop.
- **A Helm value that does not exist.** The Argo CD values had
  `applicationSet.enabled: false` — not a key in chart 10.x, so it was ignored
  without error. Caught because the ApplicationSet controller pod was still
  running. Removed.
- **Deployment started with 1 replica.** Omitting `replicas` (so the HPA owns
  it) meant the first rollout ran a single pod until the HPA reacted. Fixed with
  `replicas: minReplicas` plus Argo CD `ignoreDifferences` on `/spec/replicas`.
- **`yq -i` rewrote the whole values file.** The first CI bot commit showed a
  10-line diff for a one-line tag change (yq drops blank lines). Switched to a
  targeted `sed` plus a `yq` assertion.
- **A fabricated claim in my own docs.** The first draft of the Cloudflare
  README said validation had "caught the AI's first draft" using the v4 schema.
  That never happened — the draft was v5 from the start. Caught in review before
  commit, and replaced with what was actually done: deliberately running v4-style
  variants through validation.
- **Green locally, red for a reviewer.** Everything passed on my warm cluster.
  A fresh-clone run with no image cache failed `verify.sh`: one `nginx` pull hit
  a connection reset, `ImagePullBackOff` outlasted verify's 60 s window. The
  same test showed an 825 MB toolbox, 239 MB of it an `argocd` CLI no script
  used. Fixed both (wait + retry around the untouched verifier; toolbox 483 MB).

## Claims that were checked instead of trusted

- **Topology spread `nodeTaintsPolicy: Honor`.** The AI's reasoning said the
  default (`Ignore`) would leave a pod Pending when the on-demand node is
  drained. Rather than take that on faith, we patched the live Deployment to
  `Ignore`, drained the node, and saw `Pending … didn't match pod topology spread
  constraints`; with `Honor` it rescheduled to spot.
- **Karpenter API.** Read from the v1.15.0 CRDs, not memory; the validation
  script installs those CRDs and does a server-side dry run, and rejects
  `karpenter.sh/v1beta1`, `WhenUnderutilized`, and a budget without `duration`.
- **AL2023 alias picks the NVIDIA AMI.** The docs don't say so explicitly; the
  resolver source (`pkg/providers/amifamily/al2023.go`) shows it looks up the
  standard, NVIDIA and Neuron variants.
- **NetworkPolicy and probes.** Whether kubelet probes need an allow rule under
  `default-deny` was settled by the error itself: `connection refused`, not a
  timeout, on the wrong port — so probes were reaching the pod.

## Tooling used to verify AI output

`shellcheck`, `actionlint`, `helm lint`, `kubeconform`, `terraform validate`,
server-side dry runs against real CRDs, negative tests for each validator, unit
tests for the app, rendering the Mermaid diagrams to images, and a full
fresh-clone run of the Golden Rule before submitting.
