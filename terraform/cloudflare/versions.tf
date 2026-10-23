terraform {
  required_version = ">= 1.7, < 2.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }

  # Partial config, completed at init time with -backend-config.
  # Validation runs with -backend=false and never touches it.
  backend "s3" {}
}
