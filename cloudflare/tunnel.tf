# One remotely managed tunnel. cloudflared runs as a Nomad system job
# (nomad/jobs/ingress/cloudflared.hcl), one connector per node, and reads
# its token from Consul cloudflare/tunnel/token.
#
# Routing lives in Traefik, not here: every hostname goes to the loopback
# "tunnel" entrypoint, and only routers that list that entrypoint are
# reachable. Unknown hosts get Traefik's 404.

resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id    = local.account_id
  name          = "homelab"
  config_src    = "cloudflare"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config = {
    ingress = [
      { service = "http://127.0.0.1:8880" },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "homelab" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

resource "consul_keys" "tunnel_token" {
  key {
    path  = "cloudflare/tunnel/token"
    value = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab.token
  }
}
