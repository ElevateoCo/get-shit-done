<purpose>
Autonomously provision every external tool/service a project needs BEFORE implementation starts. Classifies each service by how it can be configured (Infisical secret already present / Composio MCP toolkit / CLI / Playwright browser automation / requires-user-credential / truly-manual), resolves as many as possible without the user, batches the rest into a single ask, then produces a TOOL-VERIFICATION.md gate that must be 100% PASS before /gsd:execute-phase runs.

Inspired by M2C1's Phase 5/6, but Elevateo-aware: it leverages the existing Infisical vault (claude-dev/dev @ secrets.elevateoco.com, 300+ secrets in folders) and the Composio MCP (server arnis-claude-code-multi, ~17 ACTIVE toolkits) so known services resolve to $0 manual work.
</purpose>

<process>

## Step 0: Resolve Model Profile

@~/.claude/get-shit-done/references/model-profile-resolution.md

Resolve model for: `gsd-phase-researcher` (reused for tool research).

## Step 1: Load project context

```bash
INIT=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" init phase-op "")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
# Extract: requirements_path, project_path (PROJECT.md), state_path, planning_dir
```

Read `PROJECT.md` + `REQUIREMENTS.md` (and any `.planning/research/*.md`). Build the **service list**: every external API, SaaS, DB, auth provider, payment processor, email sender, analytics, storage, AI provider, deploy target the project will touch. Infer from the stack (e.g. "Next.js + Supabase + Stripe checkout + Resend emails + deploy to Vercel" → supabase, stripe, resend, vercel, plus likely sentry/posthog if mentioned).

If no service list can be derived, ask the user one question: "Which external services will this project use?" and proceed.

## Step 1.5: Resource & capability discovery (check what we ALREADY have)

Before classifying services or planning ANY build-from-scratch work, inventory existing capabilities so the project reuses them instead of reinventing. Check all five sources and record matches:

**a) Local Claude Code skills** (~318 installed)
```bash
ls -d ~/.claude/skills/*/ | xargs -n1 basename
```
Match the project's domains against skill names/descriptions (e.g. a UGC project → `ad-creative-director`; a docs task → document-skills; UI → `ui-ux-pro-max`/`frontend-design`). Note which skills the execution agents should invoke.

**b) Configured MCP servers**
```bash
python3 -c "import json;print('\n'.join(json.load(open('$HOME/.claude.json')).get('mcpServers',{}).keys()))"
```
(composio-sweetlife, supabase, cloudflare-dns, brightdata, context7, graphify-brain, obsidian, chrome-devtools, telegram-mcp …). If the project needs a capability one of these already covers, use it.

**c) Local tool scripts** — `ls ~/.claude/tools/` (brain-writer, higgsfield, perplexity, vercel, transcribe, cloudflare-dns-mcp …).

**d) claude-stack catalog** — `~/Work/Github/claude-stack/catalog.json` (81 entries: Claude Code tools/skills/plugins/MCPs, tiered ACTIVE/SANDBOX/INDEXED/DROPPED + license + category).
```bash
python3 -c "import json;[print(f\"{e['tier']:>2} {e.get('layer','')[:8]:8} {e['name']:30} {e.get('category','')}\") for e in json.load(open('$HOME/Work/Github/claude-stack/catalog.json'))]" 2>/dev/null
```
Prefer TIER-3/ACTIVE entries. Surface relevant SANDBOX/INDEXED ones as "could adopt for this project." NEVER recommend a DROPPED (tier 0) entry — it was already rejected; check `why_status`.

**e) Resources code-catalog** — `~/Work/Resources/CATALOG.json` (306 templates/boilerplates/SaaS starters with `stack`/`database`/`auth`/`categories`/`localPath`). This is the **start-from-boilerplate** source.
```bash
python3 -c "import json;d=json.load(open('$HOME/Work/Resources/CATALOG.json'));[print(f\"{r['name'][:40]:40} stack={r.get('stack')} db={r.get('database')} local={r.get('localPath')}\") for r in d['resources']]" 2>/dev/null | grep -iE "<project-stack-keywords>"
```
If a boilerplate matches the project's stack (e.g. Next.js + Supabase + Stripe SaaS starter), recommend cloning/starting from its `localPath` rather than scaffolding from zero.

**Staleness caveat:** the Resources catalog `lastUpdated` may be months old (check `metadata`/`lastUpdated`) and claude-stack stars can be inflated — judge entries on license + maintenance + fit, not stars (see reference_ecosystem_star_gaming). Flag if a matched resource looks abandoned.

Record findings in a **Capability Reuse** block that feeds both the verification report and `/gsd:plan-phase`:
- skills to invoke · MCP servers to use · tools to call · stack tools to adopt · boilerplate to start from.

## Step 2: Classify each service

For each service, assign exactly one TIER (check in this order — stop at first match):

1. **INFISICAL-HAVE** — secret already exists in the vault. Check:
   ```bash
   # list folders and grep names (NEVER print values)
   infisical secrets --recursive --path=/ --projectId=5c0c4346-3c12-4ccd-9c36-a2262eab9987 \
     --env=dev --domain=https://secrets.elevateoco.com 2>/dev/null \
     | grep -iE "<service-keyword>"
   ```
   If a matching key exists → record its path. No user action.

2. **COMPOSIO-WIRED** — an ACTIVE Composio connection exists. Check:
   ```bash
   /usr/bin/curl -s -H "X-API-Key: $(infisical secrets get COMPOSIO_API_KEY --path=/personal --projectId=5c0c4346-3c12-4ccd-9c36-a2262eab9987 --env=dev --domain=https://secrets.elevateoco.com --plain --silent)" \
     "https://backend.composio.dev/api/v3/connected_accounts?limit=100" \
     | python3 -c "import json,sys; [print(a['toolkit']['slug']) for a in json.load(sys.stdin).get('items',[]) if a.get('status')=='ACTIVE']"
   ```
   If the service's toolkit is ACTIVE → agent can call it via the `composio-sweetlife` MCP. No user action.

3. **COMPOSIO-AVAILABLE** — a Composio toolkit exists but isn't connected. Check `GET /api/v3/toolkits/<slug>`. If API_KEY mode AND we have the key in Infisical → auto-create auth_config + connection (see references/composio-wire.md). If OAuth-only → queue a click.

4. **CLI** — service has a CLI the agent can drive headlessly (gh, vercel, supabase, gcloud, stripe, wrangler, resend, eas, infisical). Verify installed (`command -v`). Agent provisions directly.

5. **PLAYWRIGHT** — no API/CLI for the needed setup, but the dashboard is automatable with stored login (requires Playwright MCP + a saved storage_state). Flag for browser automation.

6. **USER-CRED** — agent needs a key only the user can mint (new API key from a dashboard). Batch into one ask.

7. **MANUAL** — no API at all (e.g. Microsoft Clarity, domain verification, app-store review). Document the manual steps; do NOT block on them unless the phase strictly needs them.

## Step 3: Auto-resolve everything resolvable

In dependency order, without pausing for the user:
- **INFISICAL-HAVE / COMPOSIO-WIRED** → write the reference into the project's `.env` as an `infisical run` injection (preferred) or note the Composio toolkit. Never copy raw secret values into the repo.
- **COMPOSIO-AVAILABLE (API_KEY + key in vault)** → wire it now via the Composio API.
- **CLI** → run the provisioning commands (create project, link, set env, etc.). Capture output.

Preferred .env pattern (no plaintext secrets in repo):
```
# .env.example committed; real values injected at runtime via:
#   infisical run --projectId=5c0c4346-3c12-4ccd-9c36-a2262eab9987 --env=dev \
#     --domain=https://secrets.elevateoco.com --path=/projects/<name> -- <command>
```

## Step 4: Batch the user asks

Collect ALL remaining USER-CRED and OAuth-click items into ONE message:
- For each: service, exactly what's needed (e.g. "Stripe restricted key with charges:write"), and where to get it (dashboard URL).
- For OAuth clicks: generate all Composio link URLs first (`POST /api/v3/connected_accounts/link`), present them together.
- Tell the user to paste new keys back; on receipt, store them in Infisical under `/projects/<name>/` (NOT the repo), then continue.

Do not trickle one ask at a time — one batch.

## Step 5: Verify every tool

For each provisioned service, run a cheap read-only check (list/me/ping) and record PASS/FAIL. Examples:
- supabase: `supabase projects list`
- vercel: `vercel projects ls`
- stripe: `stripe products list --limit 1`
- resend (Composio): call `RESEND_*` list tool via MCP
- any Composio toolkit: call its lightest list/get tool with the project's user_id
- generic API key: a documented GET endpoint

Write results to `.planning/TOOL-VERIFICATION.md` from the template:
@~/.claude/get-shit-done/templates/tool-verification.md

## Step 6: Gate

If any REQUIRED service is FAIL → stop and report. `/gsd:execute-phase` should refuse to start until TOOL-VERIFICATION.md shows all required tools PASS (MANUAL items may be deferred if the phase doesn't need them).

Update project state:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state update tool-setup-complete true 2>/dev/null || true
```

Report a concise summary: resolved-without-user / wired-now / awaiting-user / manual-deferred, and the verification table.

</process>

<elevateo_notes>
- Infisical: project `claude-dev` = `5c0c4346-3c12-4ccd-9c36-a2262eab9987`, env `dev`, domain `https://secrets.elevateoco.com`. Folders: /personal /team /vps /projects/<name> /oauth /tools /recovery /litellm. Per-project secrets live under `/projects/<name>/`.
- Composio MCP server: `arnis-claude-code-multi` id `0fb0df7b-9260-4c77-817b-728d81535636`, API key in Infisical at `/personal/COMPOSIO_API_KEY`. MCP exposed as `composio-sweetlife` in ~/.claude.json.
- Full service catalog + per-service tier: [[apps-and-connections-inventory]] in Claude-Brain/infra/.
- Services with NO Composio toolkit (use CLI/SDK directly): Higgsfield, FASHN, Fal, ElevenLabs, VAPI, Plaid, PayPal, Neon, Tinybird, Upstash, Bunny, Amadeus, MLS Grid, DocuSign, Sentry.
- HUMAN-ONLY (never block on): Microsoft Clarity, TailAdmin license, LinkedIn Sales Navigator.
</elevateo_notes>
</output>
