---
type: Feature
---
**Specialist executor routing — four domain-specialist plan executors** — `gsd-executor-security`, `gsd-executor-ui`, `gsd-executor-perf`, and `gsd-executor-debug` extend the base executor contract with domain lenses (OWASP/a11y/hot-path/repro-first) and auto-apply missing domain controls via deviation Rule 2. The `execute-phase` orchestrator reads `executor_kind` from each plan's YAML frontmatter and routes to the correct specialist; plans without `executor_kind` continue to use `gsd-executor` unchanged. The `plan-phase` workflow includes an `executor_kind_heuristic` block so the planner automatically selects the right specialist based on first-match signal keywords in the plan scope.
