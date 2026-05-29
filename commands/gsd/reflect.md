---
name: gsd:reflect
description: Reflect on a completed phase — extract learnings and surface continuous-learning instinct clusters as skill promotion candidates
argument-hint: <phase-number>
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
  - Glob
  - Agent
type: prompt
requires: [phase]
---
<objective>
Run the full reflect workflow for a completed phase: extract decisions, lessons, patterns, and surprises into LEARNINGS.md, then surface any instinct clusters captured during this project's work as Evolve candidates that can be proposed as skill definitions via fork PR.
</objective>

<execution_context>
@~/.claude/get-shit-done/workflows/extract-learnings.md
</execution_context>

Execute the extract-learnings workflow from @~/.claude/get-shit-done/workflows/extract-learnings.md end-to-end, including the `continuous_learning_evolve` step at the end.
