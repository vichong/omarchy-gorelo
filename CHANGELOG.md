# Changelog

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
