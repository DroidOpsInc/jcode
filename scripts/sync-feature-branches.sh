#!/usr/bin/env bash
# scripts/sync-feature-branches.sh
#
# Auto-rebase long-lived `feature/*` and `pr/*` branches against the
# new tip of `master` after the upstream-sync job has fast-forwarded
# master from upstream/master.
#
# Renovate's GitLab plugin doesn't natively offer "rebase every open
# branch when the base advances" — only "rebase MRs labelled
# rebase!"-style flows on its own renovate/* branches. This script
# closes the gap for our fork: it runs inside the same CI job that
# advanced master, so the working tree is already at the new tip.
#
# Behaviour per branch:
#   1. Fetch the remote head.
#   2. Try `git rebase origin/master` from a worktree.
#   3. Clean rebase   -> force-push with lease, comment on any open MR.
#   4. Conflict       -> abort, leave branch untouched, post a comment
#                        on any open MR listing the conflicting paths,
#                        and apply the `needs-rebase` label.
#
# Required env (provided by .gitlab-ci.yml upstream-sync job):
#   UPSTREAM_SYNC_TOKEN  — project access token, write_repository scope
#   CI_SERVER_URL        — e.g. https://git.developerdojo.org
#   CI_SERVER_HOST       — e.g. git.developerdojo.org
#   CI_PROJECT_PATH      — DroidOpsInc/jcode
#   CI_PROJECT_ID        — 769
#
# Conflict-resolution playbook: see DROIDOPS.md.

set -uo pipefail

: "${UPSTREAM_SYNC_TOKEN:?UPSTREAM_SYNC_TOKEN is required}"
: "${CI_SERVER_URL:?CI_SERVER_URL is required}"
: "${CI_SERVER_HOST:?CI_SERVER_HOST is required}"
: "${CI_PROJECT_PATH:?CI_PROJECT_PATH is required}"
: "${CI_PROJECT_ID:?CI_PROJECT_ID is required}"

PUSH_URL="https://oauth2:${UPSTREAM_SYNC_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"
API_BASE="${CI_SERVER_URL}/api/v4/projects/${CI_PROJECT_ID}"
REBASE_LABEL="needs-rebase"

# Branches we manage. Anything matching these globs gets a rebase pass.
TRACKED_PATTERNS=(
  "feature/"
  "pr/"
)

log() { printf '[sync-feature-branches] %s\n' "$*"; }

api() {
  # api METHOD PATH [BODY]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "${body}" ]; then
    curl -fsS -X "${method}" \
      -H "PRIVATE-TOKEN: ${UPSTREAM_SYNC_TOKEN}" \
      -H "Content-Type: application/json" \
      "${API_BASE}${path}" \
      --data "${body}"
  else
    curl -fsS -X "${method}" \
      -H "PRIVATE-TOKEN: ${UPSTREAM_SYNC_TOKEN}" \
      "${API_BASE}${path}"
  fi
}

mr_for_branch() {
  # Returns the IID of the open MR whose source branch is $1, or empty.
  local branch="$1"
  api GET "/merge_requests?state=opened&source_branch=$(printf %s "${branch}" | jq -sRr @uri)" \
    | jq -r '.[0].iid // empty'
}

post_mr_comment() {
  local iid="$1" body="$2"
  api POST "/merge_requests/${iid}/notes" \
    "$(jq -nc --arg body "${body}" '{body:$body}')" >/dev/null
}

label_mr() {
  local iid="$1" label="$2"
  api PUT "/merge_requests/${iid}" \
    "$(jq -nc --arg add "${label}" '{add_labels:$add}')" >/dev/null
}

unlabel_mr() {
  local iid="$1" label="$2"
  api PUT "/merge_requests/${iid}" \
    "$(jq -nc --arg rm "${label}" '{remove_labels:$rm}')" >/dev/null
}

# Make sure git is configured (the calling CI job already does this,
# but be defensive in case the script is invoked manually too).
git config user.email "${GIT_AUTHOR_EMAIL:-ci@droidopsinc.dev}" || true
git config user.name  "${GIT_AUTHOR_NAME:-DroidOps CI (jcode upstream sync)}" || true

# Refresh remote refs so we see every feature/pr branch.
git fetch origin --prune --tags

# Snapshot the new master tip we're rebasing onto.
MASTER_TIP="$(git rev-parse origin/master)"
log "master tip after upstream-sync: ${MASTER_TIP}"

mapfile -t BRANCHES < <(
  git for-each-ref --format='%(refname:short)' refs/remotes/origin/ \
    | sed 's|^origin/||' \
    | while read -r br; do
        for pat in "${TRACKED_PATTERNS[@]}"; do
          case "${br}" in
            "${pat}"*) printf '%s\n' "${br}"; break ;;
          esac
        done
      done \
    | sort -u
)

if [ "${#BRANCHES[@]}" -eq 0 ]; then
  log "no feature/* or pr/* branches found — nothing to do"
  exit 0
fi

CLEAN=()
CONFLICTED=()
ALREADY_AHEAD=()

WORKTREE_ROOT="$(mktemp -d)"
trap 'rm -rf "${WORKTREE_ROOT}"' EXIT

for branch in "${BRANCHES[@]}"; do
  log "--- ${branch} ---"
  WT="${WORKTREE_ROOT}/$(printf %s "${branch}" | tr / _)"

  if ! git worktree add --detach "${WT}" "origin/${branch}" >/dev/null 2>&1; then
    log "  skip: failed to create worktree"
    continue
  fi

  pushd "${WT}" >/dev/null

  # Skip if branch tip is already on top of master (no rebase needed).
  if git merge-base --is-ancestor "${MASTER_TIP}" HEAD; then
    log "  already contains master tip — skipping"
    ALREADY_AHEAD+=("${branch}")
    popd >/dev/null
    git worktree remove --force "${WT}" >/dev/null 2>&1 || true
    continue
  fi

  if git rebase "${MASTER_TIP}" >/dev/null 2>&1; then
    log "  clean rebase"
    if git push --force-with-lease "${PUSH_URL}" "HEAD:refs/heads/${branch}" >/dev/null 2>&1; then
      CLEAN+=("${branch}")
      iid="$(mr_for_branch "${branch}" || true)"
      if [ -n "${iid}" ]; then
        post_mr_comment "${iid}" \
          ":robot: Auto-rebased onto \`master@${MASTER_TIP:0:12}\` by upstream-sync." || true
        unlabel_mr "${iid}" "${REBASE_LABEL}" || true
      fi
    else
      log "  force-push refused (likely protected or stale lease) — leaving alone"
    fi
  else
    log "  conflict — aborting rebase"
    CONFLICTS_RAW="$(git diff --name-only --diff-filter=U || true)"
    git rebase --abort >/dev/null 2>&1 || true
    CONFLICTED+=("${branch}")
    iid="$(mr_for_branch "${branch}" || true)"
    if [ -n "${iid}" ]; then
      conflicts_md="$(printf '%s\n' "${CONFLICTS_RAW}" | sed 's/^/- `/; s/$/`/')"
      [ -z "${CONFLICTS_RAW}" ] && conflicts_md="(rebase aborted before paths could be enumerated)"
      post_mr_comment "${iid}" \
"$(cat <<EOF
:warning: **Rebase against \`master@${MASTER_TIP:0:12}\` failed — manual reconciliation required.**

Conflicting paths:

${conflicts_md}

See [DROIDOPS.md > Conflict-resolution playbook](../../blob/master/DROIDOPS.md) for the recovery flow.
EOF
)" || true
      label_mr "${iid}" "${REBASE_LABEL}" || true
    fi
  fi

  popd >/dev/null
  git worktree remove --force "${WT}" >/dev/null 2>&1 || true
done

log ""
log "Summary:"
log "  already-ahead : ${#ALREADY_AHEAD[@]}"
log "  rebased clean : ${#CLEAN[@]}    ${CLEAN[*]:-}"
log "  conflicted    : ${#CONFLICTED[@]}    ${CONFLICTED[*]:-}"

# We do NOT exit non-zero on conflicts — that's a signal, not a failure.
# The CI job stays green so the next day's upstream-sync can still run.
exit 0
