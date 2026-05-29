---
type: Feature
---
**Adds three ECC-adapted review specialist agents (roadmap #5/#6)** — `ecc-security-reviewer` (proactive OWASP/secrets/injection new-vulnerability discovery, complements `gsd-security-auditor`), `ecc-code-reviewer` (ECC Pre-Report Gate: only >80%-confidence findings, zero-noise APPROVE/WARNING/BLOCK verdict), and `ecc-tdd-guide` (red-green-refactor enforcement, 80%+ coverage audit, eval-driven addendum for AI paths). All three agents are adapted to GSD format with GSD frontmatter, `<prompt_defense_baseline>` block, minimal read-only tools (Read/Grep/Glob/Bash-for-scans), and ECC MIT credit. INVENTORY.md and AGENTS.md updated (Agents count 38→41); agents-doc-parity and inventory-counts drift tests pass. ECC source: affaan-m/ECC — MIT License.
