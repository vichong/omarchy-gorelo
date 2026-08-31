.pragma library

// Projection of API tickets into what the panel shows, and the diff that
// drives desktop notifications. Pure functions; every input is validated.

var BRAND_ICON = ""   // nf-fa-ticket

function priorityRank(id) {
  // Urgent, High, Normal, Low, then None.
  if (id === 1) return 0
  if (id === 2) return 1
  if (id === 3) return 2
  if (id === 4) return 3
  return 4
}

function priorityGlyph(id) {
  if (id === 1) return "●●"
  if (id === 2) return "●"
  if (id === 3) return "○"
  if (id === 4) return "·"
  return " "
}

function priorityIdOf(ticket) {
  var p = ticket && ticket.Priority ? ticket.Priority.Id : 0
  return Number.isInteger(p) ? p : 0
}

function parseIso(value) {
  if (!value) return NaN
  var text = String(value)
  // Date.parse treats zone-less timestamps as local time on some engines.
  if (!/(Z|[+-]\d\d:\d\d)$/i.test(text)) text += "Z"
  return Date.parse(text)
}

function ageString(iso, nowMs) {
  var t = parseIso(iso)
  if (isNaN(t)) return ""
  var seconds = Math.max(0, Math.round(((nowMs || Date.now()) - t) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.round(minutes / 60)
  if (hours < 48) return hours + "h"
  var days = Math.round(hours / 24)
  if (days < 14) return days + "d"
  var weeks = Math.round(days / 7)
  if (weeks < 9) return weeks + "w"
  return Math.round(days / 30) + "mo"
}

function sortTickets(tickets) {
  var list = Array.isArray(tickets) ? tickets.slice() : []
  list.sort(function(a, b) {
    var ra = priorityRank(priorityIdOf(a))
    var rb = priorityRank(priorityIdOf(b))
    if (ra !== rb) return ra - rb
    var ta = parseIso(a.UpdatedOn) || 0
    var tb = parseIso(b.UpdatedOn) || 0
    return tb - ta
  })
  return list
}

// ctx: { clientNames, userNames, statusNames, technicianId, urlTemplate, now }
function projectRow(ticket, ctx, urlFn) {
  var priorityId = priorityIdOf(ticket)
  var assignee = Number.isInteger(ticket.LeadAssigneeId) ? ticket.LeadAssigneeId : 0
  var lastUpdate = ticket.LastUpdate && typeof ticket.LastUpdate === "object" ? ticket.LastUpdate : null
  return {
    ticketId: String(ticket.Id),
    displayNumber: String(ticket.DisplayNumber || ("#" + (ticket.Number || ""))),
    title: String(ticket.Title || "(untitled)"),
    clientName: (ctx.clientNames && ctx.clientNames[String(ticket.ClientId)]) || "",
    priorityId: priorityId,
    priorityName: ticket.Priority && ticket.Priority.Name ? String(ticket.Priority.Name) : "",
    statusId: ticket.Status && Number.isInteger(ticket.Status.Id) ? ticket.Status.Id : 0,
    statusName: ticket.Status && ticket.Status.Name ? String(ticket.Status.Name) : "",
    isUnread: ticket.IsUnread === true,
    waiting: ticket.IsWaitingOnThem === true,
    mine: assignee !== 0 && assignee === ctx.technicianId,
    assigneeId: assignee,
    assigneeName: (ctx.userNames && ctx.userNames[String(assignee)]) || (assignee ? "" : "Unassigned"),
    age: ageString(ticket.UpdatedOn, ctx.now),
    lastSummary: lastUpdate && lastUpdate.Summary ? String(lastUpdate.Summary) : "",
    url: urlFn ? urlFn(ticket) : ""
  }
}

function buildRows(tickets, ctx, urlFn) {
  var sorted = sortTickets(tickets)
  var rows = []
  for (var i = 0; i < sorted.length; i++) rows.push(projectRow(sorted[i], ctx, urlFn))
  return rows
}

function matchesQuery(rowOrTicket, ctx, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return true
  if (!rowOrTicket || typeof rowOrTicket !== "object") return false
  ctx = ctx || {}

  var item = rowOrTicket
  var isRow = item.ticketId !== undefined
  var clientId = item.ClientId === undefined ? "" : String(item.ClientId)
  var assigneeId = item.LeadAssigneeId === undefined ? "" : String(item.LeadAssigneeId)
  var statusId = item.Status && item.Status.Id !== undefined
    ? String(item.Status.Id)
    : (item.StatusId === undefined ? "" : String(item.StatusId))
  var number = isRow ? "" : String(item.Number || "")
  var displayNumber = isRow
    ? String(item.displayNumber || "")
    : String(item.DisplayNumber || (number ? "#" + number : ""))
  var fields = [
    displayNumber,
    number,
    isRow ? item.title : item.Title,
    isRow ? item.clientName : (item.ClientName || (item.Client && item.Client.Name)
      || (ctx.clientNames && ctx.clientNames[clientId])),
    isRow ? item.statusName : ((item.Status && item.Status.Name)
      || (ctx.statusNames && ctx.statusNames[statusId])),
    isRow ? item.assigneeName : (item.AssigneeName || (item.LeadAssignee && item.LeadAssignee.Name)
      || (ctx.userNames && ctx.userNames[assigneeId]))
  ]
  for (var i = 0; i < fields.length; i++) {
    if (String(fields[i] || "").toLowerCase().indexOf(needle) !== -1) return true
  }
  return false
}

function filterTickets(tickets, ctx, query) {
  if (!Array.isArray(tickets)) return []
  var needle = String(query || "").trim()
  if (!needle) return tickets.slice()
  var out = []
  for (var i = 0; i < tickets.length; i++) {
    if (matchesQuery(tickets[i], ctx || {}, needle)) out.push(tickets[i])
  }
  return out
}

function deviceOnline(device) {
  return !!(device && device.Status && /online/i.test(String(device.Status.Name || "")))
}

function deviceName(device) {
  return String((device && (device.DisplayName || device.Name)) || "")
}

function matchesDevice(device, ctx, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return true
  if (!device || typeof device !== "object") return false
  ctx = ctx || {}
  var fields = [
    device.Name,
    device.DisplayName,
    device.Description,
    device.LastLoggedOnUser,
    device.LastLoggedOnUserUpn,
    ctx.clientNames && ctx.clientNames[String(device.ClientId)],
    device.SerialNo
  ]
  for (var i = 0; i < fields.length; i++) {
    if (String(fields[i] || "").toLowerCase().indexOf(needle) !== -1) return true
  }
  return false
}

function filterDevices(devices, ctx, query, limit) {
  if (!Array.isArray(devices)) return []
  var out = []
  for (var i = 0; i < devices.length; i++) {
    if (matchesDevice(devices[i], ctx || {}, query)) out.push(devices[i])
  }
  out.sort(function(a, b) {
    var onlineDifference = (deviceOnline(b) ? 1 : 0) - (deviceOnline(a) ? 1 : 0)
    if (onlineDifference !== 0) return onlineDifference
    return deviceName(a).toLowerCase().localeCompare(deviceName(b).toLowerCase())
  })
  var cap = Number.isInteger(limit) ? Math.max(0, limit) : out.length
  return out.slice(0, cap)
}

function projectDeviceRow(device, ctx, urlFn) {
  ctx = ctx || {}
  var online = deviceOnline(device)
  return {
    deviceId: String(device.Id),
    name: deviceName(device),
    hostName: String(device.Name || ""),
    clientName: (ctx.clientNames && ctx.clientNames[String(device.ClientId)]) || "",
    statusName: device.Status && device.Status.Name ? String(device.Status.Name) : "",
    online: online,
    lastUser: String(device.LastLoggedOnUser || device.LastLoggedOnUserUpn || ""),
    os: String(device.OsName || device.Os || ""),
    lastSeen: online ? "" : ageString(device.LastDisconnectDateTime, ctx.now),
    localIp: String(device.LocalIPAddress || ""),
    publicIp: String(device.PublicIPAddress || ""),
    url: urlFn ? urlFn(device) : ""
  }
}

function counts(tickets) {
  var out = { total: 0, unread: 0, urgent: 0, waiting: 0 }
  if (!Array.isArray(tickets)) return out
  for (var i = 0; i < tickets.length; i++) {
    var t = tickets[i]
    out.total++
    if (t.IsUnread === true) out.unread++
    if (t.IsWaitingOnThem === true) out.waiting++
    var p = priorityIdOf(t)
    if (p === 1 || p === 2) out.urgent++
  }
  return out
}

function indexOf(tickets) {
  var map = Object.create(null)
  if (!Array.isArray(tickets)) return map
  for (var i = 0; i < tickets.length; i++) {
    var t = tickets[i]
    map[String(t.Id)] = { updatedOn: String(t.UpdatedOn || ""), unread: t.IsUnread === true }
  }
  return map
}

// minPriority: lowest priority that still notifies (1 Urgent … 4 Low, 5 all).
function notifies(priorityId, minPriority) {
  if (minPriority >= 5) return true
  if (priorityId === 0) return false
  return priorityId <= minPriority
}

// Compare the tickets assigned to me against the previous poll. New ids are
// "assigned"; known ids whose UpdatedOn moved and that are now unread are
// "updated". The explicitly identified first poll reports nothing.
function diffForNotifications(previous, tickets, minPriority, initialized) {
  var events = []
  if (!initialized) return events
  if (!previous) previous = Object.create(null)
  if (!Array.isArray(tickets)) return events
  for (var i = 0; i < tickets.length; i++) {
    var t = tickets[i]
    var key = String(t.Id)
    var was = previous[key]
    if (!notifies(priorityIdOf(t), minPriority)) continue
    if (!was) {
      events.push({ kind: "assigned", ticket: t })
    } else if (String(t.UpdatedOn || "") !== was.updatedOn && t.IsUnread === true && !was.unread) {
      events.push({ kind: "updated", ticket: t })
    }
  }
  return events
}

function notificationText(event) {
  var t = event.ticket
  var number = String(t.DisplayNumber || ("#" + (t.Number || "")))
  var headline = event.kind === "assigned"
    ? "Assigned to you: " + number
    : "Updated: " + number
  var body = String(t.Title || "")
  if (t.LastUpdate && t.LastUpdate.Summary && event.kind === "updated") {
    body += " — " + String(t.LastUpdate.Summary)
  }
  return { headline: headline, body: body }
}

function emptyDraft() {
  return { title: "", description: "", clientId: 0, priorityId: 3, attachmentPath: "" }
}

function validateDraft(draft, defaults) {
  if (!draft || !String(draft.title || "").trim()) return "A title is required."
  if (!draft.clientId) return "Pick a client."
  if (!defaults.statusId) return "Set a default status in Settings."
  if (!defaults.groupId) return "Set a default group in Settings."
  if (!defaults.typeId) return "Set a default type in Settings."
  return ""
}

function attachmentFileName(path) {
  var s = String(path || "")
  var slash = s.lastIndexOf("/")
  return slash === -1 ? s : s.slice(slash + 1)
}
