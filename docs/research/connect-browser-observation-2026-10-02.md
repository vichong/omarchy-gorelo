# Connect v2 browser observation — 2026-10-02

An authorised inspection of a test asset in Chromium observed one Connect v2 click. Only sanitised request metadata was retained: no profile copy, cookie export, storage reads, HAR or response-body capture was used.

## Observed facts

- Source page origin: `https://app.gorelo.io`, device-detail route with the current asset UUID and hostname.
- Button: `Connect (v2)`, a button rather than an anchor.
- Click sends a `POST` to an internal regional Connect gateway, separate from the public API. The concrete origin and path are omitted.
- Request query parameter names: `api-version`, `AppType`. Values, body and headers were not collected.
- After the request, `window.open` launches a viewer on a separate regional origin with query parameter names `session` and `auth`. The concrete viewer origin is omitted.
- A timeline POST follows. This demonstrates a real launch action/side effect, not a static browser deeplink.

No session/auth values were recorded. Treat the resulting viewer URL as credential-bearing and ephemeral; expiry/reusability and exact authentication method were not inspected. This internal gateway is separate from the public API origins. No public-key compatibility is established.

## Cleanup and outcome

Temporary page observers retained only sanitised method/origin/path/query-key metadata and were removed after capture. No remote desktop input, clipboard action, file transfer or screenshot was performed. Viewer cleanup was handed back to the operator when debugging access ended; the observation did not verify session termination.

The user chose **Investigate a browser-assisted launcher before deciding**. This authorises design/research, not implementation of a browser extension, userscript, private API integration or additional remote sessions.

## Design constraints for further research

- Keep authentication and transient viewer credentials in Gorelo's browser flow. Do not extract cookies/tokens into QML, config, shell argv, logs or a native helper.
- Do not call the internal gateway with the organisation API key on speculation.
- A helper must target the intended asset, preserve auth/consent and prevent arbitrary external links from silently starting remote sessions.
- Explain browser-specific setup, popup/user-activation limits, extension permissions, maintenance burden and how the selected-browser setting would behave.
- Prefer a documented first-party launch mechanism if Gorelo supplies one later.
- Produce options and a separate approval gate; do not change the already-approved core implementation scope.
