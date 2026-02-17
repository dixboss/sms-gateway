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
Ash.create(ApiKey, %{name: "App", rate_limit: 100}, action: :create)
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
- `lib/sms_gateway_web/controllers/health_controller.ex` - GET /api/health
- Plugs: `ApiAuth` (validate API keys), `RateLimiter` (per-key limits)

**Admin Interface (AshAdmin):**
- Auto-generated CRUD interface at `/admin`
- Manages API Keys and Messages
- Uses **AshAdmin 0.14.0** for automatic resource management
- Protected by HTTP Basic Auth (ADMIN_USERNAME/ADMIN_PASSWORD)
- Built on Phoenix LiveView with real-time updates

## Key Patterns

### API Key Security

API keys use the format `sk_live_` + random chars:
- **Prefix length limit:** 20 characters max (`key_prefix` in DB)
- Generation: `"sk_live_" <> String.slice(random_64_hex, 0..10)` → 19 chars total
- Storage: Full key hashed with Bcrypt (cost 12), only prefix visible
- Display: Show full key ONCE on creation, then only prefix

**Critical:** The `:create` action in `ApiKey` resource generates keys internally. Do NOT pass `key_hash` or `key_prefix` as inputs - only pass `name` and optional `rate_limit`.

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
                             action: :create)

# Bypass modem in tests
Bypass.open()
Bypass.expect(bypass, "POST", "/api/sms/send-sms", fn conn ->
  Plug.Conn.resp(conn, 200, ~s(<?xml version="1.0"...))
end)
```

## Available Routes

The application exposes only essential endpoints:

**API Endpoints:**
- `GET /api/health` - Health check (public)
- `POST /api/v1/messages` - Send SMS (requires API key)
- `GET /api/v1/messages` - List sent messages (requires API key)
- `GET /api/v1/messages/:id` - Get message details (requires API key)

**Admin Interface:**
- `GET /admin` - AshAdmin interface (requires Basic Auth)
  - Manage API Keys
  - View/search messages
  - Auto-generated CRUD forms

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
- Keys generated by `:create` action automatically - only provide `name` and optional `rate_limit`
- Use AshAdmin at `/admin` to manage API keys

**Phoenix code reloader not working in git worktrees:**
- Worktree issue: copy modified files to main project directory
- Restart server from main project: `cd /path/to/main && mix phx.server`

**CSS not loading:**
- Check file exists: `ls priv/static/assets/app.css`
- Rebuild: `mix assets.build`
- Verify layout references correct path: `/assets/app.css` (not `/assets/css/app.css`)

# MCP Gemini Design - MANDATORY FOR FRONTEND

## ⛔ ABSOLUTE RULE - NEVER IGNORE

**You MUST NEVER write frontend/UI code yourself.**

Gemini is your frontend developer. You are NOT allowed to create visual components, pages, or interfaces without going through Gemini. This is NON-NEGOTIABLE.

### When to use Gemini? ALWAYS for:
- Creating a page (dashboard, landing, settings, etc.)
- Creating a visual component (card, modal, sidebar, form, button, etc.)
- Modifying the design of an existing element
- Anything related to styling/layout

### Exceptions (you can do it yourself):
- Modifying text/copy
- Adding JS logic without changing the UI
- Non-visual bug fixes
- Data wiring (useQuery, useMutation, etc.)

## MANDATORY Workflow

### 1. New project without existing design
```
STEP 1: generate_vibes → show options to the user
STEP 2: User chooses their vibe
STEP 3: create_frontend with the chosen vibe
```

### 2. Existing project with design
```
ALWAYS pass CSS/theme files in the `context` parameter
```

### 3. After Gemini's response
```
Gemini returns code → YOU write it to disk with Write/Edit
```

## Checklist before coding frontend

- [ ] Am I creating/modifying something visual?
- [ ] If YES → STOP → Use Gemini
- [ ] If NO (pure logic) → You can continue

## ❌ WHAT IS FORBIDDEN

- Writing a React component with styling without Gemini
- Creating a page without Gemini
- "Reusing existing styles" as an excuse to not use Gemini
- Doing frontend "quickly" yourself

## ✅ WHAT IS EXPECTED

- Call Gemini BEFORE writing any frontend code
- Ask the user for their vibe choice if new project
- Let Gemini design, you implement

## Git Workflow

- Feature branches from `main`
- PR reviews required
- Commit messages: conventional commits (`feat:`, `fix:`, `docs:`, etc.)
- CI/CD via GitHub Actions

# Browser Agent (agent-browser) - MANDATORY FOR UI VERIFICATION

## ⛔ ABSOLUTE RULE - ALWAYS VERIFY UI CHANGES

**After ANY UI modification, you MUST verify changes with `agent-browser`.**

`agent-browser` is your visual verification tool. You are NOT allowed to consider a UI task complete without browser verification. This is NON-NEGOTIABLE.

### When to use agent-browser? ALWAYS after:
- Fixing a UI bug (verify the fix works)
- Adding/modifying actions in tables (verify buttons appear correctly)
- Changing navigation (verify links work)
- Modifying modals or forms (verify they open/close properly)
- Any LiveView component changes (verify rendering)
- Fixing duplicate ID errors (verify no console errors)

### Quick Reference Commands

```bash
# Core workflow
agent-browser open <url>        # Navigate to page
agent-browser snapshot -i       # Get interactive elements with refs
agent-browser click @e1         # Click element by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser

# Verification
agent-browser console           # View console messages (check for errors)
agent-browser errors            # View page errors
agent-browser screenshot        # Take screenshot

# Waiting
agent-browser wait @e1          # Wait for element
agent-browser wait --text "OK"  # Wait for text to appear
```

### Key Commands for UI Verification

| Command | Usage |
|---------|-------|
| `open <url>` | Navigate to URL |
| `snapshot -i` | Get interactive elements with refs (@e1, @e2...) |
| `click @ref` | Click element |
| `console` | Check for JS errors |
| `errors` | View page errors |
| `screenshot [path]` | Capture visual state |
| `get text @ref` | Get element text |
| `is visible @ref` | Check element visibility |

## MANDATORY Workflow

### 1. After UI code changes
```bash
# STEP 1: Compile code
mix compile

# STEP 2: Navigate to the affected page
agent-browser open http://localhost:4000/app/sessions

# STEP 3: Get interactive elements
agent-browser snapshot -i

# STEP 4: Check for errors
agent-browser console
agent-browser errors

# STEP 5: If errors → fix and re-verify
# STEP 6: Only then → commit
```

### 2. What to check in snapshot output

**Element refs (@e1, @e2...):**
- Verify expected buttons/links exist
- Check element visibility (`:if` conditions working)
- Confirm elements have correct labels/text

**Console/errors:**
- No duplicate ID warnings
- No JavaScript errors
- Alpine.js warnings are usually OK (x-collapse)

### 3. Example verification flow

```bash
# After fixing session actions
agent-browser open http://localhost:4000/app/sessions
agent-browser snapshot -i

# Check snapshot shows:
# - "Draft" sessions have: View, Edit, Cancel buttons
# - "Scheduled" sessions have: View, Complete, Cancel buttons
# - Edit links point to /app/sessions/{id}/edit (full page)

agent-browser console  # Check for duplicate ID errors

# If OK → commit
```

### 4. Example: Testing a modal

```bash
agent-browser open http://localhost:4000/app/courses
agent-browser snapshot -i
# Find delete button ref (e.g., @e15)
agent-browser click @e15
agent-browser wait --text "Delete Course"
agent-browser snapshot -i  # Verify modal content
agent-browser screenshot delete-modal.png
```

## Checklist before committing UI changes

- [ ] Did I run `agent-browser open` to navigate to the affected page?
- [ ] Did I run `agent-browser snapshot -i` to verify elements?
- [ ] Did I run `agent-browser console` to check for errors?
- [ ] Are all conditional elements rendering correctly?
- [ ] Do all links/buttons have correct labels and actions?

## ❌ WHAT IS FORBIDDEN

- Committing UI changes without `agent-browser` verification
- Assuming code compiles = UI works
- Skipping verification "because it's a small change"
- Ignoring duplicate ID warnings in console

## ✅ WHAT IS EXPECTED

- Verify EVERY UI change with `agent-browser`
- Use `screenshot` for important states when debugging
- Check both `snapshot -i` AND `console`/`errors`
- Re-verify after each fix iteration
