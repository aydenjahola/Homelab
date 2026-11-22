variable "zone_name" {
  type    = string
  default = "aydenjahola.com"
}

data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

locals {
  zone_id    = data.cloudflare_zone.main.zone_id
  account_id = data.cloudflare_zone.main.account.id
}
