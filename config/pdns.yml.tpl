---
# =============================================================================
# PowerDNS Authoritative Server 4.9 - Configuração YAML
# Este arquivo é um template; as variáveis ${...} são substituídas pelo
# entrypoint antes da inicialização do servidor.
# Referência: https://doc.powerdns.com/authoritative/settings.html
# =============================================================================

# ---------------------------------------------------------------------------
# API REST (usada pelo Terraform provider powerdns/powerdns)
# ---------------------------------------------------------------------------
api: yes
api-key: "${PDNS_API_KEY}"

# ---------------------------------------------------------------------------
# Webserver embutido — expõe a API REST
# ---------------------------------------------------------------------------
webserver: yes
webserver-address: "0.0.0.0"
webserver-port: 8081
webserver-allow-from: "0.0.0.0/0,::/0"
webserver-loglevel: "none"

# ---------------------------------------------------------------------------
# Backend: PostgreSQL (gpgsql)
# ---------------------------------------------------------------------------
launch:
  - gpgsql

gpgsql-host: "${PDNS_DB_HOST}"
gpgsql-port: ${PDNS_DB_PORT}
gpgsql-dbname: "${PDNS_DB_NAME}"
gpgsql-user: "${PDNS_DB_USER}"
gpgsql-password: "${PDNS_DB_PASSWORD}"
gpgsql-dnssec: yes

# ---------------------------------------------------------------------------
# Listener DNS
# ---------------------------------------------------------------------------
local-address: "0.0.0.0"
local-port: 53

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
loglevel: 4
log-dns-queries: no
log-dns-details: no

# ---------------------------------------------------------------------------
# Padrão SOA — ajuste para seu domínio
# ---------------------------------------------------------------------------
default-soa-content: "ns1.example.com. hostmaster.example.com. 0 10800 3600 604800 3600"

# ---------------------------------------------------------------------------
# Desempenho
# ---------------------------------------------------------------------------
receiver-threads: 2
distributor-threads: 2
cache-ttl: 20
negquery-cache-ttl: 60
