# Only the records the homelab owns. Everything else in the zone (apex and
# www on Vercel, blog, spotify-stats, mail, verification TXT records and
# the _acme-challenge records Traefik writes) is deliberately unmanaged.
#
# vpn.aydenjahola.com is owned by the cloudflare-ddns job, not here.

locals {
  traefik_vip = "192.168.1.240"
}

variable "tunnel_cutover" {
  description = "Point *.aydenjahola.com at the tunnel. Set false only to roll back (then restore the home-IP record and port forwards)."
  type        = bool
  default     = true
}

# Every public hostname. Which ones actually answer is decided by the
# Traefik routers that opt in with entrypoints=https,tunnel.
resource "cloudflare_dns_record" "wildcard" {
  count = var.tunnel_cutover ? 1 : 0

  zone_id = local.zone_id
  name    = "*.${var.zone_name}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Cloudflare Tunnel (OpenTofu)"
}

# LAN-only names. Public DNS answers with the Traefik VIP, so they only
# work on the LAN or VPN (AdGuard answers the same thing locally).
resource "cloudflare_dns_record" "local_wildcard" {
  zone_id = local.zone_id
  name    = "*.local.${var.zone_name}"
  type    = "A"
  content = local.traefik_vip
  proxied = false
  ttl     = 1
  comment = "Traefik VIP, LAN only (OpenTofu)"
}

resource "cloudflare_dns_record" "local_apex" {
  zone_id = local.zone_id
  name    = "local.${var.zone_name}"
  type    = "A"
  content = local.traefik_vip
  proxied = false
  ttl     = 1
  comment = "Traefik VIP, LAN only (OpenTofu)"
}
