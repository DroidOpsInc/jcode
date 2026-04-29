# DroidOpsInc fork of jcode

This is a vendored fork of upstream **`1jehuang/jcode`** (MIT, GitHub).

It is the default agent-harness engine for **`DroidOpsInc/hypercraft`**.

## Upstream

| Field | Value |
|---|---|
| Upstream URL | <https://github.com/1jehuang/jcode> |
| Upstream license | MIT (preserved) |
| Upstream maintainer | Jeremy Huang (`1jehuang`) |
| Upstream default branch | `master` |

The `upstream` git remote is configured locally as fetch-only (push URL is `no-push`).

## Branch model

| Branch | Purpose | Direct commits? |
|---|---|---|
| `master` | Exact mirror of upstream `master`. Synced via scheduled CI. | No |
| `droidops/*` | Our integration branches. Targets `master`. | Yes, via MR |
| `feature/*` | Patches we plan to send upstream as PRs. Branched off `master`. | Yes, via MR |

`master` is protected. All changes land via merge requests.

## Outbound contribution flow (PRs back to upstream)

1. Branch `feature/<topic>` from `master`.
2. Implement, push, open MR against `master`. Land it once reviewed.
3. Push the same commits to a public GitHub fork of `1jehuang/jcode`.
4. Open a PR upstream from the GitHub-side fork.
5. Track Jeremy's response in the MR description.

## Inbound sync (upstream → us)

A scheduled GitLab CI job (`upstream-sync`) runs daily with the schedule
variable `UPSTREAM_SYNC=true`. It fetches `upstream/master`, fast-forwards
local `master`, and pushes back to `origin/master`. If the fast-forward fails
(we have diverged from upstream), the job fails loudly — manual reconciliation
required.

To enable the schedule:

1. Create a project access token with `write_repository` scope.
2. Store it as the masked CI variable `UPSTREAM_SYNC_TOKEN`.
3. Create a daily pipeline schedule with variable `UPSTREAM_SYNC=true`.

Renovate-style auto-rebase of long-lived feature branches against the new
`master` tip is a follow-up — see the `chore/renovate-config` issue.

## Why we forked

- The hypercraft platform requires an agent-harness engine that supports
  semantic-vector memory, native swarm collaboration, soft interrupts with
  an editable message queue, and OpenAI-compatible local-model endpoints
  (Qwen 3.6-27B via vLLM).
- Upstream jcode is the only harness shipping all of these as first-class
  features in April 2026.
- Vendoring as a private fork preserves our supply-chain posture: telemetry
  scrubbed, releases signed via launch-sequence, dependencies pinned, all
  subject to our policy gates.

See `DroidOpsInc/hypercraft` for the engine-adapter design and the broader
multi-engine strategy (jcode default, ForgeCode + Claude Code + Codex CLI
fallbacks).
