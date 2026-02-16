# SMS Gateway 📱

> Passerelle SMS professionnelle pour entreprise avec modem Huawei E303/E3372, Ash Framework, Oban et monitoring Zabbix

[![Elixir](https://img.shields.io/badge/Elixir-1.17.3-blueviolet.svg)](https://elixir-lang.org)
[![Erlang/OTP](https://img.shields.io/badge/Erlang%2FOTP-27-red.svg)](https://www.erlang.org)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8.3-orange.svg)](https://phoenixframework.org)
[![Ash](https://img.shields.io/badge/Ash-3.16+-green.svg)](https://ash-hq.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 🎯 Vue d'ensemble

SMS Gateway est une solution complète pour l'envoi et la réception de SMS en entreprise via un modem USB Huawei E303/E3372. Conçue pour gérer 100-1000 SMS par jour avec fiabilité, historisation complète et monitoring intégré.

### ✨ Caractéristiques principales

- 🚀 **API REST moderne** - JSON API avec authentification par clés API
- 📊 **Dashboard LiveView** - Monitoring en temps réel
- 🔄 **File d'attente Oban** - Gestion asynchrone avec retry automatique
- 🛡️ **Circuit Breaker** - Protection contre les défaillances du modem
- 📈 **Télémétrie complète** - Métriques Prometheus et Zabbix
- 🔐 **Sécurité renforcée** - Rate limiting, API keys hashées, SSL/TLS
- 🌐 **Multi-modem** - Support E303, E3372, E3372h, E3131
- 📝 **Historisation** - Tous les messages avec statuts et timestamps
- ⚡ **Performance** - Circuit breaker, session caching, rate limiting
- 🔍 **Monitoring** - Intégration Zabbix pour alertes et métriques

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CLIENT HTTP/HTTPS                        │
│              (Applications, Scripts, Zabbix)                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   NGINX (Reverse Proxy)                      │
│                     SSL/TLS + Headers                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              PHOENIX WEB (Port 4000)                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Router → Controllers → Plugs (Auth, RateLimit)       │  │
│  │  - ApiAuth: Validation clés API                       │  │
│  │  - RateLimiter: 100 SMS/heure par clé                 │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                 DOMAIN LAYER (Ash Framework)                 │
│  ┌──────────────┐              ┌──────────────┐            │
│  │   Message    │              │   ApiKey     │            │
│  │  Resource    │              │   Resource   │            │
│  │ - create     │              │ - create     │            │
│  │ - list       │              │ - validate   │            │
│  │ - mark_sent  │              │ - rate_limit │            │
│  └──────────────┘              └──────────────┘            │
└──────────────────────┬──────────────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
┌────────────┐  ┌──────────┐  ┌────────────────┐
│ PostgreSQL │  │   Oban   │  │ Modem Client   │
│  Database  │  │  Queue   │  │  (HTTP Client) │
│            │  │          │  │                │
│ Messages   │  │ Workers: │  │ - SesTokInfo   │
│ ApiKeys    │  │ SendSms  │  │ - SessionID    │
│ Oban Jobs  │  │ Status   │  │ - Token cache  │
└────────────┘  └──────────┘  └────────┬───────┘
                       │                │
                       │                ▼
                       │     ┌──────────────────┐
                       │     │  Huawei E303     │
                       │     │  Modem USB       │
                       │     │  192.168.8.1     │
                       │     └──────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│         Background Services                  │
│  - Poller: SMS entrants (30s)               │
│  - StatusMonitor: Health check (60s)        │
│  - UpdateStatus: Delivery status (5min)     │
└─────────────────────────────────────────────┘
```

### 🔧 Stack technique

| Composant | Technologie | Version | Rôle |
|-----------|-------------|---------|------|
| **Runtime** | Erlang/OTP | 27.2+ | VM haute disponibilité |
| **Language** | Elixir | 1.17.3+ | Langage fonctionnel |
| **Web Framework** | Phoenix | 1.8.3 | API REST + LiveDashboard |
| **Domain Layer** | Ash Framework | 3.16+ | Domain modeling + policies |
| **Database** | PostgreSQL | 16+ | Persistance + Oban queue |
| **Job Queue** | Oban | 2.20+ | Jobs asynchrones + cron |
| **HTTP Client** | HTTPoison | 2.2 | Communication modem |
| **XML Parser** | SweetXml | 0.7 | Parse réponses modem |
| **Auth** | Bcrypt | 3.2 | Hash API keys |

## 🚀 Installation rapide

### Prérequis

- **Erlang/OTP 27+** et **Elixir 1.17+** ([via asdf](https://asdf-vm.com))
- **PostgreSQL 16+**
- **Modem Huawei E303/E3372** avec carte SIM active
- **Ubuntu 24.04 LTS** (recommandé pour production)

### Installation développement

```bash
# 1. Cloner le repository
git clone https://github.com/dixboss/sms-gateway.git
cd sms-gateway

# 2. Installer les dépendances
mix deps.get

# 3. Configurer la base de données
cp config/dev.exs.example config/dev.exs
# Éditer config/dev.exs avec vos paramètres

# 4. Créer et migrer la base
mix ecto.create
mix ecto.migrate

# 5. Démarrer le serveur
mix phx.server

# L'application est disponible sur http://localhost:4000
```

### Installation production (Ubuntu 24.04)

Pour un déploiement automatisé complet, consultez le [Guide de déploiement](deployment/README.md).

## ⚙️ Configuration

### Variables d'environnement

Créer un fichier `.env` ou configurer dans `config/runtime.exs`:

```bash
# Base de données
DATABASE_URL=ecto://user:pass@localhost/sms_gateway_prod
POOL_SIZE=10

# Phoenix
SECRET_KEY_BASE=<généré via: mix phx.gen.secret>
PHX_HOST=sms-gateway.example.com
PORT=4000

# Modem Huawei
MODEM_BASE_URL=http://192.168.8.1
MODEM_POLL_INTERVAL=30000        # 30 secondes
MODEM_HEALTH_CHECK_INTERVAL=60000 # 60 secondes

# Oban (Queue)
OBAN_SMS_SEND_CONCURRENCY=6      # Max 6 SMS simultanés
OBAN_SMS_SEND_RATE_LIMIT=6       # Max 6 SMS/minute (limite modem)

# Rate limiting
DEFAULT_RATE_LIMIT=100           # SMS/heure par API key

# Logs
LOG_LEVEL=info
```

## 📖 Utilisation

### Créer une API Key

**Via IEx console** (méthode actuelle):
```elixir
# Console IEx
iex -S mix

alias SmsGateway.Sms.ApiKey
{:ok, api_key} = Ash.create(ApiKey, %{
  name: "Application Mobile",
  rate_limit: 100  # SMS/heure
})

# Sauvegarder la clé (affichée une seule fois!)
# sk_live_abc123...
```

> ⚠️ **Note**: Une interface web d'administration pour la gestion des API Keys est prévue dans la roadmap.

### Envoyer un SMS via API

```bash
curl -X POST https://sms-gateway.example.com/api/v1/messages \
  -H "X-API-Key: sk_live_abc123..." \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "+33612345678",
    "content": "Votre code de vérification: 123456"
  }'
```

**Réponse**:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "direction": "outgoing",
  "phone": "+33612345678",
  "content": "Votre code de vérification: 123456",
  "status": "queued",
  "inserted_at": "2026-02-16T10:30:00Z"
}
```

### Vérifier la santé du système

```bash
curl https://sms-gateway.example.com/api/health
```

**Réponse**:
```json
{
  "status": "healthy",
  "modem": {
    "connected": true,
    "signal_strength": 85,
    "network": "Orange F"
  },
  "queue": {
    "pending": 5,
    "executing": 2
  },
  "database": "connected"
}
```

## 🔐 Sécurité

### API Keys

- **Format**: `sk_live_` + 32 caractères aléatoires
- **Stockage**: Hash Bcrypt (cost 12)
- **Prefix visible**: Premiers caractères pour identification
- **Rate limiting**: Configurable par clé

### Rate Limiting

**Par API Key** (configurable):
- Default: 100 SMS/heure
- Headers retournés: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- Réponse 429 si dépassé

**Global (modem)**:
- Max 6 SMS/minute (limite hardware)
- Configuré dans Oban: `rate_limit: [allowed: 6, period: 60]`

## 📊 Monitoring

### LiveDashboard

Accéder au dashboard en temps réel:
```
https://sms-gateway.example.com/dashboard
```

**Métriques disponibles**:
- SMS envoyés/reçus/échoués
- Signal modem en temps réel
- Queue Oban (pending, executing)
- Performance base de données

## 📄 License

Ce projet est sous licence MIT. Voir [LICENSE](LICENSE) pour plus de détails.

## 🗺️ Roadmap

- [ ] **Interface web d'administration** (gestion API Keys)
- [ ] Support multi-modems (load balancing)
- [ ] Webhooks pour notifications temps réel
- [ ] SMS longs (> 160 caractères, automatic split)
- [ ] Templates de messages
- [ ] Scheduled SMS (envoi programmé)
- [ ] Analytics dashboard (graphiques, stats)
- [ ] API GraphQL

---

**Fait avec ❤️ pour Congo Handling**

⭐ Si ce projet vous est utile, n'hésitez pas à lui donner une étoile!
