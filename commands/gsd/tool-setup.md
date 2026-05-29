---
name: gsd:tool-setup
description: Provision every external tool/service a project needs before implementation (Elevateo layer — Infisical + Composio aware)
argument-hint: ""
allowed-tools:
  - Read
  - Bash
  - Write
  - Agent
  - AskUserQuestion
requires: [config, new-project]
---
<runtime_note>
**Copilot (VS Code):** Use `vscode_askquestions` wherever this workflow calls `AskUserQuestion`. They are equivalent — `vscode_askquestions` is the VS Code Copilot implementation of the same interactive question API.
</runtime_note>

<context>
Elevateo-specific workflow. Classifies each service by how it can be configured, resolves
as many as possible without user interaction, batches the rest into a single ask, then
produces a TOOL-VERIFICATION.md gate. See workflow for full detail.
</context>

<objective>
Provision all external services for the project and write .planning/TOOL-VERIFICATION.md.
All REQUIRED services must show PASS before /gsd:execute-phase can run.
</objective>

<execution_context>
@~/.claude/get-shit-done/workflows/tool-setup.md
@~/.claude/get-shit-done/references/composio-wire.md
@~/.claude/get-shit-done/templates/tool-verification.md
</execution_context>

<process>
Execute end-to-end.
Preserve all workflow gates (verification, user batches, state update).
</process>
