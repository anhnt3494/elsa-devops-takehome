output "quote_api_record_id" {
  value = cloudflare_dns_record.quote_api.id
}

output "cache_ruleset_id" {
  value = cloudflare_ruleset.cache.id
}
