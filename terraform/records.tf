resource "powerdns_record" "records" {
  count = length(var.records)

  zone    = var.records[count.index].zone
  name    = var.records[count.index].name
  type    = var.records[count.index].type
  ttl     = var.records[count.index].ttl
  records = var.records[count.index].records

  depends_on = [powerdns_zone.zones]
}
