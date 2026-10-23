# Part 7 — Ops answers

## 1. EKS 1.33 → 1.35 with zero downtime

The control plane moves one minor at a time and never downgrades: two hops.
Kubelets may lag the API server by three minors (since 1.28), so nodes stay on
1.33 during both hops and roll **once**.

1. **Prepare, dev → stag → prod:** EKS Upgrade Insights and `kubent`/`pluto`
   (manifests *and* Helm releases) for removed APIs; compatibility matrices of
   every controller (Karpenter, LB controller, cert-manager, ESO); PDB audit.
2. **Control plane → 1.34**, then add-ons: **vpc-cni** first (one minor at a
   time), **kube-proxy**, **CoreDNS**, **EBS/EFS CSI**. Smoke-test DNS, pod
   networking, volume attach.
3. **Control plane → 1.35**, add-ons again, same checks.
4. **Nodes once:** bump the pinned AMI in the EC2NodeClass (Karpenter drift,
   within disruption budgets); roll managed node groups with surge; canary one
   pool first.

**Top 3 risks**
1. **Removed APIs / incompatible controllers** after an irreversible step →
   Insights, matrices and a staging soak before each hop.
2. **Drains that stall or cause outages:** `minAvailable: 1` on a one-replica
   service blocks drain forever; no PDB lets all replicas go at once → PDB
   audit, ≥2 replicas with spread, surge capacity.
3. **Networking add-on regressions** are cluster-wide → upgrade add-ons
   separately from the control plane and keep the previous version ready to
   roll back (add-ons can be rolled back, the control plane cannot).

## 2. Spot reclaims paging at 3 AM

Page on **impact**; a spot node disappearing is designed behavior.

- **Fix the source:** Karpenter's interruption queue (SQS + EventBridge). On
  the 2-minute notice it taints, drains and deletes the Node before EC2
  terminates it, so most reclaims never become an unreachable node.
- **Exclude only intentional disruption:**
  ```promql
  kube_node_status_condition{condition="Ready",status!="true"} == 1
    unless on(node) kube_node_spec_taint{key="karpenter.sh/disrupted"}
  ```
  `for: 10m`. A reclaim deletes the node within minutes; a real failure stays
  NotReady without the taint and still pages. Spot pools → warning channel;
  on-demand/system nodes page sooner.
- **Page on symptoms:** SLO burn rate, Deployments below desired replicas
  >10m, pods Pending >10m (replacement capacity cannot launch — the real 3 AM
  problem), and >20% of a NodePool lost in 15m (a capacity event).
- **Alertmanager:** `group_by: [cluster, nodepool]`; inhibit node alerts while
  a `SpotInterruption` alert is active for the same node. Review interruption
  rates weekly — high rates call for more instance diversity, not muting.

## 3. Cloudflare in front, mobile LCP 5s

1. **Is it TTFB?** CrUX/WebPageTest on mobile. Low TTFB means caching is not
   the cause — look at the LCP element (hero image, blocking JS/CSS, fonts).
2. **Headers, mobile UA, repeated:**
   `curl -sI -A '<mobile UA>' https://site/ | grep -iE 'cf-cache-status|age|cache-control|set-cookie|vary'`.
   `DYNAMIC` = HTML never eligible (Cloudflare does not cache HTML by
   default); `MISS` every time = key or TTL defeats it; `BYPASS` = a rule or
   cookie.
3. **Rules:** a Cache Rule must make HTML *eligible for cache* with an edge
   TTL. Check order (later rules override), conflicting legacy Page Rules,
   bypass-on-cookie, and the cache key: `utm_*` query strings, `Vary:
   User-Agent` or device-type keys fragmenting it.
4. **Origin, bypassing Cloudflare** (`curl --resolve site:443:<origin-ip>`):
   `private/no-store` or a `Set-Cookie` on every anonymous page blocks caching.
   Send `public, s-maxage=…` without cookies for anonymous pages, or override
   edge TTL and bypass only when a login cookie is present.
5. **Verify:** `HIT` with growing `Age`, HTML hit ratio in Analytics, re-measure
   LCP; purge HTML on deploy.

## 4. Application secrets on EKS

| | External Secrets Operator + Secrets Manager | Secrets Store CSI Driver (ASCP) |
|---|---|---|
| Model | controller syncs SM values into K8s Secrets | pod mounts secrets as files |
| Env vars | yes | only via optional sync |
| Rotation | `refreshInterval` + Reloader | remount; app must re-read |
| Weak spots | value in etcd; one more controller | pod start depends on SM; per-app boilerplate |

**Pick: ESO + AWS Secrets Manager.** One `ClusterSecretStore` per cluster via
Pod Identity, IAM scoped by path (`/<env>/<service>/*`), so the same
`ExternalSecret` manifests in Git resolve to each cluster's environment.
Nothing secret in Git, central rotation, CloudTrail on every read. Offset the
weak spots with KMS envelope encryption, tight Secret RBAC and 2 ESO replicas.
With Argo CD, `ExternalSecret` needs `ignoreDifferences` for CRD-defaulted
fields, or it shows OutOfSync forever.
