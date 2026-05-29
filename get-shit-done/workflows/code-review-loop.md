<purpose>
Dual-reviewer request→receive→address→re-review loop at phase boundary. Spawns both gsd-code-reviewer and gsd-ecc-code-reviewer on the phase diff, merges their findings, applies fixes via gsd-code-fixer, and re-reviews until clean or N rounds complete. Records outcome in REVIEW-LOOP.md.

Optional and non-blocking: exits gracefully if scope is empty, config gate is disabled, or no fixable issues remain after the first pass. Does not prevent phase completion.

Mirrors the superpowers requesting-code-review / receiving-code-review discipline:
- REQUEST: build file scope and spawn both reviewers
- RECEIVE: merge findings by severity, deduplicate overlapping issues
- ADDRESS: fix Critical/High findings; justify or defer lower-severity items
- VERIFY: re-review until both reviewers approve or max rounds reached

Max rounds: 3 (configurable via workflow.code_review_loop_max_rounds config key).
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<available_agent_types>
- gsd-code-reviewer: Adversarial code reviewer; produces REVIEW.md with BLOCKER/WARNING/INFO findings
- gsd-ecc-code-reviewer: ECC-adapted reviewer with Pre-Report Gate (>80% confidence only); emits zero false positives
- gsd-code-fixer: Applies fixes to review findings with atomic per-fix commits
</available_agent_types>

<process>

<step name="initialize">
Parse arguments and load project state:

```bash
PHASE_ARG="${1}"
INIT=$(gsd-sdk query init.phase-op "${PHASE_ARG}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Parse from init JSON: `phase_found`, `phase_dir`, `phase_number`, `phase_name`, `padded_phase`, `commit_docs`.

**Input sanitization:**
```bash
if ! [[ "$PADDED_PHASE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Error: Invalid phase number format: '${PADDED_PHASE}'. Expected digits (e.g., 02, 03.1)."
  exit 1
fi
```

**Phase validation:**
If `phase_found` is false:
```
Error: Phase ${PHASE_ARG} not found. Run /gsd:progress to see available phases.
```
Exit workflow.

Parse flags from $ARGUMENTS:
```bash
DEPTH_OVERRIDE=""
FILES_OVERRIDE=""
FIX_ALL=false
for arg in "$@"; do
  case "$arg" in
    --depth=*) DEPTH_OVERRIDE="${arg#--depth=}" ;;
    --files=*) FILES_OVERRIDE="${arg#--files=}" ;;
    --all)     FIX_ALL=true ;;
  esac
done

if [ "$FIX_ALL" = "true" ]; then FIX_SCOPE="all"; else FIX_SCOPE="critical_warning"; fi
```

Compute artifact paths:
```bash
REVIEW_PATH="${PHASE_DIR}/${PADDED_PHASE}-REVIEW.md"
ECC_REVIEW_PATH="${PHASE_DIR}/${PADDED_PHASE}-ECC-REVIEW.md"
LOOP_REPORT_PATH="${PHASE_DIR}/${PADDED_PHASE}-REVIEW-LOOP.md"
FIX_REPORT_PATH="${PHASE_DIR}/${PADDED_PHASE}-REVIEW-FIX.md"
```

Read max rounds from config:
```bash
MAX_ROUNDS=$(gsd-sdk query config-get workflow.code_review_loop_max_rounds 2>/dev/null || echo "3")
if ! [[ "$MAX_ROUNDS" =~ ^[0-9]+$ ]] || [ "$MAX_ROUNDS" -lt 1 ] || [ "$MAX_ROUNDS" -gt 10 ]; then
  MAX_ROUNDS=3
fi
```
</step>

<step name="check_config_gate">
Check if code review is enabled:

```bash
CODE_REVIEW_ENABLED=$(gsd-sdk query config-get workflow.code_review 2>/dev/null || echo "true")
```

If CODE_REVIEW_ENABLED is "false":
```
Code review loop skipped (workflow.code_review=false in config).
To enable: /gsd:config workflow.code_review true
```
Exit workflow (non-blocking).
</step>

<step name="resolve_depth">
```bash
if [ -n "$DEPTH_OVERRIDE" ]; then
  REVIEW_DEPTH="$DEPTH_OVERRIDE"
else
  CONFIG_DEPTH=$(gsd-sdk query config-get workflow.code_review_depth 2>/dev/null || echo "")
  REVIEW_DEPTH="${CONFIG_DEPTH:-standard}"
fi

case "$REVIEW_DEPTH" in
  quick|standard|deep) ;;
  *) echo "Warning: Invalid depth '${REVIEW_DEPTH}'. Defaulting to 'standard'."; REVIEW_DEPTH="standard" ;;
esac
```
</step>

<step name="compute_file_scope">
Reuse the same three-tier scoping logic as code-review.md (--files > SUMMARY.md > git diff).

If FILES_OVERRIDE is set, split by comma into REVIEW_FILES array. Otherwise extract from SUMMARY.md key_files sections; fall back to git diff scoped to the phase commits.

Apply standard exclusions (.planning/, lock files, generated files). Filter deleted files. Deduplicate. Warn if scope > 50 files.

If REVIEW_FILES is empty after filtering:
```
No source files changed in phase ${PHASE_ARG}. Skipping review loop.
```
Exit workflow (non-blocking).
</step>

<step name="request_phase">
**REQUEST — spawn both reviewers in sequence.**

This mirrors the superpowers requesting-code-review discipline: give each reviewer full context, explicit file scope, and the same depth setting.

Build shared config fragments:
```bash
FILES_LIST=""
for file in "${REVIEW_FILES[@]}"; do
  FILES_LIST+="  - ${file}\n"
done
```

Compute DIFF_BASE for agent context:
```bash
PHASE_COMMITS=$(git log --oneline --all --grep="${PADDED_PHASE}" --format="%H" 2>/dev/null)
if [ -n "$PHASE_COMMITS" ]; then
  DIFF_BASE=$(echo "$PHASE_COMMITS" | tail -1)^
  git rev-parse "${DIFF_BASE}" >/dev/null 2>&1 || DIFF_BASE=$(echo "$PHASE_COMMITS" | tail -1)
else
  DIFF_BASE=""
fi
```

Display progress header:
```
═══════════════════════════════════════════════════════════════
  Code Review Loop: Phase ${PHASE_NUMBER} (${PHASE_NAME})
  Depth: ${REVIEW_DEPTH}   Max rounds: ${MAX_ROUNDS}
───────────────────────────────────────────────────────────────
  Round 1/${MAX_ROUNDS} — spawning reviewers...
═══════════════════════════════════════════════════════════════
```

**Spawn gsd-code-reviewer (adversarial):**

```
Agent(subagent_type="gsd-code-reviewer", prompt="
<files_to_read>
${FILES_LIST}
</files_to_read>

<config>
depth: ${REVIEW_DEPTH}
phase_dir: ${PHASE_DIR}
review_path: ${REVIEW_PATH}
${DIFF_BASE:+diff_base: ${DIFF_BASE}}
files:
${FILES_LIST}
</config>

Review the listed source files at ${REVIEW_DEPTH} depth. Write findings to ${REVIEW_PATH}. Do NOT commit — orchestrator handles that.
")
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Wait for the subagent result before spawning the ECC reviewer.

**Spawn gsd-ecc-code-reviewer (confidence-gated):**

```
Agent(subagent_type="gsd-ecc-code-reviewer", prompt="
Review the following source files at ${REVIEW_DEPTH} depth using your Pre-Report Gate discipline.
Write findings to ${ECC_REVIEW_PATH} in the same REVIEW.md format (YAML frontmatter + severity sections).
Do NOT commit — orchestrator handles that.

Files to review:
${FILES_LIST}

Output path: ${ECC_REVIEW_PATH}
Phase dir: ${PHASE_DIR}
Depth: ${REVIEW_DEPTH}
")
```

> **ORCHESTRATOR RULE — CODEX RUNTIME**: After calling Agent() above, stop working on this task immediately. Wait for the subagent result before proceeding to the receive phase.
</step>

<step name="receive_phase">
**RECEIVE — merge findings from both reviewers.**

This mirrors the superpowers receiving-code-review discipline: read both reports, combine findings, deduplicate overlapping issues (same file + line range → keep the higher-severity entry), and build a merged REVIEW.md that becomes the working artifact for the fix step.

```bash
# Parse finding counts from both reviews
ADVERSARIAL_STATUS="clean"
ECC_STATUS="clean"

if [ -f "${REVIEW_PATH}" ]; then
  FM=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${REVIEW_PATH}', 'utf-8');
    const m = c.match(/^---\n([\s\S]*?)\n---/);
    if (m) process.stdout.write(m[1]);
  " 2>/dev/null)
  ADVERSARIAL_STATUS=$(echo "$FM" | grep "^status:" | cut -d: -f2 | xargs)
  ADV_CRITICAL=$(echo "$FM" | grep -E "^[[:space:]]*(critical|blocker):" | head -1 | cut -d: -f2 | xargs)
  ADV_WARNING=$(echo "$FM" | grep "warning:" | head -1 | cut -d: -f2 | xargs)
fi

if [ -f "${ECC_REVIEW_PATH}" ]; then
  FM_ECC=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${ECC_REVIEW_PATH}', 'utf-8');
    const m = c.match(/^---\n([\s\S]*?)\n---/);
    if (m) process.stdout.write(m[1]);
  " 2>/dev/null)
  ECC_STATUS=$(echo "$FM_ECC" | grep "^status:" | cut -d: -f2 | xargs)
  ECC_CRITICAL=$(echo "$FM_ECC" | grep -E "^[[:space:]]*(critical|blocker):" | head -1 | cut -d: -f2 | xargs)
  ECC_WARNING=$(echo "$FM_ECC" | grep "warning:" | head -1 | cut -d: -f2 | xargs)
fi

echo "  Adversarial reviewer: ${ADVERSARIAL_STATUS} (Critical: ${ADV_CRITICAL:-0}, Warning: ${ADV_WARNING:-0})"
echo "  ECC reviewer:         ${ECC_STATUS} (Critical: ${ECC_CRITICAL:-0}, Warning: ${ECC_WARNING:-0})"
```

**Merge logic:** If both reviewers returned clean, skip the address phase — no fixes needed. Otherwise, create a merged view by appending ECC findings to REVIEW.md under a `## ECC Reviewer Findings` section header so the fixer agent sees all issues in one document.

```bash
MERGED_STATUS="clean"
if [ "${ADVERSARIAL_STATUS}" != "clean" ] || [ "${ECC_STATUS}" != "clean" ]; then
  MERGED_STATUS="issues_found"
fi

if [ "${ECC_STATUS}" = "issues_found" ] && [ -f "${ECC_REVIEW_PATH}" ]; then
  # Append ECC body (strip frontmatter) into REVIEW.md under a clear section header
  ECC_BODY=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${ECC_REVIEW_PATH}', 'utf-8');
    // Strip YAML frontmatter
    const body = c.replace(/^---\n[\s\S]*?\n---\n/, '').trim();
    process.stdout.write(body);
  " 2>/dev/null)
  
  if [ -n "$ECC_BODY" ]; then
    printf '\n\n---\n\n## ECC Reviewer Findings (gsd-ecc-code-reviewer)\n\n%s\n' "$ECC_BODY" >> "${REVIEW_PATH}"
    # Update the frontmatter status to reflect merged state
    node -e "
      const fs = require('fs');
      let c = fs.readFileSync('${REVIEW_PATH}', 'utf-8');
      c = c.replace(/^(---\n[\s\S]*?)status:\s*\S+(.*?\n---)/m, '\$1status: issues_found\$2');
      fs.writeFileSync('${REVIEW_PATH}', c);
    " 2>/dev/null || true
  fi
fi
```
</step>

<step name="address_phase">
**ADDRESS — fix findings. Skip if both reviewers returned clean.**

```bash
if [ "${MERGED_STATUS}" = "clean" ]; then
  echo ""
  echo "✓ Both reviewers approved. No fixes needed."
  # Jump to record_outcome
else
  echo ""
  echo "Applying fixes (round 1/${MAX_ROUNDS})..."
  
  Agent(subagent_type="gsd-code-fixer", prompt="
<files_to_read>
${REVIEW_PATH}
</files_to_read>

<config>
phase_dir: ${PHASE_DIR}
padded_phase: ${PADDED_PHASE}
review_path: ${REVIEW_PATH}
fix_scope: ${FIX_SCOPE}
fix_report_path: ${FIX_REPORT_PATH}
iteration: 1
</config>

Read REVIEW.md findings (including ECC Reviewer Findings section if present). Apply fixes for ${FIX_SCOPE} severity items. Commit each fix atomically. Write REVIEW-FIX.md. Do NOT commit REVIEW-FIX.md.
")
  # ORCHESTRATOR RULE — CODEX RUNTIME: After calling Agent() above, stop immediately. Wait for result.
fi
```
</step>

<step name="re_review_loop">
**RE-REVIEW — iterate until clean or MAX_ROUNDS reached.**

```bash
ROUND=1

while [ $ROUND -lt $MAX_ROUNDS ] && [ "${MERGED_STATUS}" != "clean" ]; do
  ROUND=$((ROUND + 1))
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  Round ${ROUND}/${MAX_ROUNDS} — re-reviewing..."
  echo "═══════════════════════════════════════════════════════════════"
  
  # Backup iteration artifacts, then reset so each round writes a fresh file
  cp "${REVIEW_PATH}" "${REVIEW_PATH%.md}.iter${ROUND}.md" 2>/dev/null || true
  [ -f "${ECC_REVIEW_PATH}" ] && cp "${ECC_REVIEW_PATH}" "${ECC_REVIEW_PATH%.md}.iter${ROUND}.md" 2>/dev/null || true
  # Truncate review files — round-N reviewer writes its own findings only
  printf "# Review — Round %s\n" "${ROUND}" > "${REVIEW_PATH}"
  printf "# ECC Review — Round %s\n" "${ROUND}" > "${ECC_REVIEW_PATH}"

  # Build files config for re-review
  FILES_CONFIG=""
  if [ ${#REVIEW_FILES[@]} -gt 0 ]; then
    FILES_CONFIG="files:"
    for f in "${REVIEW_FILES[@]}"; do FILES_CONFIG="${FILES_CONFIG}
  - ${f}"; done
  fi
  
  # Re-run adversarial reviewer
  Agent(subagent_type="gsd-code-reviewer", prompt="
<config>
depth: ${REVIEW_DEPTH}
phase_dir: ${PHASE_DIR}
review_path: ${REVIEW_PATH}
${FILES_CONFIG}
</config>

Re-review the phase at ${REVIEW_DEPTH} depth. Write findings to ${REVIEW_PATH}. Do NOT commit.
")
  # ORCHESTRATOR RULE — CODEX RUNTIME: After calling Agent() above, stop immediately. Wait for result.
  
  # Re-run ECC reviewer
  Agent(subagent_type="gsd-ecc-code-reviewer", prompt="
Re-review the following source files at ${REVIEW_DEPTH} depth using your Pre-Report Gate discipline.
Write findings to ${ECC_REVIEW_PATH}. Do NOT commit.

Files:
${FILES_LIST}

Output path: ${ECC_REVIEW_PATH}
Phase dir: ${PHASE_DIR}
Depth: ${REVIEW_DEPTH}
")
  # ORCHESTRATOR RULE — CODEX RUNTIME: After calling Agent() above, stop immediately. Wait for result.
  
  # Parse new statuses
  NEW_ADV_STATUS="clean"
  NEW_ECC_STATUS="clean"
  
  [ -f "${REVIEW_PATH}" ] && NEW_ADV_STATUS=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${REVIEW_PATH}', 'utf-8');
    const m = c.match(/^---\n[\s\S]*?\n---/);
    const fm = m ? m[0] : '';
    const s = fm.match(/status:\s*(\S+)/);
    process.stdout.write(s ? s[1] : 'unknown');
  " 2>/dev/null)
  
  [ -f "${ECC_REVIEW_PATH}" ] && NEW_ECC_STATUS=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${ECC_REVIEW_PATH}', 'utf-8');
    const m = c.match(/^---\n[\s\S]*?\n---/);
    const fm = m ? m[0] : '';
    const s = fm.match(/status:\s*(\S+)/);
    process.stdout.write(s ? s[1] : 'unknown');
  " 2>/dev/null)
  
  echo "  Adversarial: ${NEW_ADV_STATUS}   ECC: ${NEW_ECC_STATUS}"
  
  if [ "${NEW_ADV_STATUS}" = "clean" ] && [ "${NEW_ECC_STATUS}" = "clean" ]; then
    MERGED_STATUS="clean"
    echo ""
    echo "✓ Both reviewers approved after round ${ROUND}."
    break
  fi
  
  MERGED_STATUS="issues_found"
  
  # Merge ECC findings into REVIEW.md for next fix pass
  if [ "${NEW_ECC_STATUS}" = "issues_found" ] && [ -f "${ECC_REVIEW_PATH}" ]; then
    ECC_BODY=$(node -e "
      const fs = require('fs');
      const c = fs.readFileSync('${ECC_REVIEW_PATH}', 'utf-8');
      const body = c.replace(/^---\n[\s\S]*?\n---\n/, '').trim();
      process.stdout.write(body);
    " 2>/dev/null)
    if [ -n "$ECC_BODY" ]; then
      printf '\n\n---\n\n## ECC Reviewer Findings (round %s)\n\n%s\n' "$ROUND" "$ECC_BODY" >> "${REVIEW_PATH}"
    fi
  fi
  
  # Fix remaining issues
  echo ""
  echo "Applying fixes (round ${ROUND}/${MAX_ROUNDS})..."
  
  Agent(subagent_type="gsd-code-fixer", prompt="
<files_to_read>
${REVIEW_PATH}
</files_to_read>

<config>
phase_dir: ${PHASE_DIR}
padded_phase: ${PADDED_PHASE}
review_path: ${REVIEW_PATH}
fix_scope: ${FIX_SCOPE}
fix_report_path: ${FIX_REPORT_PATH}
iteration: ${ROUND}
</config>

Read REVIEW.md findings (including any ECC Reviewer Findings sections). Apply fixes for ${FIX_SCOPE} severity items. Commit each fix atomically. Overwrite REVIEW-FIX.md. Do NOT commit REVIEW-FIX.md.
")
  # ORCHESTRATOR RULE — CODEX RUNTIME: After calling Agent() above, stop immediately. Wait for result.
done

if [ $ROUND -ge $MAX_ROUNDS ] && [ "${MERGED_STATUS}" != "clean" ]; then
  echo ""
  echo "⚠ Reached max rounds (${MAX_ROUNDS}). Remaining issues documented — non-blocking."
fi
```
</step>

<step name="record_outcome">
**Write REVIEW-LOOP.md outcome record and commit.**

```bash
OUTCOME_STATUS="${MERGED_STATUS}"
OUTCOME_LABEL="APPROVED"
if [ "${MERGED_STATUS}" != "clean" ]; then
  OUTCOME_LABEL="ISSUES_REMAIN"
fi

# Compute next-steps sentence in bash (avoids JS ternary on shell-expanded value)
if [ "${OUTCOME_LABEL}" = "APPROVED" ]; then
  NEXT_STEPS="Both reviewers approved — phase may proceed."
else
  NEXT_STEPS="Issues remain after ${ROUND} rounds — review ${REVIEW_PATH} and address manually."
fi

# Write outcome record
node -e "
const fs = require('fs');
const ts = new Date().toISOString();
const content = [
  '---',
  'phase: ${PADDED_PHASE}',
  'loop_completed: ' + ts,
  'rounds_run: ${ROUND}',
  'max_rounds: ${MAX_ROUNDS}',
  'outcome: ${OUTCOME_LABEL}',
  'depth: ${REVIEW_DEPTH}',
  'reviewers: [gsd-code-reviewer, gsd-ecc-code-reviewer]',
  'adversarial_final: ${NEW_ADV_STATUS:-${ADVERSARIAL_STATUS}}',
  'ecc_final: ${NEW_ECC_STATUS:-${ECC_STATUS}}',
  '---',
  '',
  '# Code Review Loop Outcome — Phase ${PHASE_NUMBER}',
  '',
  '**Completed:** ' + ts,
  '**Rounds run:** ${ROUND} / ${MAX_ROUNDS}',
  '**Outcome:** ${OUTCOME_LABEL}',
  '',
  '## Reviewers',
  '',
  '- **gsd-code-reviewer** (adversarial): final status = ${NEW_ADV_STATUS:-${ADVERSARIAL_STATUS}}',
  '- **gsd-ecc-code-reviewer** (confidence-gated): final status = ${NEW_ECC_STATUS:-${ECC_STATUS}}',
  '',
  '## Artifacts',
  '',
  '- REVIEW.md (adversarial + merged ECC findings): \`${REVIEW_PATH}\`',
  '- ECC REVIEW: \`${ECC_REVIEW_PATH}\`',
  '- Fix log: \`${FIX_REPORT_PATH}\`',
  '',
  '## Next steps',
  '',
  '${NEXT_STEPS}',
].join(\"\n\");
fs.writeFileSync('${LOOP_REPORT_PATH}', content);
" 2>/dev/null

if [ -f "${LOOP_REPORT_PATH}" ] && [ "$COMMIT_DOCS" = "true" ]; then
  gsd-sdk query commit \
    "docs(${PADDED_PHASE}): add code review loop outcome report" \
    --files "${LOOP_REPORT_PATH}"
fi
```
</step>

<step name="present_results">
Display final summary:

```
═══════════════════════════════════════════════════════════════

  Code Review Loop Complete: Phase ${PHASE_NUMBER} (${PHASE_NAME})

───────────────────────────────────────────────────────────────

  Rounds:          ${ROUND} / ${MAX_ROUNDS}
  Depth:           ${REVIEW_DEPTH}
  Outcome:         ${OUTCOME_LABEL}

  Adversarial reviewer:  ${NEW_ADV_STATUS:-${ADVERSARIAL_STATUS}}
  ECC reviewer:          ${NEW_ECC_STATUS:-${ECC_STATUS}}

───────────────────────────────────────────────────────────────
```

If OUTCOME_LABEL is APPROVED:
```
✓ Both reviewers approved. Phase is ready to proceed.

Loop report: ${LOOP_REPORT_PATH}
```

If OUTCOME_LABEL is ISSUES_REMAIN:
```
⚠ Issues remain after ${ROUND} rounds. Phase completion is NOT blocked.
  Address remaining items or document justification in REVIEW.md.

Loop report:  ${LOOP_REPORT_PATH}
Review:       ${REVIEW_PATH}
Fix log:      ${FIX_REPORT_PATH}

To continue fixing manually:
  /gsd:code-review ${PHASE_NUMBER} --fix
```

═══════════════════════════════════════════════════════════════
</step>

</process>

<success_criteria>
- [ ] Phase validated before config gate
- [ ] Config gate respected (non-blocking exit on disabled)
- [ ] File scope computed via standard three-tier logic
- [ ] Both gsd-code-reviewer AND gsd-ecc-code-reviewer spawned (REQUEST)
- [ ] Findings merged — ECC findings appended to adversarial REVIEW.md (RECEIVE)
- [ ] gsd-code-fixer spawned to address merged findings (ADDRESS)
- [ ] Re-review loop runs until both reviewers clean or MAX_ROUNDS reached (VERIFY)
- [ ] Outcome recorded in REVIEW-LOOP.md
- [ ] Non-blocking: phase completion never prevented by this loop
- [ ] No duplicate command created (extends existing /gsd:code-review via --loop flag)
</success_criteria>
</output>
