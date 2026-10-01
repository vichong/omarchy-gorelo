# Gorelo update research — 2026-10-02

Research baseline: plugin commit `8d373c0` (v0.1.3). The [implementation plan](../plans/gorelo-connect-v2.md) led to the search, status-feedback and API updates in v0.2.0. This report records the public-source research; later authorised [browser observation](connect-browser-observation-2026-10-02.md) and [browser-assisted options](browser-assisted-connect-options.md) supplement the Connect findings.

## Findings and impact

| Change | First-party evidence | Plugin impact / recommendation |
| --- | --- | --- |
| Connect v2 released **25 September as alpha**, enabled with “Use Gorelo Connect v2” on a policy's Gorelo Connect plugin | [25 September release](https://feedback.gorelo.io/changelog/release-notes-2026-09-25): “You connect from the browser with nothing to install”; “This is an alpha release” | Browser launch is now a real integration target, not a future announcement. Tenant/device rollout and Linux technician-browser compatibility still need a smoke test. |
| Windows/Mac remote access; login screen, UAC, unattended devices, multiple monitors, clipboard, file transfer, background session | Same release | Vendor claims, not tested here. Do not infer a public API or a stable external launch URL from these features. |
| No public Connect/session endpoint or launch URL found | Both regional Swagger documents, listed below; `DeviceResponse` has no launch URL or Connect capability field | Direct launch remains blocked on a verified contract. RMM online status does not prove Connect v2 is enabled. Keep device-page opening separate. |
| Machine-name search supported | Swagger `GET /v1/assets/agents`, `Query`: “Keyword matched against the device name, display name and description. Up to 200 characters.” | Existing server query is valid. Improve ranking, bounded retrieval and completeness feedback; logged-on user/client/serial searches are cache-only, not guaranteed server matches. |
| Linked assets are available on ticket **detail**, not list | Swagger `GET /v1/tickets/{ticketId}` and `TicketDetailModel.AgentAssetIds`; absent from `TicketListItemModel` | Optional later lazy detail fetch can enable Connect on ticket rows without fetching every ticket's details. The roadmap need not wait for list support, but list support has not arrived. |
| Attachment upload now documented as `POST /v1/attachments` | [25 September release](https://feedback.gorelo.io/changelog/release-notes-2026-09-25), Swagger | Existing `/v1/tickets/{id}/attachments` path is absent from current Swagger. Treat as a compatibility risk, not a reproduced outage; migrate to documented route. |
| Time entry CRUD exists | [4 September release](https://feedback.gorelo.io/changelog/release-notes-2026-09-04), Swagger `/v1/time-entries` | README statement “Time entries cannot be created” is obsolete. Correct docs; defer timer/time-entry UI to a separate scope. |
| Billing override field changes; nullable contact; stricter validation; internal parameters stripped | [3 September API changes](https://feedback.gorelo.io/changelog/api-changes-2026-09-03) | Do not rely on undocumented Connect query parameters. Current simple status/assignment payloads do not use billing overrides. Add focused contract fixtures, not a billing subsystem. |
| `IsWaitingOnThem`, `LocationId`, warranty start/end | [21 August API changes](https://feedback.gorelo.io/changelog/api-changes-2026-08-21) | Existing ticket projection already uses `IsWaitingOnThem`. Location/warranty changes do not affect fields currently displayed. |
| Item, tax, invoice, contract and uptime APIs expanded | 25 September release and current Swagger | Opportunities, not necessary for the requested queue/search/Connect workflow. Current Swagger does not include invoice creation despite the release note mentioning it: verify before future use. |
| Mobile rebuilt, Messenger released, Mobile asset search added | [11 September](https://feedback.gorelo.io/changelog/release-notes-2026-09-11), [18 September](https://feedback.gorelo.io/changelog/release-notes-2026-09-18), [26 September](https://feedback.gorelo.io/changelog/release-notes-2026-09-26-scalecon-special) | Product context, no direct plugin integration required. |

## Authoritative public API inspected

- [API overview](https://help.gorelo.io/api-overview.md) and [Swagger instructions](https://help.gorelo.io/swagger-ui.md).
- [Australian Swagger JSON](https://api.aue.gorelo.io/swagger/v1/swagger.json).
- [US Swagger JSON](https://api.usw.gorelo.io/swagger/v1/swagger.json).
- Retrieved without credentials on 2026-10-02. Both documents are structurally identical, titled **Public API**, version `1.0.0`, with 58 paths. Matching schemas do not prove identical tenant rollout.
- The help site's advertised [OpenAPI file](https://help.gorelo.io/api-reference/openapi.json) is a Mintlify **Plant Store sample**, not Gorelo's contract. It was excluded from integration conclusions.

### Devices and search

Agent list uses cursor pagination, `PageSize` 1–200 (default 50), optional `Query`, `ClientIds`, `StatusIds`, and date filters. Deleted/client-inactivated devices are excluded. Its operation summary says created-time descending; a property description contradicts this with ascending. Neither specifies relevance ranking, so do not assume the first page contains the exact hostname.

Device identifiers are UUIDs. `Name` is the machine name and `DisplayName` is a friendly name. The response includes last user/UPN and client ID, but those fields are **not** included in the documented server `Query` matching. [API overview](https://help.gorelo.io/api-overview.md) explicitly defines device `Status.Id=2` as Online and `3` as Offline. Prefer these IDs over translated display names.

### Status changes

`PATCH /v1/tickets/{ticketId}` accepts `StatusId` and returns an ID, not the refreshed ticket. Its description says each change invokes the same notifications, timeline and cache updates as the app. A successful status change can therefore have side effects that a later reverse PATCH cannot undo.

Status metadata includes `BaseStatusId`, `Color`, `SortOrder` and `AskForReason`. The latter means a transition requires a reason, yet `UpdateTicketCommand` has no reason field. Do not invent one: offer the Gorelo UI for reason-required transitions until an API contract is confirmed. [Ticket documentation](https://help.gorelo.io/tickets.md) also says New cannot be selected manually. Numeric ticket base-status meanings need confirmation before changing automatic queue classification; the published device status IDs are a different domain.

### Attachments

`POST /v1/attachments` takes multipart `file`, `itemType` (`Ticket`, `Task`, `Project`), and `itemId`. The target must already exist. The response returns `Name` and `Url`; the URL contains an expiring token. Pass the pair directly into comment `Attachments` and do not persist the URL. The server accepts up to 44 MB; the plugin's stricter 20 MiB ceiling can remain.

Current create-then-upload-then-private-comment ordering and the Name/Url pair are already correct. The endpoint and multipart metadata need alignment. Keep inode-bound file verification, cleanup, response limits and stdin-only API-key transport.

### Time entries

New time-entry writes can affect billing/contract allowances. Current Swagger rejects entries for a closed ticket, a ticket without a client, or a client on credit hold (409). This is not a trivial follow-on to a session timer; treat as a separate approved feature.

## Connect v2: evidence gap

The user supplied [Install Gorelo Connect](https://help.gorelo.io/install-gorelo-connect). Its current [Markdown version](https://help.gorelo.io/install-gorelo-connect.md) describes `GoreloLauncher.exe` and `gorelolauncher:` protocol handling. Those legacy instructions are not a v2 external-launch specification.

[What is Gorelo Connect](https://help.gorelo.io/what-is-gorelo-connect) documents in-app buttons on assets, linked tickets, search and alerts. [Policy installation](https://help.gorelo.io/install-the-gorelo-connect-plugin.md) documents consent and connection banners. The [v2 roadmap post](https://feedback.gorelo.io/p/desktopcomputer-gorelo-connect-v2) describes the browser engine but no launch contract.

Before implementing direct launch, establish:

1. A supported or explicitly accepted, tested stable browser URL/launch mechanism; an already-running session URL alone is insufficient.
2. Required device/tenant identifiers, regional host, browser authentication and redirect behavior.
3. Whether a URL contains session credentials or expires; never save/replay such links as a template.
4. How unavailable/offline/non-v2 devices fail and how consent remains enforced.
5. Successful launch from the user's Omarchy browser with v2 enabled on a designated test device.

No credentials, tenant API calls, policy changes, authenticated browser inspection or remote sessions were used in this initial public-source research. No direct-launch URL was guessed. The later, separately authorised [browser observation](connect-browser-observation-2026-10-02.md) confirmed an internal session POST followed by a viewer URL with session/auth parameters; their values were not captured. A public-key-compatible or stable external launch contract remains unverified.

## Local assessment and checks

An independent read-only assessment identified these baseline issues (line numbers refer to the pre-change source):

- `Model.js:162–175`, `Service.qml:498`: online-first ranking and eight visible devices can hide an exact hostname.
- `Service.qml:565–585`: mutation feedback waits for a subsequent poll; no row pending feedback.
- `StatusDropdown.qml:214–220`, `TicketRow.qml:159–162`: dropdown immediately changes its own value, risking mismatch after failure.
- `Service.qml:461–486`: mutation-triggered search clears results; stale polls/searches need coordinated invalidation.
- `Service.qml:557–560`: existing device-page browser hook can remain the fallback.

Claude findings are static analysis; visible failures were not reproduced in a live tenant. Lead subsequently verified the public contracts and attachment mismatch independently.

A follow-up Claude review accepted the Connect gate and preferred-browser direction. Incorporated corrections: literal multipart metadata with live UUID validation; documented demo status/search semantics; preserving valid local-only search matches on Enter; an explicit no-PATCH rule for reason-required statuses; and a bounded asynchronous test seam. The plan uses one 200-device server request plus local Show more rather than introducing cursor UI. The live comment schema was separately checked by the lead (`CreateCommentCommand`: Body, ConversationTypeId, optional CreatedByName and Attachments); the implementation includes a contract fixture.

Baseline checks passed: `node tests/test_api.js`, `node tests/test_model.js`, `node tests/test_config.js`, `node tests/test_demo.js`. No QML integration or live remote-control acceptance test has run.

Research used first-party documentation, public regional Swagger schemas and a sanitised browser observation. The implementation received independent review. Release validation and remaining live-interaction checks are summarised in [CHANGELOG.md](../../CHANGELOG.md).
