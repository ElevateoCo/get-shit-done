// GSD map-codebase — Workflow tool variant (PoC).
//
// WHY THIS EXISTS
// The existing map-codebase.md spawns 4 gsd-codebase-mapper agents via the Agent tool.
// That works, but the Agent tool is non-deterministic (context varies per session),
// non-resumable (if the orchestrator is interrupted the whole wave re-runs), and
// returns unstructured confirmations that the orchestrator must re-parse.
//
// A Workflow-tool implementation fixes all three:
//   • Deterministic  — structured-output schemas guarantee every mapper returns the
//                      same shape; the synthesizer always gets the same inputs.
//   • Resumable      — the Workflow runtime checkpoints each phase(); a crash mid-wave
//                      restarts only the failed agent, not the full map.
//   • Structured     — typed output surfaces directly in the Workflow result; no
//                      line-count parsing hacks needed.
//
// This is the FIRST step of the GSD-on-Workflow migration. It is additive — the
// existing map-codebase.md and its Agent-based flow remain unchanged. Once this
// variant is validated in production it will replace the Agent flow.
//
// USAGE
//   Run via the Workflow tool with args = { projectDir, focus? }.
//   focus defaults to 'all' (4 parallel mappers); pass 'tech|arch|quality|concerns'
//   for a single-focus fast run (mirrors --fast --focus in the CLI command).
//
// NOTE: illustrative reference (lives in get-shit-done/workflows/).
// Pass real values via `args`; do not hardcode paths.

// ── Output schemas ───────────────────────────────────────────────────────────

const MAPPER_RESULT = {
  type: 'object',
  required: ['focus', 'documents'],
  properties: {
    focus: { type: 'string', enum: ['tech', 'arch', 'quality', 'concerns'] },
    documents: {
      type: 'array',
      items: {
        type: 'object',
        required: ['filename', 'lineCount', 'summary'],
        properties: {
          filename: { type: 'string' },
          lineCount: { type: 'number' },
          summary: { type: 'string', description: '1-2 sentence summary of what was written' },
        },
      },
    },
  },
}

const CODEBASE_MAP = {
  type: 'object',
  required: ['projectDir', 'documentsWritten', 'keyFindings'],
  properties: {
    projectDir: { type: 'string' },
    documentsWritten: { type: 'array', items: { type: 'string' } },
    keyFindings: {
      type: 'object',
      properties: {
        stack: { type: 'string' },
        architecture: { type: 'string' },
        qualityNotes: { type: 'string' },
        topConcerns: { type: 'array', items: { type: 'string' } },
      },
    },
  },
}

// ── Config ───────────────────────────────────────────────────────────────────

export const meta = {
  name: 'gsd-map-codebase-workflow',
  description: 'Map codebase with parallel structured-output mappers (Workflow variant of map-codebase)',
  phases: [
    { title: 'Map', detail: 'parallel mapper agents — tech / arch / quality / concerns' },
    { title: 'Synthesize', detail: 'merge mapper results into .planning/codebase/ summary' },
  ],
}

// Sanitize: projectDir is interpolated into agent prompts + paths — reject traversal/abs escapes.
const _pd = (args && args.projectDir) || '.'
if (/(^|\/)\.\.(\/|$)/.test(_pd)) throw new Error(`unsafe projectDir: ${_pd}`)
const projectDir = _pd
const planningDir = `${projectDir}/.planning/codebase`
const focusFilter = (args && args.focus) || 'all'

const ALL_FOCUSES = ['tech', 'arch', 'quality', 'concerns']
const focuses = focusFilter === 'all' ? ALL_FOCUSES : [focusFilter]

// ── Map phase ────────────────────────────────────────────────────────────────

phase('Map')

const FOCUS_PROMPTS = {
  tech: `You are a gsd-codebase-mapper (tech focus).
Explore the codebase at ${projectDir}. Identify the language/framework stack, package manager,
key dependencies (with versions), build tools, test runner, and CI config.
Write your findings to ${planningDir}/STACK.md and ${planningDir}/INTEGRATIONS.md.
Return a MAPPER_RESULT with focus="tech" listing the two files written and their line counts.`,

  arch: `You are a gsd-codebase-mapper (arch focus).
Explore the codebase at ${projectDir}. Map the top-level directory structure, module/package
boundaries, entry points, and data-flow between major components (auth → API → DB → etc).
Write your findings to ${planningDir}/ARCHITECTURE.md and ${planningDir}/STRUCTURE.md.
Return a MAPPER_RESULT with focus="arch" listing the two files written and their line counts.`,

  quality: `You are a gsd-codebase-mapper (quality focus).
Explore the codebase at ${projectDir}. Document naming conventions, file organization patterns,
test coverage strategy, linting/formatting config, and any shared utilities/helpers worth reusing.
Write your findings to ${planningDir}/CONVENTIONS.md and ${planningDir}/TESTING.md.
Return a MAPPER_RESULT with focus="quality" listing the two files written and their line counts.`,

  concerns: `You are a gsd-codebase-mapper (concerns focus).
Explore the codebase at ${projectDir}. Flag technical debt, security surface areas, missing
tests, deprecated dependencies, and any other issues that planning agents should know about.
Write your findings to ${planningDir}/CONCERNS.md.
Return a MAPPER_RESULT with focus="concerns" listing the file written and its line count.`,
}

log(`Spawning ${focuses.length} mapper(s) in parallel: ${focuses.join(', ')}`)

const mapperResults = await parallel(
  focuses.map((focus) =>
    agent(FOCUS_PROMPTS[focus], {
      label: `map:${focus}`,
      phase: 'Map',
      schema: MAPPER_RESULT,
      model: 'sonnet',
    })
  )
)

// ── Synthesize phase ─────────────────────────────────────────────────────────

phase('Synthesize')

const allDocs = mapperResults.flatMap((r) => (r && r.documents ? r.documents.map((d) => d.filename) : []))

log(`Mapper results: ${mapperResults.length} agent(s) completed, ${allDocs.length} document(s) written`)

const synthesis = await agent(
  `You are a gsd-research-synthesizer.
The following codebase documents have been written to ${planningDir}:
${allDocs.map((f) => `  - ${f}`).join('\n')}

Read each document and:
1. Write a one-paragraph executive summary to ${planningDir}/SUMMARY.md covering stack, architecture, and top concerns.
2. Return a CODEBASE_MAP with projectDir="${projectDir}", documentsWritten=[array of all paths above plus SUMMARY.md],
   and keyFindings summarizing stack, architecture, qualityNotes, and topConcerns (max 3).`,
  {
    label: 'synthesize:codebase',
    phase: 'Synthesize',
    schema: CODEBASE_MAP,
    model: 'sonnet',
  }
)

return synthesis
