# Custom WAF rules (Free plan: 5 rules). T1 is Cloudflare's country code
# for Tor exit nodes.
variable "blocked_countries" {
  type    = list(string)
  default = ["CN", "RU", "T1"]
}

resource "cloudflare_ruleset" "waf_custom" {
  zone_id     = local.zone_id
  name        = "homelab custom rules"
  description = "Managed by OpenTofu (cloudflare/waf.tf)"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      description = "Block countries and Tor"
      expression  = "(ip.src.country in {${join(" ", formatlist("\"%s\"", var.blocked_countries))}})"
      action      = "block"
      enabled     = true
    },
    {
      description = "Block router and IoT exploit scanners"
      expression  = "(http.request.uri.path contains \"/shell\") or (http.request.uri.path contains \"/device.rsp\") or (http.request.uri.query contains \"chmod\")"
      action      = "block"
      enabled     = true
    },
  ]
}
