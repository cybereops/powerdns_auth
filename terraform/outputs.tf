output "zones_created" {
  description = "Zonas DNS provisionadas"
  value       = { for k, z in powerdns_zone.zones : k => z.name }
}

output "records_created" {
  description = "Registros DNS provisionados"
  value = [
    for r in powerdns_record.records : {
      zone = r.zone
      name = r.name
      type = r.type
    }
  ]
}
