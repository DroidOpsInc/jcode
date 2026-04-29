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

### Renovate-driven feature-branch rebase

After `master` advances, the same `upstream-sync` CI job invokes
`scripts/sync-feature-branches.sh` to rebase every open `feature/*` and
`pr/*` branch onto the new tip. See `renovate.json` for the supporting
custom-datasource that surfaces upstream advances on the Renovate
dashboard, and `scripts/sync-feature-branches.sh` for the rebase logic
(Renovate's GitLab plugin doesn't natively support "rebase every open
branch when the base advances", so we implement that pass ourselves).

Pinned upstream tip (Renovate-tracked):

<!-- renovate:upstream-sha -->
`6cc66ed2f856d24c771a82b1b39646772b081c96`

The sentinel above is updated by Renovate when upstream/master advances;
the actual fast-forward + rebase pass happens in CI.

### Conflict-resolution playbook

When `sync-feature-branches.sh` can't rebase a branch cleanly it leaves
the branch untouched, comments on the open MR with the conflicting
paths, and labels the MR `needs-rebase`. To resolve:

1. **Pull the latest `master`.**
   ```bash
   git fetch origin
   git checkout master && git pull --ff-only
   ```
2. **Check out the feature branch.**
   ```bash
   git checkout feature/<topic>
   git pull --ff-only origin feature/<topic>
   ```
3. **Rebase manually.**
   ```bash
   git rebase origin/master
   ```
4. **Resolve each conflict.** Prefer keeping the upstream-shaped change
   when the conflict is in vendored code (we want to stay
   fast-forwardable from `1jehuang/jcode:master`); prefer keeping our
   change when the conflict is in `DROIDOPS.md`, `.gitlab-ci.yml`, or
   anything under `scripts/sync-feature-branches.sh`.
5. **Continue & push.**
   ```bash
   git add -A && git rebase --continue
   git push --force-with-lease origin feature/<topic>
   ```
6. **Remove the `needs-rebase` label** from the MR. The next
   `upstream-sync` pass will leave the branch alone (its tip already
   contains `master`).

If a branch has been stale for more than 14 days and continues to
conflict every cycle, close the MR and re-cut the branch from the
current `master`. Long-lived divergence is what Renovate is trying to
prevent — a permanent fork is a stronger signal than any one rebase.

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
