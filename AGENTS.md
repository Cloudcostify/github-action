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

- `action.yml` — the composite action: validates inputs and resolves the
  target platform, downloads and checksum-verifies the released CLI binary,
  then runs it.
- `scripts/lib.sh` — sourceable bash functions used by `action.yml` and by
  the test suite (input validation, platform/RID resolution, checksum
  verification). Keep behavior in this file, not duplicated inline in
  `action.yml`, so it stays testable.
- `tests/lib_test.sh` — dependency-free unit tests for `scripts/lib.sh`; run
  via `.github/workflows/test-action.yml`.
- `.github/workflows/test-action.yml` — CI: ShellCheck, actionlint, the unit
  tests, and an input-validation end-to-end job that runs the composite
  action itself against known-bad inputs.
- `README.md`, `PRIVACY.md`.

## Build, test, package, release

- Nothing to compile; `action.yml` plus `scripts/lib.sh` are the shipped
  artifact.
- `bash tests/lib_test.sh` runs the unit tests locally.
- CI (`.github/workflows/test-action.yml`) also runs ShellCheck over
  `scripts/` and `tests/`, and actionlint over the workflow/action YAML.
- Release is a Git tag on this repository (e.g. `v1.0.0`), referenced by
  consumers as `uses: Cloudcostify/github-action@v1.0.0-beta`. The
  `cli-version: latest` input resolves against `Cloudcostify/cli`'s GitHub
  releases at runtime; `Cloudcostify/cli` publishes each release's binaries
  together with a `SHA256SUMS` manifest via its own
  `.github/workflows/release.yml`, which this action's download step
  verifies against before executing anything. Tagging and publishing a
  release in either repository is a human-authorized action, not something
  an agent does unprompted.
- Manual verification: run the action in a real workflow against a Pulumi
  stack and confirm `budget-exceeded` is set correctly, that the download
  step resolves the correct OS/arch binary, and that checksum verification
  actually runs (fails closed if `SHA256SUMS` is missing or mismatched).

## Security-sensitive areas

- Every `inputs.*` value is untrusted, including in a fork-triggered
  workflow run. Inputs must reach shell logic only through `env:` bindings,
  never through direct `${{ }}` interpolation inside a `run:` script body,
  and must be passed to the downloaded CLI as an argument-array entry, never
  concatenated into a command string.
- The downloaded CLI binary must pass checksum verification
  (`scripts/lib.sh`'s `verify_checksum`) before `chmod +x` or execution;
  treat a missing, malformed, or mismatched checksum as fail-closed, not a
  warning.
- `provider`, `budget`, and `cli-version` are constrained inputs — validate
  each against its allowlist/format (see `scripts/lib.sh`) before using it,
  including before any network call.
- `api-key` and `pulumi-access-token` are passed to the downloaded binary
  only via `env:`; never place a credential in an argument, a log line, or
  generated Markdown output.
- Resolving an unrecognized operating system or architecture must fail
  closed; never fall back to a default platform.

## Required verification

- Run `bash tests/lib_test.sh` for any change to `scripts/lib.sh`.
- Apply the canonical review-gate routing before any change to the
  input/output contract, the download step, checksum verification, or how
  inputs reach the shell.
- CI runs ShellCheck, actionlint, the unit tests, and the input-validation
  end-to-end job on every push/PR to `main`.
- The download-and-verify path against a real release cannot be exercised
  end-to-end until `Cloudcostify/cli` has published its first release with
  binaries and a `SHA256SUMS` manifest; treat that as an open verification
  gap until then, not as passing coverage.
