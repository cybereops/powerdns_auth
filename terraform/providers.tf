terraform {
  required_version = ">= 1.6"

  required_providers {
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5"
    }
  }
}

provider "powerdns" {
  server_url = var.pdns_server_url
  api_key    = var.pdns_api_key
}
