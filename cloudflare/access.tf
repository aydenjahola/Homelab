# Cloudflare Access (Zero Trust org: aydenjahola.cloudflareaccess.com) with
# Authentik as the only identity provider.
#
# LAN and VPN clients never pass through Cloudflare (AdGuard answers
# *.aydenjahola.com with the Traefik VIP), so these apps only gate
# internet traffic. They are a real control only once 80/443 are closed.

locals {
  team_domain   = "aydenjahola.cloudflareaccess.com"
  authentik_url = "https://auth.${var.zone_name}"
  oidc_slug     = "cloudflare-access"

  # Hosts that need an Access login. Left out on purpose: home (public
  # dashboard), auth (the IdP), vault and ntfy (native apps), status/gatus
  # (public status page), md (link-shared notes), gym (PWA with push).
  protected_apps = {
    grafana   = "Grafana"
    netronome = "Netronome"
    pdf       = "Stirling PDF"
    plausible = "Plausible"
  }

  # Paths that must stay public on protected hosts (more specific path wins).
  bypass_paths = {
    plausible-script = { host = "plausible", path = "js/*", name = "Plausible tracking script" }
    plausible-event  = { host = "plausible", path = "api/event", name = "Plausible event API" }
  }
}

# --- Authentik OIDC client -------------------------------------------------
# The secret is generated here and written to Consul; the Authentik
# blueprint app-cloudflare-access.yaml reads the same keys.

resource "random_password" "access_client_secret" {
  length  = 64
  special = false
}

resource "consul_keys" "authentik_access_client" {
  key {
    path  = "authentik/oidc/${local.oidc_slug}/client_id"
    value = local.oidc_slug
  }

  key {
    path  = "authentik/oidc/${local.oidc_slug}/client_secret"
    value = random_password.access_client_secret.result
  }
}

data "consul_keys" "owner" {
  key {
    name = "email"
    path = "authentik/user/email"
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  account_id = local.account_id
  name       = "Authentik"
  type       = "oidc"

  config = {
    client_id        = local.oidc_slug
    client_secret    = random_password.access_client_secret.result
    auth_url         = "${local.authentik_url}/application/o/authorize/"
    token_url        = "${local.authentik_url}/application/o/token/"
    certs_url        = "${local.authentik_url}/application/o/${local.oidc_slug}/jwks/"
    scopes           = ["openid", "email", "profile"]
    email_claim_name = "email"
    pkce_enabled     = true
  }

  depends_on = [consul_keys.authentik_access_client]
}

# --- Policies ----------------------------------------------------------------

resource "cloudflare_zero_trust_access_policy" "owner" {
  account_id       = local.account_id
  name             = "Owner via Authentik"
  decision         = "allow"
  session_duration = "24h"

  include = [
    { email = { email = data.consul_keys.owner.var.email } },
  ]

  require = [
    { login_method = { id = cloudflare_zero_trust_access_identity_provider.authentik.id } },
  ]
}

resource "cloudflare_zero_trust_access_policy" "public" {
  account_id = local.account_id
  name       = "Public bypass"
  decision   = "bypass"

  include = [
    { everyone = {} },
  ]
}

# --- Applications ------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "protected" {
  for_each = local.protected_apps

  account_id                = local.account_id
  name                      = each.value
  type                      = "self_hosted"
  domain                    = "${each.key}.${var.zone_name}"
  session_duration          = "24h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.authentik.id]
  auto_redirect_to_identity = true
  app_launcher_visible      = false

  policies = [
    { id = cloudflare_zero_trust_access_policy.owner.id, precedence = 1 },
  ]
}

resource "cloudflare_zero_trust_access_application" "bypass" {
  for_each = local.bypass_paths

  account_id           = local.account_id
  name                 = each.value.name
  type                 = "self_hosted"
  domain               = "${each.value.host}.${var.zone_name}/${each.value.path}"
  app_launcher_visible = false

  policies = [
    { id = cloudflare_zero_trust_access_policy.public.id, precedence = 1 },
  ]
}
