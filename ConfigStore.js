.pragma library

// Persisted, non-secret configuration. The API key never lives here — it is
// stored in the system keyring (see CredentialManager.qml).

var REGIONS = ["usw", "aue"]

var KEYS = [
  "region", "technicianId", "technicianName", "pollSeconds", "notify",
  "notifyMinPriority", "statusIds", "defaultStatusId", "defaultGroupId",
  "defaultTypeId", "defaultClientId", "ticketUrlTemplate", "activeTab",
  "openAfterCreate"
]

var DEFAULT_TICKET_URL = "https://app.gorelo.io/Ticket/{id}"

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
  var n = intOr(value, 90)
  return Math.max(30, Math.min(900, n))
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
      region: REGIONS.indexOf(raw.region) !== -1 ? raw.region : "usw",
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
      defaultClientId: Math.max(0, intOr(raw.defaultClientId, 0)),
      ticketUrlTemplate: typeof raw.ticketUrlTemplate === "string" && raw.ticketUrlTemplate.trim()
        ? raw.ticketUrlTemplate.trim() : DEFAULT_TICKET_URL,
      activeTab: raw.activeTab === "all" ? "all" : "mine",
      openAfterCreate: raw.openAfterCreate !== false
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
