# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Warlock is a Node.js/Express web app for managing a fleet of Linux game server hosts from a single UI. It communicates with remote hosts exclusively via SSH (as root), using a standardized `manage.py` CLI contract for each supported game.

## Commands

```bash
npm run dev    # Development with nodemon (auto-restart)
npm start      # Production

# Run individual tests
node tests/test_get_installer.mjs
python3 tests/test_base_config.py
python3 tests/test_unreal_config.py
```

There is no linter configured.

## Local Development (Vagrant)

A `Vagrantfile` is included for a self-contained Linux dev environment on Windows.

```bash
vagrant up                           # First run: provisions Ubuntu 24.04, installs Node, runs npm install, creates .env
vagrant ssh                          # Shell into the VM
cd /vagrant && npm run dev           # Start Warlock with nodemon
```

Browse to `http://localhost:3077` from Windows. The first visit redirects to `/install` to create an admin user.

The VM mounts the project root at `/vagrant`. Edits made on Windows are reflected immediately; nodemon handles restarts. `node_modules/` and `warlock.sqlite` are created inside the VM at `/vagrant/` — they will appear on the Windows filesystem but are already gitignored.

If nodemon does not detect file changes (a known issue with some hypervisor synced folders), add `-L` (legacy polling) to the dev script in `package.json`:
`"dev": "NODE_ENV=development nodemon -L app.js"`

To re-run provisioning after pulling changes that affect dependencies:
```bash
vagrant provision
```

## Architecture

### Request Flow

```
Browser → EJS view (server-rendered) → routes/*.js (UI pages)
                                     → routes/api/*.js (JSON endpoints)
                                              ↓
                                     libs/cmd_runner.mjs or cmd_streamer.mjs
                                              ↓
                              SSH as root@<host> (or direct exec for localhost)
                                              ↓
                                     <app_path>/manage.py <args>
```

### Key Patterns

**SSH execution** — all remote operations go through two libraries:
- `libs/cmd_runner.mjs`: one-shot commands; returns `{stdout, stderr}`; verifies the host exists in the DB first; uses direct `exec()` for `localhost`/`127.0.0.1`
- `libs/cmd_streamer.mjs`: long-running commands streamed as Server-Sent Events; format is `stdout: <line>` / `stderr: <line>`, ending with `event: done` or `event: error`

**Application discovery** — `libs/get_all_applications.mjs` reads `Apps.yaml` for the list of supported games, then for each registered host runs a shell glob to find installed `.app` marker files at `/var/lib/warlock/*.app`. Results are cached for 1 day via `libs/cache.mjs`.

**Game management contract** — each game's installer repo must provide `manage.py` with a standard CLI (see `docs/Management API.md`). Key flags: `--get-services` (JSON), `--get-configs` (JSON), `--set-config KEY VALUE`, `--backup`, `--check-update`, `--update`. Service-specific variants add `--service <name>`.

**Adding a new game** — add an entry to `Apps.yaml` with a `guid`, `source: github`, `repo`, `installer` path, and `syntax` list. No code changes required; Warlock discovers it automatically.

**Metrics pipeline** — `tasks/metrics_poll.mjs` runs every 60s collecting per-service metrics, `tasks/metrics_merge.mjs` runs hourly aggregating them into the `Metric` table (Sequelize/SQLite).

**Authentication** — `libs/validate_session.mjs` is middleware applied to all protected routes. Set `SKIP_AUTHENTICATION=true` in `.env` to bypass for local dev. 2FA via TOTP can be bypassed separately with `SKIP_2FA=true`.

### File Organization

| Path | Purpose |
|------|---------|
| `app.js` | Entry point; mounts all routes, starts background tasks |
| `db.js` | Sequelize models: `User`, `Host`, `Meta`, `Metric` |
| `Apps.yaml` | Master list of supported games |
| `routes/*.js` | EJS page handlers |
| `routes/api/*.js` | JSON API endpoints |
| `libs/` | Shared utilities (SSH, auth, caching, discovery) |
| `tasks/` | Background scheduled tasks |
| `views/` | EJS templates; `views/partials/` has nav and theme selector |
| `tests/` | Integration tests (Python config parsers + Node installer test) |

### Environment Variables (`.env`)

| Variable | Default | Notes |
|----------|---------|-------|
| `PORT` | `3077` | |
| `IP` | `127.0.0.1` | Bind address |
| `SESSION_SECRET` | `warlock_secret_key` | Override in production |
| `SKIP_AUTHENTICATION` | — | Set to `true` to skip login |
| `SKIP_2FA` | — | Set to `true` to skip 2FA |
| `NODE_ENV` | — | Set to `development` for debug logs |

## Code Style

Group related `const`/`let` declarations at the top of each function/block scope. Use a single `const` with comma-separated identifiers rather than scattering declarations throughout the function body.

API responses follow: `{ success: boolean, error?: string, data?: any }`

## Contribution Philosophy

The project authors explicitly rewrote the original AI-generated codebase because it was bloated and unmaintainable. Any changes intended for upstream contribution must be held to that standard. In practice:

- **Solve the stated problem only.** Do not refactor surrounding code, add abstractions for hypothetical reuse, or clean up style in files you aren't changing.
- **Follow existing patterns exactly.** New routes, libs, and tasks should look like the ones already there — same structure, same naming conventions, same level of complexity.
- **No defensive over-engineering.** Don't add extra validation, fallbacks, or error handling beyond what the existing codebase does for similar cases.
- **No new dependencies** unless clearly unavoidable. The current `package.json` is intentionally lean.
- **Small, readable diffs.** A reviewer should be able to understand a change in one pass. If a PR would be hard to review, it should be split or simplified.

The goal is changes that look like they were written by the same careful human developer who maintains this project — not changes that look like they were generated.
