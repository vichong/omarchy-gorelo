.pragma library
.import "Api.js" as Api

// Persisted, non-secret configuration. The API key never lives here — it is
// stored in the system keyring (see CredentialManager.qml).

var POLL_MIN = 30
var POLL_MAX = 900
var POLL_DEFAULT = 90

var KEYS = [
  "region", "demoMode", "technicianId", "technicianName", "pollSeconds", "notify",
  "notifyMinPriority", "statusIds", "defaultStatusId", "defaultGroupId",
  "defaultTypeId", "ticketUrlTemplate", "deviceUrlTemplate", "activeTab",
  "openAfterCreate", "browserDesktop"
]

var DEFAULT_TICKET_URL = "https://app.gorelo.io/ticket/ticket-detail/{id}"
var DEFAULT_DEVICE_URL = "https://app.gorelo.io/asset/device-detail/{id}?hostName={name}"

function intOr(value, fallback) {
  var n = typeof value === "number" ? value : parseInt(value, 10)
  return isNaN(n) ? fallback : n
}

function intList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var n = intOr(value[i], NaN)
    if (isNaN(n) || n <= 0 || seen[n]) continue
    seen[n] = true
    out.push(n)
  }
  return out
}

function clampPoll(value) {
  var n = intOr(value, POLL_DEFAULT)
  return Math.max(POLL_MIN, Math.min(POLL_MAX, n))
}

function httpsTemplate(value, fallback) {
  if (typeof value !== "string") return fallback
  var trimmed = value.trim()
  return trimmed.indexOf("https://") === 0 ? trimmed : fallback
}

function parse(text) {
  var raw = {}
  var error = ""
  try {
    raw = text ? JSON.parse(text) : {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      raw = {}
      error = "config.json must contain a JSON object"
    }
  } catch (exception) {
    raw = {}
    error = "config.json is not valid JSON"
  }

  return {
    error: error,
    config: {
      region: Api.isRegion(raw.region) ? raw.region : "usw",
      demoMode: raw.demoMode === true,
      technicianId: Math.max(0, intOr(raw.technicianId, 0)),
      technicianName: typeof raw.technicianName === "string" ? raw.technicianName : "",
      pollSeconds: clampPoll(raw.pollSeconds),
      notify: raw.notify !== false,
      // Lowest priority that still notifies: 1 Urgent … 4 Low, 5 everything.
      notifyMinPriority: Math.max(1, Math.min(5, intOr(raw.notifyMinPriority, 3))),
      // Empty means "every status that doesn't look closed" (Api.defaultStatusIds).
      statusIds: intList(raw.statusIds),
      defaultStatusId: Math.max(0, intOr(raw.defaultStatusId, 0)),
      defaultGroupId: Math.max(0, intOr(raw.defaultGroupId, 0)),
      defaultTypeId: Math.max(0, intOr(raw.defaultTypeId, 0)),
      ticketUrlTemplate: httpsTemplate(raw.ticketUrlTemplate, DEFAULT_TICKET_URL),
      deviceUrlTemplate: httpsTemplate(raw.deviceUrlTemplate, DEFAULT_DEVICE_URL),
      activeTab: raw.activeTab === "all" ? "all" : "mine",
      openAfterCreate: raw.openAfterCreate !== false,
      // Absolute path of a browser .desktop entry; empty means the system default.
      browserDesktop: typeof raw.browserDesktop === "string" && /^\/[^\n]+\.desktop$/.test(raw.browserDesktop)
        ? raw.browserDesktop : ""
    }
  }
}

function merge(current, patch) {
  var result = {}
  for (var i = 0; i < KEYS.length; i++) result[KEYS[i]] = current[KEYS[i]]
  for (var p = 0; p < KEYS.length; p++) {
    var key = KEYS[p]
    if (Object.prototype.hasOwnProperty.call(patch || {}, key)) result[key] = patch[key]
  }
  return result
}

function serialize(config) {
  return JSON.stringify(config, null, 2) + "\n"
}
