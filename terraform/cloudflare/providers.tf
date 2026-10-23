# Credentials come from CLOUDFLARE_API_TOKEN in the environment (CI secret),
# never from code or tfvars.
provider "cloudflare" {}
