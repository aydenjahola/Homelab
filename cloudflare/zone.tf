# Zone-wide settings. Each resource PATCHes one setting, so no import is
# needed: removing one from here leaves Cloudflare at its last value.

locals {
  zone_settings = {
    ssl                      = "strict" # was "full"; origins have valid certs
    min_tls_version          = "1.2"    # was "1.0"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
    email_obfuscation        = "off" # rewrites emails in app HTML (HedgeDoc, Vaultwarden)
  }
}

resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = local.zone_id
  setting_id = each.key
  value      = each.value
}
