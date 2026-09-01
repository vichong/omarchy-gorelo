const { loadModule, assert, equal, done } = require("./helpers")
const ConfigStore = loadModule("ConfigStore.js")

const empty = ConfigStore.parse("")
equal(empty.error, "", "empty config is fine")
equal([empty.config.region, empty.config.demoMode, empty.config.pollSeconds, empty.config.notify, empty.config.notifyMinPriority, empty.config.activeTab],
  ["usw", false, 90, true, 3, "mine"], "defaults")

const bad = ConfigStore.parse("{nope")
equal(bad.error, "config.json is not valid JSON", "invalid json reported")
equal(bad.config.region, "usw", "invalid json still yields defaults")

const parsed = ConfigStore.parse(JSON.stringify({
  region: "aue", demoMode: true, technicianId: "12", pollSeconds: 5, notifyMinPriority: 9,
  statusIds: [1, "2", 2, -1, "x"], ticketUrlTemplate: "  ", activeTab: "all", apiKey: "leak"
}))
equal([parsed.config.region, parsed.config.technicianId, parsed.config.pollSeconds, parsed.config.notifyMinPriority],
  ["aue", 12, 30, 5], "coercion and clamping")
equal(parsed.config.demoMode, true, "demo mode is explicitly enabled")
equal(parsed.config.statusIds, [1, 2], "status ids deduplicated and validated")
equal(parsed.config.ticketUrlTemplate, ConfigStore.DEFAULT_TICKET_URL, "blank template falls back")
equal(parsed.config.deviceUrlTemplate, ConfigStore.DEFAULT_DEVICE_URL, "device template defaults")
equal(parsed.config.activeTab, "all", "tab")
assert(!("apiKey" in parsed.config), "unknown keys (including a stray apiKey) are dropped")
assert(!("defaultClientId" in parsed.config), "dead default client key is dropped")

const merged = ConfigStore.merge(parsed.config, { pollSeconds: 120, apiKey: "leak" })
equal(merged.pollSeconds, 120, "merge applies known keys")
assert(!("apiKey" in merged), "merge never carries a key")
assert(ConfigStore.serialize(merged).indexOf("leak") === -1, "serialized config never contains a key")
equal(ConfigStore.parse("{\"region\":\"eu\"}").config.region, "usw", "unknown region falls back")
equal(ConfigStore.parse(JSON.stringify({ browserDesktop: "/usr/share/applications/chromium.desktop" })).config.browserDesktop,
  "/usr/share/applications/chromium.desktop", "browser desktop path kept")
equal(ConfigStore.parse(JSON.stringify({ browserDesktop: "chromium" })).config.browserDesktop, "", "relative browser value rejected")
equal(ConfigStore.parse(JSON.stringify({ browserDesktop: "/tmp/x.desktop\nrm" })).config.browserDesktop, "", "browser value with newline rejected")
equal(empty.config.browserDesktop, "", "browser defaults to system default")
equal([ConfigStore.POLL_MIN, ConfigStore.POLL_MAX, ConfigStore.POLL_DEFAULT], [30, 900, 90],
  "poll bounds are exported for QML controls")
equal(ConfigStore.parse(JSON.stringify({ deviceUrlTemplate: " https://x/{id}/{name} " })).config.deviceUrlTemplate,
  "https://x/{id}/{name}", "device template is trimmed")
equal(ConfigStore.parse(JSON.stringify({ ticketUrlTemplate: "http://x/{id}" })).config.ticketUrlTemplate,
  ConfigStore.DEFAULT_TICKET_URL, "insecure ticket template falls back")
equal(ConfigStore.parse(JSON.stringify({ deviceUrlTemplate: "javascript:alert(1)" })).config.deviceUrlTemplate,
  ConfigStore.DEFAULT_DEVICE_URL, "non-HTTPS device template falls back")
equal(ConfigStore.parse(JSON.stringify({ ticketUrlTemplate: "HTTPS://x/{id}" })).config.ticketUrlTemplate,
  ConfigStore.DEFAULT_TICKET_URL, "template must start with lowercase https scheme")
equal(ConfigStore.parse(JSON.stringify({ ticketUrlTemplate: " https://app.gorelo.io/Ticket/{id} " })).config.ticketUrlTemplate,
  ConfigStore.DEFAULT_TICKET_URL, "old ticket template migrates to the new default")
equal(ConfigStore.parse(JSON.stringify({ ticketUrlTemplate: " https://example.com/tickets/{id} " })).config.ticketUrlTemplate,
  "https://example.com/tickets/{id}", "custom ticket template is untouched")

done("test_config")
