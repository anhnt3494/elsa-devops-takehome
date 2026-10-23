# Part 5b — Cloudflare DNS + cache rules (validate-only)

Provider **cloudflare/cloudflare 5.28.1** (v5 schema, locked with checksums for
linux/darwin × amd64/arm64 in `.terraform.lock.hcl`).
`./scripts/50-validate-tf.sh` runs `fmt -check`, `init -backend=false
-lockfile=readonly` and `validate` in the toolbox — no credentials, no API
calls.

| File | What |
|---|---|
| `dns.tf` | `quote-api.example.com`, proxied CNAME to the origin (TTL automatic) |
| `cache-rules.tf` | zone entrypoint ruleset for `http_request_cache_settings`: static assets cached (edge 30d, browser 1d), `/api/*` bypassed |
| `imports.tf` | `import` block adopting the hand-made `status.example.com` record |
| `versions.tf` / `providers.tf` | pinned provider, partial S3 backend, token from `CLOUDFLARE_API_TOKEN` |

## Decisions

- **v5, not v4.** v5 renamed `cloudflare_record` → `cloudflare_dns_record` and
  turned nested blocks into attributes (`rules = [{ … }]`). I wrote against the
  5.28.1 docs, then fed v4-style variants through the same validation to make
  sure it would catch them: `cloudflare_record` fails with `Invalid resource
  type`, a `rules { }` block with `Argument or block definition required`.
- **Rule order matters.** Every matching cache rule applies and later rules win,
  so the `/api/` bypass comes **after** the static-asset rule: a path like
  `/api/export.js` matches both and must end up uncached.
- **Edge TTL long, browser TTL short.** Edge cache can be purged on deploy;
  browser cache cannot. Raise `static_browser_ttl_seconds` only for
  fingerprinted asset names.
- **One ruleset per phase.** A zone has a single entrypoint ruleset for
  `http_request_cache_settings`. If someone already created cache rules in the
  dashboard, that ruleset must be imported too (`<zone_id>/<ruleset_id>` style
  ID), not created alongside.

## Adopting a manually created record

1. Find the record ID (dashboard or `GET /zones/{zone_id}/dns_records?name=status.example.com`).
2. Pass it as `status_record_id`; the `import` block does the rest — no
   `terraform import` command, and the adoption is reviewed in the MR plan like
   any other change.
3. If the current settings are unknown, `terraform plan
   -generate-config-out=generated.tf` writes them out; copy them into the
   resource.
4. The plan must read **1 to import, 0 to change**. Any diff means the resource
   block does not match reality yet — fix the code, not the record.
