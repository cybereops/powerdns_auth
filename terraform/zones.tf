resource "powerdns_zone" "zones" {
  for_each = var.zones

  name    = each.key
  kind    = each.value.kind
  masters = each.value.masters
}
