# status.example.com was created by hand in the dashboard. The import block
# adopts the existing record instead of creating a duplicate; the resource
# below mirrors its current settings, so the first plan must show
# "1 to import, 0 to add, 0 to change". Once applied, this block can stay
# (no-op) or be removed.
import {
  to = cloudflare_dns_record.status
  id = "${var.zone_id}/${var.status_record_id}"
}

resource "cloudflare_dns_record" "status" {
  zone_id = var.zone_id
  name    = "status.example.com"
  type    = "CNAME"
  content = "statuspage.example.net"
  proxied = false
  ttl     = 300
  comment = "Status page (adopted from manual config). Managed by Terraform."
}
