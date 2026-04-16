variable "pdns_server_url" {
  description = "URL base da API REST do PowerDNS (ex: http://localhost:8081)"
  type        = string
}

variable "pdns_api_key" {
  description = "Chave de API do PowerDNS (PDNS_API_KEY definida no .env)"
  type        = string
  sensitive   = true
}

variable "zones" {
  description = "Mapa de zonas DNS a serem criadas"
  type = map(object({
    kind    = string # Native | Master | Slave
    masters = optional(list(string), [])
  }))
  default = {}
}

variable "records" {
  description = "Lista de registros DNS a serem criados"
  type = list(object({
    zone    = string
    name    = string
    type    = string
    ttl     = number
    records = list(string)
  }))
  default = []
}
