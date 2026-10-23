locals {
  quote_api_host = cloudflare_dns_record.quote_api.name
}

# The zone's single entrypoint ruleset for the cache-settings phase. Every
# matching rule applies in order and later rules override earlier ones, so the
# /api bypass is last: a request like /api/export.csv must never be cached
# even though it also matches the static-asset rule.
resource "cloudflare_ruleset" "cache" {
  zone_id     = var.zone_id
  name        = "Cache rules"
  description = "Cache settings for quote-api.example.com. Managed by Terraform."
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "quote_api_static_assets"
      description = "Cache static assets aggressively at the edge"
      expression  = "(http.host eq \"${local.quote_api_host}\" and http.request.uri.path.extension in {\"css\" \"js\" \"mjs\" \"map\" \"png\" \"jpg\" \"jpeg\" \"gif\" \"webp\" \"avif\" \"svg\" \"ico\" \"woff\" \"woff2\" \"ttf\"})"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = var.static_edge_ttl_seconds
        }
        browser_ttl = {
          mode    = "override_origin"
          default = var.static_browser_ttl_seconds
        }
      }
      enabled = true
    },
    {
      ref         = "quote_api_bypass_api"
      description = "Never cache API responses"
      expression  = "(http.host eq \"${local.quote_api_host}\" and starts_with(http.request.uri.path, \"/api/\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
      enabled = true
    },
  ]
}
