resource "cloudflare_dns_record" "quote_api" {
  zone_id = var.zone_id
  name    = "quote-api.example.com"
  type    = "CNAME"
  content = var.origin_hostname
  proxied = true
  ttl     = 1 # "automatic"; required for proxied records
  comment = "quote-api via Cloudflare proxy. Managed by Terraform."
}
