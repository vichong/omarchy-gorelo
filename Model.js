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
  var t = Date.parse(String(value))
  if (!isNaN(t)) return t
  // Timestamps without a zone designator are UTC.
  return Date.parse(String(value) + "Z")
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
// "updated". The very first poll (empty previous index) reports nothing.
function diffForNotifications(previous, tickets, minPriority) {
  var events = []
  if (!previous || Object.keys(previous).length === 0) return events
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
