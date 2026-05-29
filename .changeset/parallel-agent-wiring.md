---
type: Added
---
**Parallel-agent + subagent-driven discipline wired into execute-phase and map-codebase (roadmap #8)** — `execute_waves` now references `superpowers:dispatching-parallel-agents` (for independent-plan fan-out within a wave) and `superpowers:subagent-driven-development` (for interdependent-plan sequential dispatch within a wave). `spawn_agents` in `map-codebase` now references `superpowers:dispatching-parallel-agents` for the 4-mapper concurrent fan-out. Additive guidance only — spawn mechanics, wave grouping, and agent contracts are unchanged.
