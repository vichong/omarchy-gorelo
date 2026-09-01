.pragma library

// Pure helpers for the Gorelo public API (https://help.gorelo.io/api-overview).
// Nothing here performs I/O; Service.qml owns the XMLHttpRequest calls.

var REGIONS = [
  { id: "usw", label: "United States", host: "https://api.usw.gorelo.io" },
  { id: "aue", label: "Australia", host: "https://api.aue.gorelo.io" }
]

// Public priority scale: None=0, Urgent=1, High=2, Normal=3, Low=4.
var PRIORITIES = [
  { id: 1, name: "Urgent" },
  { id: 2, name: "High" },
  { id: 3, name: "Normal" },
  { id: 4, name: "Low" },
  { id: 0, name: "None" }
]

var CONVERSATION_PRIVATE = 2
// Ceiling on any API response body we are willing to buffer or parse. The
// largest legitimate response (200 tickets with embedded comments) stays well
// under 1 MB.
var MAX_RESPONSE_BYTES = 5 * 1024 * 1024
var DEFAULT_TICKET_URL = "https://app.gorelo.io/ticket/ticket-detail/{id}"
var DEFAULT_DEVICE_URL = "https://app.gorelo.io/asset/device-detail/{id}?hostName={name}"
var BASE_STATUS_RANK = { 1: 0, 2: 1, 6: 2, 3: 3, 4: 4 }

function errorResult(kind, message) {
  return { ok: false, status: 0, kind: String(kind || ""), error: String(message || ""),
           code: "", data: null, pagination: null }
}

function responseError(kind, message, status, code, data) {
  var result = errorResult(kind, message)
  result.status = status
  result.code = code || ""
  result.data = data === undefined ? null : data
  return result
}

function isRegion(id) {
  for (var i = 0; i < REGIONS.length; i++) if (REGIONS[i].id === id) return true
  return false
}

function baseUrl(region) {
  for (var i = 0; i < REGIONS.length; i++) if (REGIONS[i].id === region) return REGIONS[i].host
  return REGIONS[0].host
}

function regionLabel(region) {
  for (var i = 0; i < REGIONS.length; i++) if (REGIONS[i].id === region) return REGIONS[i].label
  return region
}

// { PageSize: 100, StatusIds: [1,2] } -> "?PageSize=100&StatusIds=1%2C2"
function query(params) {
  var parts = []
  for (var key in params) {
    var value = params[key]
    if (value === undefined || value === null || value === "") continue
    if (Array.isArray(value)) {
      if (value.length === 0) continue
      value = value.join(",")
    }
    parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)))
  }
  return parts.length ? "?" + parts.join("&") : ""
}

function priorityName(id) {
  for (var i = 0; i < PRIORITIES.length; i++) if (PRIORITIES[i].id === id) return PRIORITIES[i].name
  return "None"
}

// Classify an HTTP outcome. `text` is the raw body; the API wraps every
// response in { IsSuccess, Data, DataContext, Notifications }.
function parseResponse(status, text) {
  if (text && text.length > MAX_RESPONSE_BYTES) {
    return responseError("protocol", "The Gorelo API response was too large.", status, "", null)
  }
  var body = null
  try { body = text ? JSON.parse(text) : null } catch (e) { body = null }

  var notifications = body && Array.isArray(body.Notifications) ? body.Notifications : []
  var messages = []
  for (var i = 0; i < notifications.length; i++) {
    var n = notifications[i]
    if (n && n.Message) messages.push(String(n.Message))
  }
  var code = notifications.length && notifications[0] && notifications[0].Code !== undefined
    ? String(notifications[0].Code) : ""

  if (status === 0) {
    return responseError("network", "Could not reach the Gorelo API.", 0, code, null)
  }
  if (status === 401 || status === 403) {
    return responseError("credential",
      status === 401 ? "The API key was rejected." : "The API key lacks permission for this request.",
      status, code, null)
  }
  if (status === 429) {
    return responseError("ratelimit", "Rate limited by the Gorelo API.", status, code, null)
  }
  if (status < 200 || status >= 300) {
    return responseError("api",
      messages.length ? messages.join(" ") : ("Gorelo API error (HTTP " + status + ")."),
      status, code, body ? body.Data : null)
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || body.IsSuccess !== true) {
    return responseError("protocol", "The Gorelo API returned an unexpected response.", status, code, null)
  }
  var pagination = body && body.DataContext && body.DataContext.Pagination ? body.DataContext.Pagination : null
  return { ok: true, status: status, kind: "", error: "", code: code, data: body.Data, pagination: pagination }
}

function nextCursor(pagination) {
  if (!pagination || pagination.HasMore !== true) return ""
  return pagination.NextCursor ? String(pagination.NextCursor) : ""
}

// Names are how technicians recognise the closed states; the public API does
// not say which base status a status maps to.
var CLOSED_NAME = /clos|resolv|cancel|complet|done|reject/i

function isClosedStatus(status) {
  return !!(status && CLOSED_NAME.test(String(status.Name || "")))
}

function defaultStatusIds(statuses) {
  var out = []
  if (!Array.isArray(statuses)) return out
  for (var i = 0; i < statuses.length; i++) {
    if (!isClosedStatus(statuses[i]) && Number.isInteger(statuses[i].Id)) out.push(statuses[i].Id)
  }
  return out
}

function statusRank(status) {
  var rank = status ? BASE_STATUS_RANK[status.BaseStatusId] : undefined
  return typeof rank === "number" ? rank : 5
}

function sortStatuses(statuses) {
  var list = Array.isArray(statuses) ? statuses.slice() : []
  var indexed = []
  for (var i = 0; i < list.length; i++) indexed.push({ status: list[i], index: i })
  indexed.sort(function(a, b) {
    var rank = statusRank(a.status) - statusRank(b.status)
    if (rank !== 0) return rank
    var order = (a.status.SortOrder || 0) - (b.status.SortOrder || 0)
    if (order !== 0) return order
    var name = String(a.status.Name || "").localeCompare(String(b.status.Name || ""))
    return name !== 0 ? name : a.index - b.index
  })
  for (var j = 0; j < indexed.length; j++) list[j] = indexed[j].status
  return list
}

function statusColor(status) {
  if (!status || typeof status.Color !== "string") return ""
  var color = status.Color.trim()
  return /^#[0-9a-fA-F]{6}$/.test(color) ? color : ""
}

function statusIcon(status) {
  var id = status ? status.BaseStatusId : undefined
  if (id === 1) return "󰝥" // md-circle-outline
  if (id === 2) return "󱎕" // md-circle-half
  if (id === 6) return "󰍶" // md-minus-circle
  if (id === 3 || id === 4) return "󰗠" // md-check-circle
  return "󰝤" // md-circle
}

// Prototype-free map so a server-controlled id can never collide with
// Object.prototype names.
function nameMap(list, labelFn) {
  var map = Object.create(null)
  if (!Array.isArray(list)) return map
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item || item.Id === undefined || item.Id === null) continue
    map[String(item.Id)] = labelFn ? labelFn(item) : String(item.Name || "")
  }
  return map
}

function userDisplayName(user) {
  if (!user) return ""
  var name = [user.FirstName, user.LastName].filter(function(p) { return !!p }).join(" ").trim()
  return name || String(user.Email || "") || ("User " + user.Id)
}

function ticketUrl(template, ticket) {
  if (!ticket) return ""
  var t = template || DEFAULT_TICKET_URL
  return t
    .replace("{id}", encodeURIComponent(String(ticket.Id || "")))
    .replace("{number}", encodeURIComponent(String(ticket.Number || "")))
    .replace("{displayNumber}", encodeURIComponent(String(ticket.DisplayNumber || "")))
}

function deviceUrl(template, device) {
  if (!device) return ""
  var t = template || DEFAULT_DEVICE_URL
  return t
    .replace("{id}", encodeURIComponent(String(device.Id || "")))
    .replace("{name}", encodeURIComponent(String(device.Name || "")))
}

// Comment bodies are HTML; a note typed in the panel is plain text.
function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/\n/g, "<br>")
}

function validTicketList(data) {
  if (!Array.isArray(data)) return []
  var out = []
  for (var i = 0; i < data.length; i++) {
    var t = data[i]
    if (t && typeof t === "object" && t.Id !== undefined && t.Id !== null) out.push(t)
  }
  return out
}
