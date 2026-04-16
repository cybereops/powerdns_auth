# PowerDNS Authoritative + PostgreSQL + Terraform

Ambiente Docker Compose com **PowerDNS Authoritative Server 4.9.13** usando
**PostgreSQL 16** como backend, e integração com **Terraform** para
provisionamento declarativo de zonas e registros DNS.

---

## Índice

1. [Arquitetura](#1-arquitetura)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Estrutura do projeto](#3-estrutura-do-projeto)
4. [Deploy](#4-deploy)
5. [Porta DNS customizada](#5-porta-dns-customizada)
6. [Testes](#6-testes)
7. [Provisionamento com Terraform](#7-provisionamento-com-terraform)
8. [Troubleshooting](#8-troubleshooting)
9. [Operação diária](#9-operação-diária)

---

## 1. Arquitetura

```
┌───────────────────────────────────────────────────────────┐
│                        host Linux                         │
│                                                           │
│   porta 5053/udp+tcp ──┐          porta 8081/tcp ──┐      │
│                        │                           │      │
│   ┌────────────────────▼───────────────────────────▼──┐   │
│   │           rede Docker: pdns_net                   │   │
│   │                                                   │   │
│   │   ┌──────────────────┐      ┌──────────────────┐  │   │
│   │   │  powerdns-auth   │─────▶│   powerdns-db    │  │   │
│   │   │  (pdns-auth-49)  │ 5432 │  (postgres:16)   │  │   │
│   │   │                  │      │                  │  │   │
│   │   │ dns     :53      │      │ schema:          │  │   │
│   │   │ api/web :8081    │      │ domains,records, │  │   │
│   │   └──────────────────┘      │ cryptokeys, ...  │  │   │
│   │                             └──────────────────┘  │   │
│   └───────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────┘
           ▲                              ▲
           │ dig / nslookup               │ Terraform
           │ (consultas DNS)              │ (API REST /api/v1)
```

- **powerdns-auth** — servidor DNS autoritativo; expõe `:53` (DNS) e `:8081` (API).
- **powerdns-db** — PostgreSQL com o schema do PowerDNS carregado no primeiro boot.
- **pdns_net** — rede bridge isolada; apenas o container DNS é acessível do host.

---

## 2. Pré-requisitos

| Ferramenta | Versão mínima |
|---|---|
| Docker Engine | 24.x |
| Docker Compose v2 | (plugin) |
| Terraform | 1.6+ |
| `dig` ou `nslookup` | qualquer |
| `curl` + `jq` | para testar a API |

Verificação rápida:

```bash
docker --version
docker compose version
terraform -version
dig -v
```

---

## 3. Estrutura do projeto

```
.
├── docker-compose.yml          # orquestração pdns + postgres
├── .env                        
├── .env.example                # template do .env
├── config/
│   └── pdns.yml.tpl            # config PowerDNS em YAML 
├── docker/
│   ├── pdns/entrypoint.sh      # gera pdns.conf a partir das env vars
│   └── db/init/01-schema.sql   # schema PostgreSQL do PowerDNS
└── terraform/
    ├── providers.tf            # provider pan-net/powerdns
    ├── variables.tf            # pdns_server_url, pdns_api_key, zones, records
    ├── zones.tf                # powerdns_zone (for_each)
    ├── records.tf              # powerdns_record (count)
    ├── outputs.tf              # lista zonas/registros provisionados
    ├── terraform.tfvars        
    └── terraform.tfvars.example
```

---

## 4. Deploy

### 4.1 Configurar variáveis de ambiente

```bash
cp .env.example .env
```

Edite `.env` e ajuste no mínimo:

```env
PDNS_API_KEY=<uma string aleatória longa>       # gere com: openssl rand -hex 32
PDNS_DB_PASSWORD=<senha forte>
PDNS_DNS_PORT=5053                               # 53 em prod, 5053 em dev
PDNS_WEBSERVER_PORT=8081
```

Para gerar uma API key segura:

```bash
openssl rand -hex 32
```

### 4.2 Subir o stack

```bash
docker compose up -d
```

Verifique se ambos os containers estão saudáveis:

```bash
docker compose ps
```

Saída esperada:

```
NAME              STATUS                   PORTS
powerdns-auth     Up X seconds             0.0.0.0:5053->53/tcp,
                                           0.0.0.0:5053->53/udp,
                                           0.0.0.0:8081->8081/tcp
powerdns-db       Up X seconds (healthy)   5432/tcp
```

### 4.3 Acompanhar os logs

```bash
# os dois serviços
docker compose logs -f

# apenas o PowerDNS
docker compose logs -f pdns
```

Logs de sucesso esperados:

```
powerdns-auth  | [entrypoint] Gerando /tmp/pdns.conf...
powerdns-auth  | [entrypoint] Configuração gerada. Iniciando pdns_server...
powerdns-auth  | Apr 16 00:50:00 UTC PowerDNS Authoritative Server 4.9.13 starting up
powerdns-auth  | Apr 16 00:50:00 UTC gpgsql: Using PostgreSQL backend
powerdns-auth  | Apr 16 00:50:00 UTC Done launching threads, ready to distribute questions
```

---

## 5. Porta DNS customizada

A porta `53` quase sempre está ocupada em máquinas Linux modernas:

- `systemd-resolved` (Ubuntu/Debian com GNOME)
- `dnsmasq` (NetworkManager)
- `named`, `unbound`, etc.

Se você tentar subir com `PDNS_DNS_PORT=53` e a porta estiver ocupada, verá:

```
Error response from daemon: Ports are not available: bind for 0.0.0.0:53 failed: port is already allocated
```

**Solução:** use uma porta alta no host (o PowerDNS continua ouvindo :53 **dentro** do container — o mapeamento é só no host).

```bash
# no .env
PDNS_DNS_PORT=5053
```

Recriar o container para aplicar:

```bash
docker compose up -d --force-recreate pdns
```

Verificar qual processo usa a porta 53 no host (se quiser liberar):

```bash
sudo ss -lupn sport = :53
sudo ss -ltpn sport = :53
```

---

## 6. Testes

Com o stack no ar, siga a ordem abaixo: primeiro valide a API, depois crie
uma zona de teste via API, e então faça uma consulta DNS.

### 6.1 Testar a API REST

```bash
# carrega a api key do .env
source .env

curl -s -H "X-API-Key: ${PDNS_API_KEY}" \
  http://localhost:${PDNS_WEBSERVER_PORT}/api/v1/servers/localhost | jq .
```

Saída esperada:

```json
{
  "type": "Server",
  "id": "localhost",
  "daemon_type": "authoritative",
  "version": "4.9.13",
  "url": "/api/v1/servers/localhost",
  "config_url": "/api/v1/servers/localhost/config",
  "zones_url": "/api/v1/servers/localhost/zones"
}
```

Se a resposta for `401 Unauthorized`, a `PDNS_API_KEY` do `.env` não bate com
a que o container carregou — recrie: `docker compose up -d --force-recreate pdns`.

### 6.2 Criar uma zona de teste via API

```bash
source .env

curl -s -X POST \
  -H "X-API-Key: ${PDNS_API_KEY}" \
  -H "Content-Type: application/json" \
  http://localhost:${PDNS_WEBSERVER_PORT}/api/v1/servers/localhost/zones \
  -d '{
    "name": "meudominio.com.br.",
    "kind": "Native",
    "nameservers": ["ns1.meudominio.com.br.", "ns2.meudominio.com.br."],
    "rrsets": [
      {
        "name": "meudominio.com.br.",
        "type": "A",
        "ttl": 300,
        "records": [{"content": "192.168.1.10", "disabled": false}]
      }
    ]
  }' | jq .
```

Listar zonas:

```bash
curl -s -H "X-API-Key: ${PDNS_API_KEY}" \
  http://localhost:${PDNS_WEBSERVER_PORT}/api/v1/servers/localhost/zones | jq '.[].name'
```

### 6.3 Consultar via `nslookup` (porta customizada)

```bash
nslookup -port=5053 meudominio.com.br 127.0.0.1
```

Saída esperada:

```
Server:        127.0.0.1
Address:       127.0.0.1#5053

Name:    meudominio.com.br
Address: 192.168.1.10
```

### 6.4 Consultar via `dig` (mais detalhado)

```bash
# registro A
dig @127.0.0.1 -p 5053 meudominio.com.br A

# registro NS
dig @127.0.0.1 -p 5053 meudominio.com.br NS

# todos os registros (ANY)
dig @127.0.0.1 -p 5053 meudominio.com.br ANY

# SOA
dig @127.0.0.1 -p 5053 meudominio.com.br SOA +short
```

Saída de exemplo (`dig ... A`):

```
;; ANSWER SECTION:
meudominio.com.br.    300    IN    A    192.168.1.10

;; Query time: 3 msec
;; SERVER: 127.0.0.1#5053(127.0.0.1) (UDP)
;; MSG SIZE  rcvd: 62
```

### 6.5 Consultar pela interface TCP

```bash
dig @127.0.0.1 -p 5053 +tcp meudominio.com.br A
```

### 6.6 Deletar a zona de teste

```bash
source .env

curl -s -X DELETE \
  -H "X-API-Key: ${PDNS_API_KEY}" \
  http://localhost:${PDNS_WEBSERVER_PORT}/api/v1/servers/localhost/zones/meudominio.com.br.
```

---

## 7. Provisionamento com Terraform

A criação via API (seção 6.2) é boa para testes rápidos. Para
infraestrutura real, use o Terraform no diretório `terraform/`.

### 7.1 Configurar credenciais

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edite `terraform.tfvars`:

```hcl
pdns_server_url = "http://localhost:8081"
pdns_api_key    = "<valor exato de PDNS_API_KEY do .env>"

zones = {
  "meudominio.com.br." = {
    kind = "Native"
  }
}

records = [
  {
    zone    = "meudominio.com.br."
    name    = "meudominio.com.br."
    type    = "A"
    ttl     = 300
    records = ["192.168.1.10"]
  },
  {
    zone    = "meudominio.com.br."
    name    = "www.meudominio.com.br."
    type    = "CNAME"
    ttl     = 300
    records = ["meudominio.com.br."]
  }
]
```

### 7.2 Init, plan, apply

```bash
terraform init
terraform plan
terraform apply
```

### 7.3 Validar com nslookup

```bash
nslookup -port=5053 meudominio.com.br 127.0.0.1
nslookup -port=5053 www.meudominio.com.br 127.0.0.1
```

### 7.4 Destruir recursos

```bash
terraform destroy
```

---

## 8. Troubleshooting

### Container reinicia em loop

```bash
docker compose logs pdns | tail -50
```

Causas comuns:

| Erro no log | Causa | Correção |
|---|---|---|
| `Unable to open /tmp/pdns.conf` | entrypoint falhou ao gerar o config | veja permissão do `entrypoint.sh` (`chmod +x`) |
| `connection refused` ao Postgres | banco ainda não está pronto | aguarde o healthcheck; reveja `depends_on` |
| `FATAL: password authentication failed` | senha do `.env` difere da do volume | `docker compose down -v && docker compose up -d` (apaga o banco!) |
| `port is already allocated` | porta 53 ou 8081 ocupada | troque `PDNS_DNS_PORT` no `.env` |

### API retorna 401

A `PDNS_API_KEY` mudou no `.env` mas o container foi iniciado com o valor
antigo. Force o recreate:

```bash
docker compose up -d --force-recreate pdns
```

### Consulta DNS trava / timeout

- Confirme que está usando a porta certa: `docker compose ps` mostra os mapeamentos.
- Teste UDP **e** TCP: `dig +tcp ...`.
- Verifique se o firewall local (`ufw`, `firewalld`) bloqueia a porta alta.

### Reset total do ambiente

**Cuidado:** apaga o banco, zonas e registros.

```bash
docker compose down -v
docker compose up -d
```

---

## 9. Operação diária

| Ação | Comando |
|---|---|
| Subir o stack | `docker compose up -d` |
| Derrubar (mantém dados) | `docker compose down` |
| Derrubar e apagar dados | `docker compose down -v` |
| Reiniciar só o PowerDNS | `docker compose restart pdns` |
| Recriar o PowerDNS (após editar `.env`) | `docker compose up -d --force-recreate pdns` |
| Logs em tempo real | `docker compose logs -f pdns` |
| Shell no container | `docker compose exec pdns /bin/bash` |
| Shell no banco | `docker compose exec db psql -U pdns` |
| Listar zonas (SQL) | `docker compose exec db psql -U pdns -c 'SELECT name,type FROM domains;'` |
| Listar registros (SQL) | `docker compose exec db psql -U pdns -c 'SELECT name,type,content FROM records;'` |

### Inspecionar o pdns.conf gerado

```bash
docker compose exec pdns cat /tmp/pdns.conf
```

Útil para conferir quais variáveis do `.env` foram efetivamente aplicadas.

---


