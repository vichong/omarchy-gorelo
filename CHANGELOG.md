# Changelog

## 0.2.1 — 2026-10-02

### Full-codebase due-diligence fixes

- Ignore curl config files (such as `.curlrc`) for requests and uploads, preserving the plugin's transport settings; curl environment variables still apply.
- Prevent flag-shaped ticket text from changing notification options; render notification headlines as literal plain text.
- Isolate captures in private staging directories and publish unique, non-overwriting screenshot names, so delayed cleanup cannot delete a newer capture with the same timestamped filename.
- Keep capture/upload/delete metadata checks locale-independent without changing child-process locale, and show actionable capture failure/timeout feedback without treating ordinary cancellation as an error.
- Reset account-specific caches, drafts and settings when a different API key is submitted, including within the same region. Ordinary reconnects retain their settings.
- Retain local ticket-search matches after closing them and across empty or failed refreshes. Bound the active snapshot to 1,000 local matches plus 50 current server results, with a distinct capacity warning and no silent eviction.
- Preserve local-only device matches when server search fills its 200-result limit; choose device records by request freshness rather than unconditional cache precedence.
- Preserve newer draft and private-note edits when earlier submissions finish, including screenshot and overlay lifecycles. Prevent duplicate pending note submissions.
- Keep one ticket's actionable failure visible when an unrelated ticket action succeeds.

Targeted failing-then-passing regressions, all ten Node test files, helper syntax checks and Omarchy plugin validation passed. Independent Standards/security and Spec/behavioral follow-ups found no remaining blocker in their reviewed scopes. The final isolated Qt snapshot passed 200 assertions plus demo/Panel smoke; external effects were stubbed and screenshots were synthetic.

Subsequent local manual acceptance covered panel rendering, search/tab changes, typing/focus, scrolling and successful screenshot attachment after a shell restart. A same-URL QML cache issue was independently reproduced: plugin rescan could retain the previous component after a symlink switch. The README now documents the fresh-runtime deployment precaution; no plugin source change was needed for that retest.

Live ticket writes/status changes and screenshot uploads remain unverified. Capture cancellation has automated coverage, but the proposed manual replacement test was not applicable: the UI requires removing an existing attachment before adding another. Low-severity process/cleanup limitations remain documented; these checks are not a safety guarantee. See the [full-codebase due-diligence report](docs/research/v0.2.0-due-diligence.md) for phase-specific coverage, findings and residual risks. Local testing does not publish these changes or update the marketplace.

**Full diff:** https://github.com/vichong/omarchy-gorelo/compare/v0.2.0...v0.2.1

## 0.2.0 — 2026-10-02

### Better ticket-status feedback

- Status changes immediately show **Closing…** or **Saving…** and prevent duplicate submissions.
- A successful save updates the queue immediately and shows a short confirmation notification. Tickets leave the queue only when the selected status is excluded by its filters.
- Failed changes retain the ticket and its confirmed status. Uncertain network/server outcomes are reconciled with a fresh read instead of blindly repeating a write.
- Preserve surviving rows and expanded editors during refreshes, reject stale responses, and improve keyboard focus after a row disappears.
- Statuses requiring a reason direct you to Gorelo without sending an incomplete status change.

### Better machine search

- Exact hostnames rank ahead of friendly-name and partial matches, even when the exact device is offline.
- Server search retrieves up to 200 devices; **Show more devices** reveals additional retrieved matches and reports truncation when a narrower query is needed.
- Pressing Enter preserves useful local ticket matches and adds server matches, deduplicating by ID and preferring fresher records.
- Show actual hostnames alongside friendly names and distinguish current server hits from cached results.
- Enforce the documented 200-character query limit. Device online/offline state uses documented status IDs.

### API compatibility and safety

- Screenshot uploads use the current `POST /v1/attachments` endpoint with literal `itemType=Ticket` and validated ticket UUID metadata.
- Preserve stdin-only API-key transport, exact API origins, redirect rejection, response limits, the 20 MiB attachment cap, and inode-bound upload/cleanup.
- Align demo status/search behavior with the current API while keeping demo filters isolated from live settings.
- Expand automated coverage for asynchronous status changes, searches, selection, API contracts and attachment process boundaries.

### Connect v2 status

Gorelo Connect v2 is available as a policy-enabled alpha, but **this release does not add direct Connect launch**. The observed browser flow creates a session through an internal gateway and opens a viewer with transient credentials; a supported external launch contract has not been verified.

Use **Open in Gorelo**, then Gorelo's **Connect (v2)** button. No browser extension, credential extraction or private-session API integration is installed by this release. Time-entry APIs now exist, but timer/billing features remain out of scope.

### Validation

All nine Node test suites and Omarchy plugin validation passed. An isolated Qt 6 runtime smoke verified demo queue loading, pending/confirmed status behavior, device search and Panel instantiation against stock Omarchy components. Independent code review completed with accepted findings resolved.

Interactive focus/visual acceptance and live ticket-write/upload checks remain unverified; automated tests and the demo smoke are not substitutes for those checks.

**Full diff:** https://github.com/vichong/omarchy-gorelo/compare/v0.1.3...v0.2.0

## Earlier releases

See the [GitHub releases](https://github.com/vichong/omarchy-gorelo/releases) for v0.1.0–v0.1.3.
