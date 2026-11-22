# Records that existed before OpenTofu. Import blocks are no-ops once the
# record is in state, so they can stay.

import {
  to = cloudflare_dns_record.local_wildcard
  id = "${local.zone_id}/017351c121a2ab0cab2b8914fd483adc"
}

import {
  to = cloudflare_dns_record.local_apex
  id = "${local.zone_id}/f8baf3938b9d14ae5f629caf606b89fb"
}

# The DDNS-made *.aydenjahola.com A record, adopted and turned into the
# tunnel CNAME at cutover (var.tunnel_cutover = true).
import {
  for_each = var.tunnel_cutover ? toset(["0"]) : toset([])
  to       = cloudflare_dns_record.wildcard[tonumber(each.key)]
  id       = "${local.zone_id}/f213b82b3ed6a2ce608cb74d64450fe1"
}
