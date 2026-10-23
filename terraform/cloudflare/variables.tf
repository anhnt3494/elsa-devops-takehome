variable "zone_id" {
  description = "Cloudflare zone ID of example.com."
  type        = string
}

variable "origin_hostname" {
  description = "Origin the proxied record points at (e.g. the AWS load balancer DNS name)."
  type        = string
}

variable "status_record_id" {
  description = "ID of the manually created status.example.com record being adopted into Terraform."
  type        = string
}

variable "static_edge_ttl_seconds" {
  description = "Edge cache TTL for static assets. Purgeable, so it can be long."
  type        = number
  default     = 2592000 # 30 days
}

variable "static_browser_ttl_seconds" {
  description = "Browser cache TTL for static assets. Not purgeable, so it stays short unless asset names are fingerprinted."
  type        = number
  default     = 86400 # 1 day
}
