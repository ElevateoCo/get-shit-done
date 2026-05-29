---
phase: {N}
status: pending
analyzed: {YYYY-MM-DDTHH:MM:SSZ}
gates_total: 0
gates_pre: 0
gates_mid: 0
gates_post: 0
---

# Phase {N}: {Name} — Human Gate Map

> Pre-computed at planning time. Executor checks this file before spawning wave agents.
> Autonomous mode checks this file before calling plan-phase/execute-phase for this phase.

## Pre-Execution Gates (must be done BEFORE wave 1)

None

<!-- Example:
- [ ] GATE-01 | type: human-action | Create Stripe restricted API key with webhook:read scope | estimated: 5min
  > Instructions: platform.stripe.com → Developers → API keys → Create restricted key
  > Unblocks: plans 01-02, 01-03
-->

## Mid-Execution Gates (checkpoint:human-action inside a plan)

None

<!-- Example:
- [ ] GATE-02 | type: human-action | Click email verification link for SendGrid subuser | estimated: 2min
  > Plan: 01-04, task 3
-->

## Post-Execution Gates (sign-off before phase marked complete)

None

<!-- Example:
- [ ] GATE-03 | type: human-verify | Visual approval of payment flow in staging | estimated: 10min
  > Scope: checkout → payment confirmation → receipt email
-->

## Planner Instruction

Read this file before creating plans for Phase {N}.
Do NOT create tasks for items listed as GATE-* above.
Reference the gate ID instead (e.g., "Requires GATE-01 — see HUMAN-GATES.md").
This prevents duplicate effort and ensures human-required steps are surfaced to the user
up front rather than discovered mid-wave.
