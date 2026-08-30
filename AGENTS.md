# AGENTS

Guidance for AI agents working in this repo (Omega).

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `mohmaedeslam00116/omega` (via `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) — each string equals its role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` at repo root + `docs/adr/` for decisions. See `docs/agents/domain.md`.

## Project

- **Repo:** https://github.com/mohmaedeslam00116/omega
- **Stack:** Node >=18, ESM, no monorepo
- **Skills:** 37 skills from `mattpocock/skills` installed via `skills-lock.json` (`.agents/skills/` + `.claude/skills/`)
- **Workflow:** `ask-matt` → `/grill-me` / `/to-spec` → `/to-tickets` → `/implement` → `/code-review` → `/triage`

## Conventions

- Use `gh` for issue tracker operations (see `docs/agents/issue-tracker.md` for commands)
- Use triage labels from `docs/agents/triage-labels.md`
- Read `CONTEXT.md` (when it exists) and relevant `docs/adr/*.md` before exploring code
- Single-context repo — no `CONTEXT-MAP.md`
