# Automated maintenance

Modeled after the Home Assistant openGym repository's release watch and monthly Codex agent.

## Daily: upstream change watch

GitHub Action: .github/workflows/check-upstream.yml.
Runs daily at 09:29 UTC and on workflow_dispatch. Compares the latest
DuarteSantos8/openGym release with upstream.json lastReviewedRelease.
For a release needing review, opens a GitHub issue once per upstream tag
(including closed-issue deduplication). Does not commit version bumps.

## Monthly: improvements/fixes/features

GitHub Action: .github/workflows/monthly-garmin-agent.yml.
Runs on the fourth day of the month at 10:48 UTC or manually from Actions.
Fetches official upstream release notes and changes to key Garmin and watch
relay files. An OpenAI Codex action reviews them and proposes only justified
compatibility fixes or small improvements. It runs npm test and manifest
checks, then opens a human-review pull request if files changed.
No change = no pull request. Never auto-merge.

## One-time setup required in this NEW repository

1. Create the GitHub Actions repository secret OPENAI_API_KEY under
   Settings > Secrets and variables > Actions. The secret in the older
   Home Assistant repository is not shared with this repository.
2. Under Settings > Actions > General, ensure the repository permits
   GitHub Actions to create pull requests. This setting may be disabled.
3. Keep GitHub Actions and Issues enabled. Review the PR and its CI
   before merging; device-related edits still need actual Garmin SDK
   compilation and testing on the original fēnix 5S.

The monthly action's model job has no repository write token. A separate
PR job gets restricted write permissions only if validated edits exist.

The agent's scope is intentionally restricted: maintain native integration
with the official OpenGym watch relay, preserve the original fēnix 5S /
Connect IQ 3.1 target, keep required reps separate from motion estimates,
do not automatically complete a set, and preserve offline event delivery,
scoped watch authentication and heart-rate features.

Note: upstream.json lastReviewedRelease is a source-compatibility review
marker only, NOT proof of simulator or device testing. GitHub Actions
schedules use UTC and may run later than the specified minute.
