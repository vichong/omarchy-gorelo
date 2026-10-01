# Browser-assisted Connect: options and approval gate

**Research only — 2026-10-02. No implementation or additional session authorised.**

## Recommendation

Use the smallest useful flow: **find machine → Open in Gorelo in the selected browser → user presses Gorelo's own Connect (v2) button**. This is explicitly a two-step handoff, not direct Connect. It needs no extension, native host or credential transport. An optional narrowly scoped extension could help identify the intended asset and highlight the existing button, but should not automatically start a session on navigation.

Prefer a supported vendor launch contract if Gorelo supplies one. A genuinely one-click plugin-to-session bridge is **not established**: authenticated page automation is technically plausible, but an external navigation is not proof of user intent and does not convey page user activation. Native messaging does not solve that problem by itself.

## Evidence and boundaries

The [sanitised observation](connect-browser-observation-2026-10-02.md) establishes that a real Connect (v2) click sends a POST to an internal regional gateway, then opens a credential-bearing viewer URL. It does not establish a reusable deeplink, authentication contract, expiry or popup behavior for synthetic clicks. No values, cookies or headers were captured. The [public API research](gorelo-updates-2026-10-02.md) found no public session endpoint; absence from those contracts is not proof no vendor-supported mechanism exists.

Gorelo documents Connect buttons on asset details and other in-app surfaces [1]. Its installation guide still describes `GoreloLauncher.exe` and `gorelolauncher` links [2], not a v2 Linux/browser launch specification. Neither is authority to call the observed private gateway using an organisation API key.

This investigation fetched only public browser documentation and the two public Gorelo help pages with curl. No live browser, profile, private endpoint, credentials, install, product source inspection or status/search diff review was used. All bridge designs below are proposals, not tested behavior.

## Three practical options

### 1. Supported vendor deeplink / launch API — preferred eventual solution

Ask Gorelo for a documented, non-secret asset-targeted browser launch mechanism, supported regional hosts, browser login/redirect semantics, consent, device eligibility and Linux technician-browser compatibility. Ask whether navigation merely opens a confirmation screen or creates a session, and how arbitrary websites are prevented from triggering it.

A non-secret URL that reaches a vendor confirmation screen would fit the current preferred-browser handoff without an extension. If an API is offered, verify its authentication and scope rather than treating the current public key as compatible. A response containing transient viewer credentials must stay within Gorelo's browser flow; it cannot become a plugin URL template, log entry or native-helper return value.

**Trade-off:** least maintenance and best long-term contract, but unavailable on current evidence. One-click behavior depends on the vendor's actual design; a documented confirmation screen is still two-step. Legacy native protocol instructions are not a substitute.

### 2. Thin browser UI assistant — smallest optional helper

Proposed flow:

1. Plugin opens the existing asset-details URL, carrying only the intended non-secret asset identifier through the already established device-page mechanism.
2. The signed-in browser displays Gorelo's asset page. If an assistant is installed, it validates the exact HTTPS origin, top-level document and intended asset UUID, then compares the displayed asset identity. No automatic Connect click on page load, hash change, URL marker or message.
3. The user reviews hostname/client and presses the **original Gorelo Connect (v2) button**. The assistant may highlight/scroll to that button, but Gorelo remains responsible for session creation, auth and consent.

For a browser-action-only MV3 extension, `activeTab` plus `scripting` permits temporary injection after a browser extension action [3,4]. **The plugin opening a URL does not grant activeTab.** This least-privilege variant introduces an extra toolbar invocation when assistance is needed. An automatically appearing assistant instead needs declared content-script matching/site access scoped to `https://app.gorelo.io/*`, with additional in-script asset-route checks [5]. Do not request all sites, gateway/viewer access, cookies, debugger, webRequest, nativeMessaging or token storage for highlighting.

Content scripts normally run in an isolated JavaScript world but share the DOM; they cannot simply access Gorelo's page variables [5]. Reading the asset heading/route and locating a button is possible in principle. Calling private app functions, injecting MAIN-world network hooks, capturing responses or copying auth material is outside this proposal. DOM isolation is not a security guarantee against a compromised Gorelo page.

A userscript could perform the same limited highlighting using an existing, separately approved userscript manager. It is not a credential-safe shortcut to a launch contract: restrict its page match, avoid privileged network/storage grants and audit manager/update behavior. No particular manager or permission syntax was researched here; adopting one requires a separate source-backed choice. A userscript has the same DOM fragility and must not interpret a URL marker as permission to start Connect.

**Trade-off:** two deliberate steps remain, with no helper at all being the smallest version. A helper improves discoverability, not the underlying launch capability. New button labels, localisation, SPA routing, duplicate/hidden controls, client context and DOM redesign can break matching. On ambiguity, missing/disabled v2 control or identity mismatch: do nothing and leave the normal page usable. Never select a legacy Connect button by guesswork.

### 3. MV3 extension + native messaging host — possible, disproportionate now

A richer bridge could pass only an asset UUID and a short-lived request ID from the plugin to an extension, show browser confirmation, and then invoke Gorelo's UI. It would need a separately designed local transport.

**Important directionality:** Chrome starts a registered native host when the extension calls `runtime.connectNative()` or `sendNativeMessage()`; communication uses framed JSON over that child process's stdin/stdout [6]. A CLI cannot just start the host binary and thereby address an installed extension. `sendNativeMessage()` is request/response with only the first host message returned; a `connectNative()` port permits continuing messages while connected [6]. Plugin-originated requests would need, for example, a user-owned bounded queue read when the extension invokes its host, or an extension-established host connected to a protected local IPC endpoint. Those are additional architecture/security decisions, not existing browser features.

Host manifests allow exact extension origins, not wildcards, and Chrome/Chromium have different Linux registration locations [6]. Native-origin allowlisting does not authenticate whoever writes the local queue/socket. A production bridge needs local access controls, strict bounded schemas, expiry, single-use consumption, duplicate suppression and browser/profile selection. MV3 workers normally terminate after inactivity; a native port can keep them alive, but crashes disconnect it [7]. Pending requests must not replay into surprise sessions after restart. Always-on helper lifecycle and recovery add operational burden.

Web-to-extension `externally_connectable` is an allowlisted website messaging feature, not a CLI-to-browser IPC mechanism [8]. A localhost HTTP bridge would add a web-accessible surface and require explicit origin/authentication/replay protections; CORS alone is not proof of user intent. Do not add it merely to make native messaging work in reverse.

**Trade-off:** highest install, permissions, IPC and maintenance burden. Even authenticated native messages do not carry the plugin click's web-page transient activation. Require a fresh browser confirmation and prefer the original Gorelo button. This is still two-step; reject claims of reliable one-click launch until an approved design and authorised test establish both intent and popup behavior.

## User activation and remote-session forgery

MDN specifies that activation-triggering events are trusted input events; transient activation expires and can be consumed by `window.open()` [9]. `HTMLElement.click()` produces an untrusted click [10]. Thus a synthetic click can run a handler without creating fresh user activation. A plugin click, tab navigation, extension message or native-host message must not be assumed to transfer activation into Gorelo's document.

`window.open()` can fail with `null` when blocked; browsers require direct user input and separate gestures for new windows [11]. Here Gorelo performs an asynchronous session POST before opening the viewer. Its internal handling of activation and popup fallback is unknown. Clicking the original button preserves its normal user input path, but actual Linux browser behavior still needs an authorised test. An extension confirmation followed by asynchronous injection is **not** guaranteed equivalent. Do not pre-open replacement viewers, wrap `window.open`, capture session URLs or disable popup protection globally to work around this. If necessary, explain a narrowly scoped Gorelo-site popup setting, subject to user approval.

**Security design requirement:** treat asset URLs, query/hash markers, custom protocols, page `postMessage`, extension/content-script messages and local transport payloads as untrusted requests, not launch consent. A malicious link could navigate a signed-in browser and induce a CSRF-like remote-session start even without stealing credentials. Exact-host validation only identifies the destination; it does not establish the source or the user's intention. Rate limits and UUID validation do not solve that either.

Default to explicit browser confirmation displaying the asset identity, followed by the native Gorelo button. Do not use `navigator.userActivation.isActive` alone as a request-specific consent proof: a different interaction may have activated the page. Chrome explicitly recommends validating/sanitising content-script messages and limiting privileged actions [8]. Any later auto-launch proposal needs a reviewed, authenticated request channel and separately verified activation behavior; without trustworthy initiation proof, confirmation stays mandatory.

## Browser choice, distribution and maintenance

- The no-helper option follows the selected browser and that browser's current Gorelo login. Login/profile selection may add steps; do not copy a signed-in profile or cookies to make it seamless.
- Helpers must be installed in the browser/profile actually used. A Chrome MV3 design is not a tested Firefox or every Chromium-derivative integration. Changing the preferred-browser setting must not silently redirect to some other connected browser/profile. Unsupported/unconfigured browsers fall back to clearly labelled **Open in Gorelo**, not claimed Connect success.
- An extension needs a reviewed package, stable identity, user installation and a trusted update path. Chrome documents Web Store and Linux self-hosted distribution/update mechanisms [12]; native-host installation is separate and bound to the extension ID [6]. Browser derivatives and non-default profiles require explicit compatibility checks, not assumptions.
- For a small personal experiment, manually reviewed local code could avoid a hosted update service, but makes updates/support the user's responsibility. Production distribution, manager selection and host registration are new approval decisions. A userscript adds manager trust and its own update supply chain.
- DOM-based helpers require ongoing compatibility checks and fail-closed selectors. Do not use always-enabled remote debugging as production integration; the observation's debugging attachment was a task-specific exception, not a design precedent.

## Separate approval gate and remaining unknowns

**No new implementation approval is inferred from the approved core plan.** Recommended next decision: accept the existing two-step handoff, ask the vendor for a supported mechanism, or explicitly approve a minimal highlighting-only prototype. The native-host option is not recommended now.

Before any prototype: approve browser/profile support, exact scope/permissions, distribution/update ownership and the explicit-confirmation UX. A highlighting prototype need not start any remote session. Before synthetic UI invocation or one-click work, obtain separate approval for undocumented DOM automation and its security/maintenance trade-off.

Before live acceptance: designate one v2-enabled test asset, authorise the specific Connect action, and define viewer cleanup. Verify target/client identity, auth/consent, unavailable-device behavior, popup-blocked behavior and selected-browser/profile handling without logging viewer URLs or auth values. Outcomes should say **Opening Gorelo** / **Opening Connect**, never **Connected** based solely on browser handoff.

Unresolved: stable machine-readable asset identity in the page; selectors/localisation; trusted versus synthetic event handling; asynchronous popup behavior; tenant/region/session expiry and consent details; vendor support; supported browsers/profiles. None requires reverse-engineering the private API to report honestly.

## Public sources fetched

1. [Gorelo: What is Gorelo Connect](https://help.gorelo.io/what-is-gorelo-connect.md).
2. [Gorelo: Install Gorelo Connect](https://help.gorelo.io/install-gorelo-connect.md).
3. [Chrome: activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab).
4. [Chrome: scripting API](https://developer.chrome.com/docs/extensions/reference/api/scripting).
5. [Chrome: Content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts).
6. [Chrome: Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).
7. [Chrome: Extension service worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle).
8. [Chrome: Message passing and security considerations](https://developer.chrome.com/docs/extensions/develop/concepts/messaging).
9. [MDN: User activation](https://developer.mozilla.org/en-US/docs/Web/Security/User_activation).
10. [MDN: Event.isTrusted](https://developer.mozilla.org/en-US/docs/Web/API/Event/isTrusted).
11. [MDN: Window.open](https://developer.mozilla.org/en-US/docs/Web/API/Window/open).
12. [Chrome: Alternative installation methods](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions).
