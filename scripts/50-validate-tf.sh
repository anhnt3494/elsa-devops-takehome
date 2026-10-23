#!/usr/bin/env bash
# Part 5b: static checks for the Cloudflare Terraform. Validate-only: no
# backend, no credentials, no API calls. Provider versions and checksums come
# from the committed .terraform.lock.hcl (read-only).
source "$(dirname "$0")/lib.sh"

TF_DIR=$REPO/terraform/cloudflare
# Keep .terraform/ out of the bind-mounted repo (the toolbox runs as root).
export TF_DATA_DIR=/tmp/tf-data/cloudflare
export TF_IN_AUTOMATION=1

log "terraform fmt -check"
terraform -chdir="$TF_DIR" fmt -check -recursive -diff

log "terraform init -backend=false"
terraform -chdir="$TF_DIR" init -backend=false -input=false -lockfile=readonly >/dev/null

log "terraform validate"
terraform -chdir="$TF_DIR" validate
ok "Cloudflare Terraform is formatted and valid"
