# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SMS Gateway is a professional SMS gateway for enterprise use with Huawei E303/E3372 modems. It handles 100-1000 SMS/day with full historization, monitoring, and rate limiting.

**Tech Stack:**
- Elixir 1.17+ / Erlang/OTP 27+
- Phoenix 1.8.3 (REST API + LiveView admin)
- Ash Framework 3.16+ (domain modeling)
- PostgreSQL 16+ (persistence)
- Oban 2.20+ (job queue + cron)
- HTTPoison (modem HTTP client)

## Development Commands

```bash
# Setup (first time)
mix setup                    # Install deps, create DB, setup assets

# Development server
mix phx.server               # Start server at http://localhost:4000

# Database
mix ecto.create              # Create database
mix ecto.migrate             # Run migrations
mix ecto.reset               # Drop, create, migrate, seed
mix ash.codegen              # Generate Ash migrations when resources change

# Testing
mix test                     # Run all tests (creates test DB + migrates)
mix test test/path/file.exs  # Run single test file
mix test test/path/file.exs:42  # Run single test at line

# Code quality
mix precommit                # Run before commit (compile strict, format, test)
mix format                   # Format code
mix compile --warnings-as-errors  # Strict compilation

# Assets (Tailwind CSS + daisyUI)
mix assets.build             # Build CSS/JS for development
mix assets.deploy            # Build minified assets for production
```

## Architecture

### Domain Layer (Ash Framework)

The core business logic is modeled using **Ash Framework 3.16+**, which provides declarative resource definitions with actions, policies, and validations.

**Key Resources:**
- `lib/sms_gateway/sms/api_key.ex` - API key management with bcrypt hashing
- `lib/sms_gateway/sms/message.ex` - SMS messages with status tracking
- `lib/sms_gateway/sms/domain.ex` - Ash domain definition

**Ash Actions Pattern:**
```elixir
# Resources define actions, not functions
Ash.create(ApiKey, %{name: "App", rate_limit: 100}, action: :create_key)
Ash.read!(Message)
Ash.update(message, %{status: :delivered})
```

**Important:** When modifying resources, run `mix ash.codegen` to generate database migrations.

### Modem Layer

**Circuit Breaker Pattern:** All modem operations use a circuit breaker (`lib/sms_gateway/modem/client.ex`) to prevent cascading failures when the modem is unreachable.

**Key Modules:**
- `SmsGateway.Modem.Client` - HTTP client with session token caching and circuit breaker
- `SmsGateway.Modem.Poller` - Background polling for incoming SMS (30s interval)
- `SmsGateway.Modem.StatusMonitor` - Health checks and circuit breaker management (60s interval)

**Modem Communication:**
- Base URL: `http://192.168.8.1` (Huawei default)
- Authentication: SesTokInfo → SessionID + Token (cached 5min)
- XML responses parsed with SweetXml

### Background Jobs (Oban)

**Workers:**
- `SmsGateway.Workers.SendSms` - Send outgoing SMS via modem
  - Concurrency: 6 (max 6 parallel sends)
  - Rate limit: 6/minute (modem hardware limit)
- `SmsGateway.Workers.UpdateStatus` - Poll delivery status from modem (cron: every 5min)

**Queue Configuration:**
```elixir
# config/runtime.exs
queues: [
  sms_send: [
    limit: 6,
    rate_limit: [allowed: 6, period: 60]
  ]
]
```

### Web Layer

**API (REST):**
- `lib/sms_gateway_web/controllers/api/v1/message_controller.ex` - POST /api/v1/messages
- Plugs: `ApiAuth` (validate API keys), `RateLimiter` (per-key limits)

**Admin Interface (LiveView):**
- `lib/sms_gateway_web/live/admin/api_keys_live.ex` - CRUD for API keys at /admin/api-keys
- Uses **daisyUI 5.0.35** components (built on Tailwind CSS v4)
- Protected by HTTP Basic Auth (ADMIN_USERNAME/ADMIN_PASSWORD)

**Important:** Admin interface uses **Phoenix LiveView** with real-time updates via PubSub broadcasts.

## Key Patterns

### API Key Security

API keys use the format `sk_live_` + random chars:
- **Prefix length limit:** 20 characters max (`key_prefix` in DB)
- Generation: `"sk_live_" <> String.slice(random_64_hex, 0..10)` → 19 chars total
- Storage: Full key hashed with Bcrypt (cost 12), only prefix visible
- Display: Show full key ONCE on creation, then only prefix

**Critical:** The `:create_key` action in `ApiKey` resource generates keys internally. Do NOT pass `key_hash` or `key_prefix` as inputs.

### Rate Limiting

**Two levels:**
1. **Per API Key** (configurable): Default 100 SMS/hour, enforced in `RateLimiter` plug
2. **Global (Oban)**: 6 SMS/minute enforced by Oban queue rate_limit

### Circuit Breaker

Modem operations fail-fast when circuit opens (5 consecutive failures):
- States: `:closed` → `:open` (5 failures) → `:half_open` (after backoff) → `:closed` (success)
- Prevents cascading timeouts when modem unreachable
- Jobs paused when circuit open, resumed when closed

## Configuration

**Environment Variables (production):**
```bash
DATABASE_URL              # PostgreSQL connection
SECRET_KEY_BASE           # Phoenix secret (mix phx.gen.secret)
PHX_HOST                  # Domain name
MODEM_BASE_URL           # Default: http://192.168.8.1
ADMIN_USERNAME           # Admin interface login
ADMIN_PASSWORD           # REQUIRED in production
DEFAULT_RATE_LIMIT       # SMS/hour per API key (default: 100)
```

**Files:**
- `config/dev.exs` - Development (gitignored, copy from dev.exs.example)
- `config/runtime.exs` - Production runtime config (reads ENV vars)
- `config/test.exs` - Test environment (in-memory DB)

## Testing

Tests use **ExUnit** with Ash test helpers:
```elixir
# Test data creation
{:ok, api_key} = Ash.create(ApiKey, %{name: "Test", rate_limit: 100},
                             action: :create_key)

# Bypass modem in tests
Bypass.open()
Bypass.expect(bypass, "POST", "/api/sms/send-sms", fn conn ->
  Plug.Conn.resp(conn, 200, ~s(<?xml version="1.0"...))
end)
```

## Admin Interface (daisyUI)

The admin interface at `/admin/api-keys` uses **daisyUI 5.0.35** component library:
- Card, button, badge, alert, input, modal components
- Dark mode support with auto-detection
- Real-time updates via Phoenix PubSub
- Compiled CSS at `priv/static/assets/app.css`

**Rebuilding CSS after changes:**
```bash
mix assets.build
# Or in development, Phoenix watches automatically
```

## Deployment

Production deployment via systemd service + nginx reverse proxy. See `deployment/README.md` for full automation scripts.

**Manual production build:**
```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
_build/prod/rel/sms_gateway/bin/sms_gateway start
```

## Troubleshooting

**Modem connection issues:**
- Check modem at http://192.168.8.1 (direct browser access)
- Verify SIM card active and unlocked
- Check circuit breaker state in logs: `[error] Circuit breaker opening after 5 failures`

**API key validation errors:**
- Error "key_prefix: length must be less than or equal to 20" → check generation uses `String.slice(secret, 0..10)` not `0..16`
- Keys generated by `:create_key` action, NOT manually in LiveView

**Phoenix code reloader not working in git worktrees:**
- Worktree issue: copy modified files to main project directory
- Restart server from main project: `cd /path/to/main && mix phx.server`

**CSS not loading:**
- Check file exists: `ls priv/static/assets/app.css`
- Rebuild: `mix assets.build`
- Verify layout references correct path: `/assets/app.css` (not `/assets/css/app.css`)
