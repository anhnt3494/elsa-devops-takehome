# Part 3 — Troubleshooting log

`troubleshoot/broken-app.yaml` contained **9 independent faults** (8 symptoms; #7 is two faults), stacked so
that each one hid the next. I fixed them one at a time in a copy,
[`troubleshoot/fixed-app.yaml`](troubleshoot/fixed-app.yaml), re-applying
after each change and looking at the *next* symptom. Every change in that file
is marked `# FIX:`.

```bash
./scripts/30-troubleshoot.sh            # apply fixed-app.yaml + verify.sh -> PASS
./scripts/30-troubleshoot.sh --broken   # apply broken first, watch verify.sh FAIL, then fix
```

Constraints respected: `default-deny` is untouched (only allow rules were
added), and no node label or taint was changed — `verify.sh` checks both.

| # | Workload | Symptom | Root cause | Fix |
|---|---|---|---|---|
| 1 | web | `ContainerCreating` forever | volume references ConfigMap `web-conf`; it is `web-config` | rename reference |
| 2 | web | `ImagePullBackOff` | tag `nginx:1.25.99` does not exist | `nginx:1.25.5` |
| 3 | web | none locally / `Pending` on small machines | 16Gi memory request for nginx | 32Mi request / 64Mi limit |
| 4 | web | `Running 0/1`, restart loop | probes on 8080, nginx listens on 80 | probes → 80 |
| 5 | web-svc | connection refused once endpoints exist | `targetPort: 8080` | `targetPort: 80` |
| 6 | web-svc | Service has no endpoints | selector `app=webapp`, pods are `app=web` | selector `app=web` |
| 7 | ai-inference | `Pending` | nodeSelector `node-type` (missing `acme.io/` prefix) **and** no toleration for the GPU taint | prefixed selector + toleration |
| 8 | namespace | smoke test fails | `default-deny` blocks DNS egress, client egress, web ingress | 3 least-privilege allow policies |

---

## Triage

```console
$ kubectl apply -f troubleshoot/broken-app.yaml
$ kubectl -n troubleshoot get deploy,rs,pods,svc,endpoints,networkpolicy -o wide
deployment.apps/ai-inference   0/1   ...  busybox:1.36    app=ai-inference
deployment.apps/web            0/2   ...  nginx:1.25.99   app=web
pod/ai-inference-77cfc6f99b-nhkb5   0/1   Pending             ...  <none>
pod/web-5c8d87f7d8-bqhlp            0/1   ContainerCreating   ...  agent-3
service/web-svc   ClusterIP   10.43.212.254   80/TCP   app=webapp
endpoints/web-svc   <none>
networkpolicy.networking.k8s.io/default-deny   <none>
```

Three threads to pull: `web` never starts, `ai-inference` never schedules, and
the Service selector (`app=webapp`) already disagrees with the Deployment
selector (`app=web`). The `default-deny` policy with an empty pod selector
means that once the pods work, traffic will still be blocked.

## 1. ConfigMap name mismatch (web)

**Symptom:** pods stuck in `ContainerCreating`.

```console
$ kubectl -n troubleshoot describe pod web-5c8d87f7d8-bqhlp | sed -n '/^Events:/,$p'
  Normal   Scheduled    27s                default-scheduler  Successfully assigned troubleshoot/web-5c8d87f7d8-bqhlp to agent-3
  Warning  FailedMount  12s (x6 over 28s)  kubelet            MountVolume.SetUp failed for volume "html" : configmap "web-conf" not found
$ kubectl -n troubleshoot get configmap
web-config         1      35s
```

**Root cause:** the volume references `web-conf`; the ConfigMap in the same
file is `web-config`. Kubelet will not start a container whose volume cannot be
mounted, so this hid every container-level problem behind it.

**Fix:** `configMap.name: web-config`.

## 2. Non-existent image tag (web)

**Symptom:** after fix 1, the new pod went to `ImagePullBackOff`.

```console
$ kubectl -n troubleshoot describe pod web-d97fb6568-6nkjx | grep Failed
  Warning  Failed  ...  Failed to pull image "nginx:1.25.99": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:1.25.99": failed to resolve reference
$ curl -s 'https://hub.docker.com/v2/repositories/library/nginx/tags?page_size=100&name=1.25.' | jq -r '.results[].name' | sort -V
1.25.0 ... 1.25.5
```

**Root cause:** `1.25.99` was never published. The 1.25 line ends at 1.25.5.

**Fix:** `nginx:1.25.5` — the smallest change that keeps the version line the
author intended. In an incident I don't also do a major upgrade; 1.25 is EOL
upstream, so the upgrade belongs in a follow-up ticket, not in this hotfix.

## 3. 16Gi memory request (web)

**Symptom:** *none on my machine* — which is the interesting part. Each k3s
node is a container and reports the host's full RAM as allocatable:

```console
$ kubectl get nodes -o custom-columns=NODE:.metadata.name,ALLOC_MEM:.status.allocatable.memory
agent-1   32304924Ki
...
```

so a 16Gi request fit on my 32 GB workstation. On a 16 GB laptop (or a normal
cloud node) both replicas would be `Pending` with `Insufficient memory`. I
found it by reading the spec rather than from an event, then measured what
nginx actually uses:

```console
$ kubectl -n troubleshoot top pods
web-554d846c86-55sdk   1m   11Mi
$ kubectl -n troubleshoot exec <web-pod> -- cat /sys/fs/cgroup/memory.peak
17731584    # ~17Mi peak
```

**Fix:** request 32Mi, limit 64Mi (≈2× and ≈4× the observed peak). A fault
whose symptom depends on the machine is exactly the kind that passes in one
environment and pages someone in another.

## 4. Probes on the wrong port (web)

**Symptom:** after fix 2 the container was `Running` but `0/1` and restarting.

```console
$ kubectl -n troubleshoot describe pod web-74665f8855-sfjpn | grep -E 'Liveness|Readiness|Unhealthy|Killing'
    Liveness:     http-get http://:8080/ delay=5s timeout=1s period=5s
    Readiness:    http-get http://:8080/ delay=3s timeout=1s period=5s
  Warning  Unhealthy  Readiness probe failed: Get "http://10.42.0.15:8080/": dial tcp 10.42.0.15:8080: connect: connection refused
  Warning  Unhealthy  Liveness probe failed: Get "http://10.42.0.15:8080/": dial tcp 10.42.0.15:8080: connect: connection refused
  Normal   Killing    Container nginx failed liveness probe, will be restarted
$ kubectl -n troubleshoot exec web-74665f8855-sfjpn -- sh -c 'grep -h listen /etc/nginx/conf.d/*.conf'
    listen       80;
```

**Root cause:** the stock nginx image listens on 80 (`containerPort: 80` was
right); both probes target 8080, so liveness kills a healthy container.

**Fix:** probes → port 80.

Side finding: the error is `connection refused`, not a timeout. So the
kubelet's probes are **not** blocked by `default-deny` (kube-router, k3s's
policy engine, allows node-local traffic). No policy is needed for probes.

## 5. Service targetPort (web-svc)

**Symptom:** latent — it can only show once the Service has endpoints (fault 6);
it would surface as `connection refused` on the ClusterIP.

**Root cause:** `targetPort: 8080`; the same wrong port as fault 4. I fixed it
in the same pass once `grep listen` had shown the real port, instead of waiting
for it to fail separately.

**Fix:** `targetPort: 80`. (In my own chart I use a named port, `targetPort:
http`, which makes faults 4 and 5 impossible to introduce independently.)

## 6. Service selector (web-svc)

**Symptom:** `web` pods `1/1 Ready`, but the Service has no endpoints.

```console
$ kubectl -n troubleshoot get endpointslices -l kubernetes.io/service-name=web-svc
web-svc-zldfb   IPv4   <unset>   <unset>
$ kubectl -n troubleshoot get svc web-svc -o jsonpath='{.spec.selector}'
{"app":"webapp"}
$ kubectl -n troubleshoot get pods -l app=web --show-labels
web-554d846c86-55sdk   ...   app=web,pod-template-hash=554d846c86
$ kubectl -n troubleshoot get pods -l app=webapp
No resources found in troubleshoot namespace.
```

**Fix:** selector `app: web`. Endpoints appeared immediately:
`10.42.4.10,10.42.2.9`.

## 7. ai-inference cannot schedule

**Symptom:** `Pending` from the start.

```console
$ kubectl -n troubleshoot describe pod -l app=ai-inference | sed -n '/^Events:/,$p'
  Warning  FailedScheduling  default-scheduler  0/5 nodes are available: 1 node(s) had untolerated taint(s), 4 node(s) didn't match Pod's node affinity/selector.
$ kubectl get node -l acme.io/node-type=gpu -o jsonpath='{.items[0].metadata.name} {.items[0].spec.taints}'
agent-4 [{"effect":"NoSchedule","key":"nvidia.com/gpu","value":"true"}]
$ kubectl get nodes -l node-type=gpu
No resources found
```

**Root cause — two separate faults:**
1. `nodeSelector: node-type: gpu` matches no node; the label is
   `acme.io/node-type=gpu`.
2. The GPU node is tainted `nvidia.com/gpu=true:NoSchedule` and the pod has no
   toleration.

Fixing only one is not enough: a toleration *allows* the pod onto the tainted
node but does not *attract* it there, and a correct selector alone is repelled
by the taint. The scheduler message lists both reasons ("untolerated taint" for
agent-4, "didn't match selector" for the other four).

**Fix:** `nodeSelector: {acme.io/node-type: gpu}` plus a toleration for
`nvidia.com/gpu=true:NoSchedule`. The pod landed on `agent-4`. The node was not
touched.

## 8. NetworkPolicy: default-deny with no allow rules

**Symptom:** everything Ready, but `verify.sh` step 7 fails:

```console
[7/7] In-cluster smoke test through the Service...
curl: (7) Failed to connect to web-svc.troubleshoot.svc.cluster.local port 80 after 1 ms: Couldn't connect to server
FAIL: smoke test failed (check NetworkPolicy/DNS/Service path)
```

The smoke Job's pods are labeled `app=smoke-client`. To separate DNS from TCP,
I ran a debug pod with the same label:

```console
$ kubectl -n troubleshoot run netdebug --image=curlimages/curl:8.7.1 \
    --labels=app=smoke-client --restart=Never --command -- sleep 300
$ kubectl -n troubleshoot exec netdebug -- nslookup -timeout=3 web-svc.troubleshoot.svc.cluster.local
nslookup: write to '10.43.0.10': Connection refused          # DNS egress blocked
$ kubectl -n troubleshoot exec netdebug -- curl -sS -m 5 http://10.43.212.254
curl: (7) Failed to connect to 10.43.212.254 port 80 after 0 ms   # TCP blocked even without DNS
$ kubectl -n default run nettest --rm -i --image=curlimages/curl:8.7.1 --restart=Never -- \
    curl -sS -m 5 http://web-svc.troubleshoot.svc.cluster.local
curl: (7) Failed to connect ... after 1 ms                   # resolves, but web refuses ingress
```

**Root cause:** `default-deny` selects every pod for both Ingress and Egress,
and nothing allows (a) the client to reach cluster DNS, (b) the client to reach
`web`, (c) `web` to accept the client. kube-router *rejects* (ICMP) rather than
drops, so every failure is instant "connection refused" — which made a DNS
failure look like a TCP failure in the Job output. Splitting the path with the
debug pod is what made the three separate blocks visible.

**Fix:** keep `default-deny`, add three narrow policies:

| Policy | Selects | Allows |
|---|---|---|
| `allow-smoke-client-dns` | `app=smoke-client` | egress to `kube-system/k8s-app=kube-dns`, 53/UDP+TCP |
| `allow-smoke-client-to-web` | `app=smoke-client` | egress to `app=web`, 80/TCP |
| `allow-web-from-smoke-client` | `app=web` | ingress from `app=smoke-client`, 80/TCP |

Ports are the **pod** port (80): policies are evaluated after the Service DNAT.
DNS is scoped to the client only, because nothing else in the namespace
resolves names (web only serves; ai-inference makes no calls).

Checked both directions:

```console
$ kubectl -n troubleshoot exec netdebug -- curl -sS http://web-svc.troubleshoot.svc.cluster.local
<html><body><h1>TROUBLESHOOT-OK</h1></body></html>
$ kubectl -n default run nettest2 --rm -i ... curl -sS -m 5 http://web-svc.troubleshoot.svc.cluster.local
curl: (7) Failed to connect ...                              # other namespaces still denied
$ sh troubleshoot/verify.sh
...
PASS
```

## What I would add so these don't reach a cluster again

- **Named ports** (`containerPort` named `http`, probes and `targetPort` by
  name) — removes faults 4 and 5 as a class.
- **CI checks on manifests:** kubeconform for schema, a check that every image
  tag resolves in its registry (fault 2), and a policy (Kyverno/OPA) that
  rejects memory requests above a namespace budget (fault 3) and Services whose
  selector matches no workload in the same chart (fault 6).
- **Network policies tested like code:** a small job per allowed and denied
  flow (as above) run on every change, rather than finding out from a smoke
  test.
