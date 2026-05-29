<purpose>
Extract decisions, lessons learned, patterns discovered, and surprises encountered from completed phase artifacts into a structured LEARNINGS.md file. Captures institutional knowledge that would otherwise be lost between phases.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<objective>
Analyze completed phase artifacts (PLAN.md, SUMMARY.md, VERIFICATION.md, UAT.md, STATE.md) and extract structured learnings into 4 categories: decisions, lessons, patterns, and surprises. Each extracted item includes source attribution. The output is a LEARNINGS.md file with YAML frontmatter containing metadata about the extraction.
</objective>

<process>

<step name="initialize">
Parse arguments and load project state:

```bash
INIT=$(gsd-sdk query init.phase-op "${PHASE_ARG}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Parse from init JSON: `phase_found`, `phase_dir`, `phase_number`, `phase_name`, `padded_phase`.

If phase not found, exit with error: "Phase {PHASE_ARG} not found."
</step>

<step name="collect_artifacts">
Read the phase artifacts. PLAN.md and SUMMARY.md are required; VERIFICATION.md, UAT.md, and STATE.md are optional.

**Required artifacts:**
- `${PHASE_DIR}/*-PLAN.md` — all plan files for the phase
- `${PHASE_DIR}/*-SUMMARY.md` — all summary files for the phase

If PLAN.md or SUMMARY.md files are not found or missing, exit with error: "Required artifacts missing. PLAN.md and SUMMARY.md are required for learning extraction."

**Optional artifacts (read if available, skip if not found):**
- `${PHASE_DIR}/*-VERIFICATION.md` — verification results
- `${PHASE_DIR}/*-UAT.md` — user acceptance test results
- `.planning/STATE.md` — project state with decisions and blockers

Track which optional artifacts are missing for the `missing_artifacts` frontmatter field.
</step>

<step name="extract-learnings">
Analyze all collected artifacts and extract learnings into 4 categories:

### 1. Decisions
Technical and architectural decisions made during the phase. Look for:
- Explicit decisions documented in PLAN.md or SUMMARY.md
- Technology choices and their rationale
- Trade-offs that were evaluated
- Design decisions recorded in STATE.md

Each decision entry must include:
- **What** was decided
- **Why** it was decided (rationale)
- **Source:** attribution to the artifact where the decision was found (e.g., "Source: 03-01-PLAN.md")

### 2. Lessons
Things learned during execution that were not known beforehand. Look for:
- Unexpected complexity in SUMMARY.md
- Issues discovered during verification in VERIFICATION.md
- Failed approaches documented in SUMMARY.md
- UAT feedback that revealed gaps

Each lesson entry must include:
- **What** was learned
- **Context** for the lesson
- **Source:** attribution to the originating artifact

### 3. Patterns
Reusable patterns, approaches, or techniques discovered. Look for:
- Successful implementation patterns in SUMMARY.md
- Testing patterns from VERIFICATION.md or UAT.md
- Workflow patterns that worked well
- Code organization patterns from PLAN.md

Each pattern entry must include:
- **Pattern** name/description
- **When to use** it
- **Source:** attribution to the originating artifact

### 4. Surprises
Unexpected findings, behaviors, or outcomes. Look for:
- Things that took longer or shorter than estimated
- Unexpected dependencies or interactions
- Edge cases not anticipated in planning
- Performance or behavior that differed from expectations

Each surprise entry must include:
- **What** was surprising
- **Impact** of the surprise
- **Source:** attribution to the originating artifact
</step>

<step name="capture_thought_integration">
**What this step is:** `capture_thought` is an **optional convention**, not a bundled GSD tool. GSD does not ship one and does not require one. The step is a hook for users who run a memory / knowledge-base MCP server (for example ExoCortex-style servers, `claude-mem`, or `mem0`-style servers) that exposes a tool with this exact name. If any MCP server in the current session provides a `capture_thought` tool with the signature below, each extracted learning is routed through it with metadata. If no such tool is present, the step is a silent no-op — `LEARNINGS.md` is always the primary output.

**Detection:** Check whether a tool named `capture_thought` is available in the current session. Do not assume any specific MCP server is connected.

**If available**, call once per extracted learning:

```
capture_thought({
  category: "decision" | "lesson" | "pattern" | "surprise",
  phase: PHASE_NUMBER,
  content: LEARNING_TEXT,
  source: ARTIFACT_NAME
})
```

**If not available** (no MCP server in the session exposes this tool, or the runtime does not support it), skip the step silently and continue. The workflow must not fail or warn — this is expected behavior for users who do not run a knowledge-base MCP.
</step>

<step name="write_learnings">
Write the LEARNINGS.md file to the phase directory. If a previous LEARNINGS.md exists, overwrite it (replace the file entirely).

Output path: `${PHASE_DIR}/${PADDED_PHASE}-LEARNINGS.md`

The file must have YAML frontmatter with these fields:
```yaml
---
phase: {PHASE_NUMBER}
phase_name: "{PHASE_NAME}"
project: "{PROJECT_NAME}"
generated: "{ISO_DATE}"
counts:
  decisions: {N}
  lessons: {N}
  patterns: {N}
  surprises: {N}
missing_artifacts:
  - "{ARTIFACT_NAME}"
---
```

Individual items may carry an optional `graduated:` annotation (added by `graduation.md` when a cluster is promoted):
```markdown
**Graduated:** {target-file}:{ISO_DATE}
```
This annotation is appended after the item's existing fields and prevents the item from being re-surfaced in future graduation scans. Do not add this field during extraction — it is written only by the graduation workflow.

The body follows this structure:
```markdown
# Phase {PHASE_NUMBER} Learnings: {PHASE_NAME}

## Decisions

### {Decision Title}
{What was decided}

**Rationale:** {Why}
**Source:** {artifact file}

---

## Lessons

### {Lesson Title}
{What was learned}

**Context:** {context}
**Source:** {artifact file}

---

## Patterns

### {Pattern Name}
{Description}

**When to use:** {applicability}
**Source:** {artifact file}

---

## Surprises

### {Surprise Title}
{What was surprising}

**Impact:** {impact description}
**Source:** {artifact file}
```
</step>

<step name="update_state">
Update STATE.md to reflect the learning extraction:

```bash
gsd-sdk query state.update "Last Activity" "$(date +%Y-%m-%d)"
```
</step>

<step name="report">
```
---------------------------------------------------------------

## Learnings Extracted: Phase {X} — {Name}

Decisions:  {N}
Lessons:    {N}
Patterns:   {N}
Surprises:  {N}
Total:      {N}

Output: {PHASE_DIR}/{PADDED_PHASE}-LEARNINGS.md

Missing artifacts: {list or "none"}

Next steps:
- Review extracted learnings for accuracy
- /gsd:progress — see overall project state
- /gsd:execute-phase {next} — continue to next phase

---------------------------------------------------------------
```
</step>

<step name="continuous_learning_evolve">

**Self-improving loop: surface instinct clusters as skill promotion candidates.**

This step is **always non-blocking** — if the CLI is absent or no instincts have been captured yet, log a single line and continue.

### 1. Detect CLI path

```bash
# Prefer plugin-root install; fall back to manual install; skip if neither exists
INSTINCT_CLI=""
if [ -n "$CLAUDE_PLUGIN_ROOT" ] && \
   [ -f "${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py" ]; then
  INSTINCT_CLI="${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/scripts/instinct-cli.py"
elif [ -f "${HOME}/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py" ]; then
  INSTINCT_CLI="${HOME}/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py"
else
  echo "[evolve: instinct-cli not found — skipping continuous-learning step]"
  exit 0
fi

# Security: normalize path with realpath and require it to live under $HOME/.claude/
INSTINCT_CLI_REAL="$(realpath "$INSTINCT_CLI" 2>/dev/null)"
HOME_CLAUDE_REAL="$(realpath "${HOME}/.claude" 2>/dev/null)"
if [ -z "$INSTINCT_CLI_REAL" ] || \
   [ "${INSTINCT_CLI_REAL#"${HOME_CLAUDE_REAL}/"}" = "$INSTINCT_CLI_REAL" ]; then
  echo "[evolve: instinct-cli path is outside \$HOME/.claude/ — skipping for safety]"
  exit 0
fi
INSTINCT_CLI="$INSTINCT_CLI_REAL"
```

All remaining substeps (2–4) execute only when the block above completes without calling `exit 0` — i.e., only when `$INSTINCT_CLI` is set and its canonical path is confirmed to live under `$HOME/.claude/`.

### 2. Run status + evolve

```bash
python3 "$INSTINCT_CLI" status
python3 "$INSTINCT_CLI" evolve
```

Capture stdout. If either command exits non-zero (e.g. no instincts captured yet), log:
```
[evolve: no instincts captured yet — run more sessions to accumulate data]
```
and skip to the **Evolve candidates** report (show empty block).

### 3. Parse and surface candidates

From the `evolve` output, extract candidate entries. Each entry from `instinct-cli.py evolve` contains: name, type (`skill` | `command` | `agent`), trigger, and evidence-count.

Present to the user:

```
## Evolve candidates

| Name | Type | Trigger | Evidence |
|------|------|---------|----------|
| {name} | {type} | {trigger} | {N} instincts |
```

If the evolve output contains no candidates:
```
## Evolve candidates

[none — instinct clusters have not yet reached promotion threshold]
```

### 4. Adopt a candidate → propose a fork PR

For each candidate the user explicitly adopts (ask "Adopt any of the above? Enter name(s) or press Enter to skip"):

1. **Sanitize the name before writing.** Run `basename` on `{name}` to strip any directory components,
   then reject the result if it is empty, equals `.` or `..`, or contains `/` or `..` as a substring.
   If the name fails validation, log:
   ```
   [evolve: rejected unsafe skill name '{name}' — skipping]
   ```
   and skip that candidate. Only proceed with the basename-validated value as `{safe-name}`.

2. Write a draft skill definition to `skills/{safe-name}/SKILL.md` in the current repo (creating the directory if needed).

   The draft follows the standard GSD skill frontmatter:

   ```markdown
   ---
   name: {name}
   description: {one-line description derived from the instinct cluster}
   origin: continuous-learning-v2
   version: 0.1.0
   status: draft
   ---

   # {Name}

   ## Purpose

   {2-3 sentences summarising what was repeatedly observed across sessions.}

   ## When to activate

   {trigger from instinct-cli output}

   ## Evidence

   Based on {N} instincts captured across {M} sessions.

   ## Actions

   {List the concrete actions / patterns from the instinct cluster — drawn from `instinct-cli.py evolve` output. Do not fabricate; only include what the CLI reported.}

   ---
   *Draft generated by `/gsd:reflect` continuous-learning step. Review before merging.*
   ```

3. Note the file path and confirm to the user:
   ```
   Draft written: skills/{safe-name}/SKILL.md
   Open a PR for review — the catalog will index it after merge.
   ```

**BOUNDARY:** Do NOT auto-install, auto-merge, or push this skill anywhere. Do NOT write to `~/.claude/` or any path outside the current repo. The skill definition lives as a draft in this fork until a human-reviewed PR is merged.

</step>

</process>

<success_criteria>
- [ ] Phase artifacts located and read successfully
- [ ] All 4 categories extracted: decisions, lessons, patterns, surprises
- [ ] Each extracted item has source attribution
- [ ] LEARNINGS.md written with correct YAML frontmatter
- [ ] Missing optional artifacts tracked in frontmatter
- [ ] capture_thought integration attempted if tool available
- [ ] STATE.md updated with extraction activity
- [ ] User receives summary report
- [ ] continuous_learning_evolve step attempted (CLI absent or no instincts → silent skip)
- [ ] Adopted candidates written as draft skills/{name}/SKILL.md in this repo
</success_criteria>

<critical_rules>
- PLAN.md and SUMMARY.md are required — exit with clear error if missing
- VERIFICATION.md, UAT.md, and STATE.md are optional — extract from them if present, skip gracefully if not found
- Every extracted learning must have source attribution back to the originating artifact
- Running extract-learnings twice on the same phase must overwrite (replace) the previous LEARNINGS.md, not append
- Do not fabricate learnings — only extract what is explicitly documented in artifacts
- If capture_thought is unavailable, the workflow must not fail — graceful degradation to file-only output
- LEARNINGS.md frontmatter must include counts for all 4 categories and list any missing_artifacts
- continuous_learning_evolve is always non-blocking — CLI absent or zero instincts must not fail the workflow
- Adopted skill drafts are written ONLY inside this fork repo (skills/{name}/SKILL.md) — never to ~/.claude/ or outside the repo
- Do NOT auto-merge, auto-install, or push skill drafts — human PR review is required before catalog indexing
</critical_rules>
