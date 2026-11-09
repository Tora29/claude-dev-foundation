#!/bin/bash
. "$(dirname "$0")/../common.sh"
mkdir -p infra
cat > infra/main.tf <<'TF'
terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}
TF
