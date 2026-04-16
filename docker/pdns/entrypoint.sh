#!/bin/sh
# =============================================================================
# Entrypoint do PowerDNS Authoritative Server
# Gera /tmp/pdns.conf (formato nativo do pdns_server) a partir das
# variáveis de ambiente definidas em .env.
# O arquivo config/pdns.yml.tpl é a fonte de verdade legível por humanos;
# as mesmas chaves existem aqui em formato key=value.
# =============================================================================
set -e

CONFIG="/tmp/pdns.conf"

echo "[entrypoint] Gerando ${CONFIG}..."

cat > "${CONFIG}" << EOF
# PowerDNS Authoritative Server 4.9 — gerado pelo entrypoint
# Não edite manualmente; altere config/pdns.yml.tpl e reinicie o container.

# API REST (Terraform / curl)
api=yes
api-key=${PDNS_API_KEY}

# Webserver embutido
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=0.0.0.0/0,::/0
webserver-loglevel=none

# Backend PostgreSQL
launch=gpgsql
gpgsql-host=${PDNS_DB_HOST}
gpgsql-port=${PDNS_DB_PORT}
gpgsql-dbname=${PDNS_DB_NAME}
gpgsql-user=${PDNS_DB_USER}
gpgsql-password=${PDNS_DB_PASSWORD}
gpgsql-dnssec=yes

# Listener DNS
local-address=0.0.0.0
local-port=53

# Logging
loglevel=4
log-dns-queries=no
log-dns-details=no

# SOA padrão
default-soa-content=ns1.example.com. hostmaster.example.com. 0 10800 3600 604800 3600

# Desempenho
receiver-threads=2
distributor-threads=2
cache-ttl=20
negquery-cache-ttl=60
EOF

echo "[entrypoint] Configuração gerada. Iniciando pdns_server..."
exec pdns_server --config-dir=/tmp "$@"
