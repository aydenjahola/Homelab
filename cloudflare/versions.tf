terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State lives in Consul KV beside every other secret and is covered by
  # cluster-snapshot-backup.
  backend "consul" {
    address = "192.168.1.100:8500"
    scheme  = "http"
    path    = "terraform/cloudflare"
    lock    = true
  }
}

# CLOUDFLARE_API_TOKEN comes from apply.sh (Consul cloudflare/terraform/token).
provider "cloudflare" {}

provider "consul" {
  address = "192.168.1.100:8500"
  scheme  = "http"
}
