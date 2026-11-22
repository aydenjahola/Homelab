# Redirect and configuration rules that were created in the dashboard,
# adopted so the whole zone is in code.

import {
  to = cloudflare_ruleset.redirects
  id = "zones/${local.zone_id}/03c6c577952c4c169d38534ca822e0a3"
}

resource "cloudflare_ruleset" "redirects" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      description = "Redirect to outline.solarracing.ie"
      expression  = "(starts_with(http.request.full_uri, \"https://outline.aydenjahola.com/\"))"
      action      = "redirect"
      enabled     = true
      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = false
          target_url = {
            value = "https://outline.solarracing.ie/"
          }
        }
      }
    },
  ]
}

# The only rule here ("Hedgedoc disable rocket loader") never matched
# (full URI equals a bare hostname) and Rocket Loader is off zone-wide,
# so the phase is emptied.
import {
  to = cloudflare_ruleset.config
  id = "zones/${local.zone_id}/e3262a4734c94b7a89ee9851520f52ab"
}

resource "cloudflare_ruleset" "config" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_config_settings"
  rules   = []
}
