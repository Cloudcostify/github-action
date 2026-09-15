# AGENTS.md

Canonical agent rules: `saas-factory-labs/SaaS-Factory@main/AGENTS.md`
(https://github.com/saas-factory-labs/SaaS-Factory/blob/main/AGENTS.md) — a
**private** repository. Requires authenticated GitHub access to
`saas-factory-labs/SaaS-Factory`.

## Required startup sequence

Before planning or implementing any change in this repository, an agent must:

1. Obtain authenticated GitHub access to `saas-factory-labs/SaaS-Factory`. If
   access is unavailable, fail closed and report the blocker before
   proceeding — do not plan or implement.
2. From `saas-factory-labs/SaaS-Factory@main`, read completely, in order:
   1. `AGENTS.md`
   2. `docs/agent-contract/shared-agent-rules.md`
   3. `docs/content/ai-rules/README.md`
   4. Only the baseline, backend, frontend, infrastructure, test,
      development-workflow, and documentation rule sections under
      `docs/content/ai-rules/` relevant to the task.
3. Classify the anticipated change against the mandatory review-gate routing
   table in `docs/content/ai-rules/development-workflow/review-gates.md`,
   then load and apply every triggered prompt under `docs/content/ai-prompts/`
   before writing production code. Record every canonical gate's status per
   the status contract defined in `review-gates.md`, with evidence, in the
   plan and pull request. Reclassify and apply any newly triggered prompts
   whenever the scope of the change changes.
4. Read this file completely. It narrows the canonical rules for this
   repository; it does not replace, duplicate, or weaken them. In particular,
   the canonical `AGENTS.md`'s build commands, source layout, and
   repository-ownership sections describe the SaaS-Factory repository itself
   and do not apply here — use the commands and layout below instead.
5. Read a nearer `AGENTS.md` below the target directory if one exists; it may
   add scoped constraints.
6. Inspect the current source and tests in this repository before proposing
   or making changes.

If the private repository, any rule listed above, or a triggered review
prompt cannot be loaded completely, stop and report the blocker. Do not
substitute assumptions for canonical content, and do not copy canonical rule
text into this repository — always fetch and follow it from
`saas-factory-labs/SaaS-Factory@main`.

## Repository purpose and ownership boundary

Public composite GitHub Action (`Cloudcostify Budget Guard`) that downloads
the released `Cloudcostify/cli` binary and runs it in a caller's workflow to
estimate and gate on infrastructure cost. This repository owns the action's
input/output contract and the CLI-download step. It does not own CLI logic
itself — that lives in `Cloudcostify/cli`.

## Components

- `action.yml` — the entire action: a composite action with two `bash`
  steps (download the released CLI binary, then run it).
- `README.md`, `PRIVACY.md`.

There is no build step, no test suite, and no `.github/workflows/` in this
repository — `action.yml` is consumed directly by GitHub Actions in
downstream repositories.

## Build, test, package, release

- Nothing to build or package; `action.yml` is the shipped artifact.
- Release is a Git tag (e.g. `v1.0.0`), referenced by consumers as
  `uses: Cloudcostify/github-action@v1.0.0-beta`. The `cli-version: latest`
  input resolves against `cloudcostify/cli`'s GitHub releases at runtime.
  Tagging and publishing a release is a human-authorized action, not
  something an agent does unprompted.
- Manual verification: run the action in a real workflow against a Pulumi
  stack and confirm `budget-exceeded` is set correctly, and that the
  download step resolves the correct OS/arch binary (`linux`/`osx`/`win`,
  `x64`/`arm64`).

## Security-sensitive areas

- `action.yml` interpolates `${{ inputs.* }}` directly into `run:` bash
  steps. Treat every input as attacker-controlled in a fork-triggered
  workflow; do not introduce further unescaped interpolation.
- The CLI binary is downloaded over HTTPS via `curl` from a GitHub Releases
  URL with no checksum or signature verification before it is executed.
- `api-key` and `pulumi-access-token` inputs are passed through as
  environment variables to the downloaded binary.

## Required verification

- Apply the canonical review-gate routing before any change to the
  input/output contract, the download step, or how inputs reach the shell.
- Manually exercise the action end-to-end (as above); there is no CI to
  rely on in this repository.
