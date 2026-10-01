# Gorelo updates and Connect v2 — approval plan

**Status: slices 1–3 implemented in v0.2.0.** Direct Connect remains verification-gated. This document records the approved scope and acceptance criteria; the browser-assisted options remain research only.

Read the [dated research](../research/gorelo-updates-2026-10-02.md) for source-backed API contracts, release findings and unknowns. See [release notes](../../CHANGELOG.md) for shipped changes and verification limits.

## Goal

Find the intended machine quickly, launch Connect v2 in the preferred browser when its launch contract is verified, and make ticket status changes visibly reliable. Preserve existing queue, device-page, screenshot, privacy and demo workflows.

## Recommended scope

### 1. Current API compatibility

- Move screenshot upload to documented `POST /v1/attachments`, supplying `itemType=Ticket` and the newly created ticket ID. Send metadata with curl `--form-string` (not `-F` interpolation), validate the live ID as a UUID in both backend and helper, and accept only the Ticket item type. Keep the existing private-comment attachment step, strict 20 MiB cap, verified inode and cleanup behavior; demo IDs stay isolated from live validation.
- Validate ticket/device server query length against the documented 200-character limit, with a clear message instead of silent truncation or a failing request.
- Use documented device status IDs for online/offline display; unknown/missing IDs remain unknown rather than falling back to name guessing or being inferred as Connect-ready. Align demo fixtures and tests with Online=2, Offline=3, and an unknown case.
- For `AskForReason` statuses, send no PATCH, retain the confirmed dropdown value, explain the limitation and offer Open in Gorelo. Add a matching demo fixture. The public PATCH contract has no reason field. Keep existing explicit status filters unchanged. Avoid unverified numeric ticket-base-status migrations.
- Correct README claims: Connect v2 is alpha, time-entry writes exist, ticket detail exposes linked assets, and user-name searches outside the cache are not supported by documented server matching.

Completion: focused contract tests pass and existing screenshot safety checks remain intact. Do not call the old upload route broken without a live reproduction; the change aligns with the supported published contract.

### 2. Conventional close-ticket UX

**Pending → confirmed update/removal → confirmation.** No confirmation dialog, artificial delay or optimistic Undo.

- As soon as a status is selected, display `Closing…` or `Saving…` on that ticket and disable duplicate status submissions. Keep pending state keyed by ticket ID in the service, not a disposable row delegate.
- After successful PATCH, update local ticket status and queue membership immediately; do not wait for another full queue fetch. Respect configured visible status IDs: Closed only leaves a queue that excludes it.
- In all-status server search, retain the ticket with its new status. Background refresh keeps current results visible.
- Confirm once, e.g. `Ticket #123 closed`; for other statuses, `Ticket #123 changed to On Hold`. Use the existing short-lived notification/toast mechanism.
- On failure, restore the last confirmed status, retain the row and expansion, and show an actionable error. A timeout must not claim the server definitely rejected the change; reconcile with a read before a blind retry.
- Invalidate pre-mutation polls and ticket-search responses so they cannot reintroduce stale state. Reconcile local state against a fresh authoritative result; handle poll/search failures without a permanently hidden ticket.
- Preserve selected ticket identity when possible; after removal select the next row, or the previous row at the end, and restore keyboard focus without stealing focus from unrelated editing.
- Reset pending state safely on connection/demo/region changes; stale callbacks must not mutate the new connection's state.

Completion: success, failure, ambiguous timeout, repeated selection, in-flight poll/search, search-mode retention, custom filters, last-row removal and keyboard navigation behave as specified.

### 3. Machine search that prioritises the intended device

- Keep the familiar combined search: immediate cached results while typing; Enter searches Gorelo. No surprise remote session on Enter in the search field.
- Rank exact machine-name matches first, then exact display-name, then name prefixes, then broader substring matches; use online status and stable name/ID ordering only as tie-breakers.
- Display actual hostname as well as friendly name where they differ; keep client and last user useful for disambiguating duplicate names.
- Eight visible rows become a presentation batch, not an invisible final cutoff. Offer `Show more` for additional matches already held locally.
- Keep server searches bounded and simple: one device query with `PageSize=200`, using `HasMore` to show truncation/refine-search guidance. Exact matches are prioritised within retrieved results, not guaranteed globally when the server truncates. Defer server cursor UI.
- Distinguish current-query results from older cached hits; preserve bounded caches and reject stale query callbacks. Keep cache-only user/client/serial matching, with accurate help text.
- Enter augments locally matched tickets/devices with server results, deduplicated by ID, rather than discarding local-only matches. Newer server records supersede stale cache records and are rematched as appropriate. Align demo server search with the documented narrower fields, so demo does not hide this live limitation.
- Make the expanded row's `Open in Gorelo` and eventual `Connect` actions keyboard-focusable with standard Tab/Enter activation rather than inventing a new shortcut.

Completion: exact offline hostname outranks online partial matches, duplicate names remain distinguishable, server matches beyond the cache are reachable, additional retrieved matches are revealable, query changes do not mix results, Enter preserves valid local-only matches, and failures preserve useful results with honest completeness labels.

### 4. Connect v2 — gated on a verified launch contract

This is the requested end-to-end outcome, but public documentation alone does not yet make it implementable safely.

Before code: obtain a supported external launch pattern or inspect a user-authorised v2 launch on a designated test device. Record only sanitised structure, origins and required identifiers; never credentials/session URLs. Confirm auth, expiry, consent and Linux browser behavior. If the mechanism is undocumented, bring that stability/security trade-off back for approval.

If a stable, non-secret browser deep link is verified:

- Add a separate **Connect** action; preserve **Open in Gorelo** for device details.
- Route through a narrow `connectDevice(deviceId)` service seam and the existing preferred-browser launcher. Use current browser login; never put the API key in a URL or command arguments.
- Validate HTTPS and verified exact host/origin rules, encode placeholders, and reject credentials, malformed URLs and look-alike hosts.
- Keep launch configuration non-secret. Do not add an arbitrary URL template as a substitute for discovering a valid contract.
- Browser handoff reports `Opening Connect…`, not `Connected`: a successful browser launch does not establish session state.
- Demo mode reports what would happen and never opens a real session. Online/offline RMM state is informative, not a Connect capability guarantee.

If launch requires an undocumented internal API, cookies, session-token capture or a native custom protocol: stop this slice for a new decision. Do not automate the web UI or substitute device-page opening while claiming direct Connect success. The existing clearly labelled device-page action remains usable.

Completion: a user-approved test on a v2-enabled endpoint launches in the selected Omarchy browser with normal Gorelo auth/consent and a clean failure path. No other endpoint is contacted for a remote session.

## Deliberately deferred

- Timer/time-entry UI, automatic billing or session-end notes.
- Linked-device controls on ticket rows (possible through lazy ticket-detail fetches; a follow-on once device Connect works).
- Active-session bar indicator: launching a browser does not provide session lifecycle events.
- Dedicated web-app windows/workspace management. The existing preferred browser is the proposed first release, superseding the old roadmap's unconditional web-app promise only with approval.
- Billing/catalogue/invoice/uptime/project features, wholesale architecture rewrites, policy rollout and additional API scopes.

## Implementation and delegation sequence after approval

1. Establish behavioral tests at existing pure JS seams. Extract only the pending-status/search reconciliation logic needed into a small QML-compatible JS module, exercised with controllable callbacks in Node and used by Service; retain a manual QML wiring/focus check. Do not build a general QML framework. Use Matt's TDD workflow one behavior at a time.
2. Implement API alignment, status UX and search as vertical slices. Shared `Service.qml` and model edits have one implementation owner; delegate only disjoint tests/research objectives.
3. Resolve the Connect contract gate separately. Implement that slice only when its conditions are satisfied; otherwise report it blocked, not completed.
4. Run the existing Node suite, new deterministic fake-backend/helper tests, and `omarchy plugin validate .`; manually validate QML interaction in demo/test mode.
5. Official Claude CLI reviews the resulting diff against this plan and security invariants. Lead resolves findings and records which live checks remain.
6. Any live status write, screenshot upload or remote session uses a user-approved test ticket/device. No commits, push, release, policy changes or shell restart are implied by code approval.

## Test seams and acceptance matrix

| Boundary | Tests |
| --- | --- |
| API/config/model (existing Node approach) | Current ticket/comment payload fixtures; upload metadata; query limit; device status IDs including unknown/missing; ranking before limits; stable merge and truncation; URL encoding/validation once contract known; default settings compatibility |
| Narrow status/search coordinator with controllable fake backend | Pending display state; one PATCH per ticket; confirmation once; success vs failure; timeout reconciliation; stale poll/search rejection; pending cleanup on connection switch; local+server search retention; filter-aware removal; reason-required target sends no PATCH; 400 Notifications message retained |
| Attachment helper with fake curl, private temporary files | Correct multipart target and literal metadata; invalid/non-UUID IDs and malicious `@`/`<` values refused; stdin credential handling; no redirects; owned regular-file/inode constraints, size caps and cleanup preserved; no live upload |
| Demo/manual QML | Documented status IDs and server matching fields; visible pending/error feedback with delayed fake responses; dropdown rollback; reason-required handoff; keyboard focus; next/previous selection; show more; no real Connect launch in demo |
| Explicitly authorised live smoke | New upload contract; machine found beyond cached results; one selected test ticket status change; one Connect v2 browser launch with auth/consent |

The baseline Node suite already passes; it does not cover asynchronous QML/service behavior. Tests must observe behavior rather than only source strings. No live acceptance checks have run.

## Approval recorded

The user approved slices 1–3 and the gated Connect slice, with **preferred browser + separate Connect action + confirmed-save toast UX**, using the test boundaries above. If the direct-launch contract remains unavailable, report the independent work and the Connect blocker separately. Approval is not a claim that a direct-launch URL is known.
