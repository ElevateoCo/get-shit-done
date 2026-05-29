---
name: gsd:tool-setup
description: Autonomously provision every external tool/service a project needs before implementation starts
argument-hint: ""
allowed-tools:
  - Read
  - Bash
  - Write
  - Agent
  - AskUserQuestion
requires: [config, new-project]
---

<context>
Provisions every external service a project needs — Infisical secrets, Composio MCP toolkits, CLI tools — and produces a TOOL-VERIFICATION.md gate before /gsd:execute-phase runs.
</context>

<objective>
Provision and verify all external tools/services for the project.

**Creates:**
- `.planning/TOOL-VERIFICATION.md` — verification gate for all external services

**After this command:** Run `/gsd:plan-phase 1` to start planning.
</objective>

<execution_context>
@~/.claude/get-shit-done/workflows/tool-setup.md
@~/.claude/get-shit-done/references/model-profile-resolution.md
@~/.claude/get-shit-done/references/composio-wire.md
@~/.claude/get-shit-done/templates/tool-verification.md
</execution_context>

<process>
Execute end-to-end.
Preserve all workflow gates (classification, auto-resolve, batch user ask, verification, state update).
</process>
</content>
