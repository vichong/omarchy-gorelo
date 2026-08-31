const { loadModule, assert, equal, done } = require("./helpers")
const Model = loadModule("Model.js")

const now = Date.parse("2026-08-31T10:00:00Z")
equal(Model.ageString("2026-08-31T09:59:30Z", now), "now", "age under a minute")
equal(Model.ageString("2026-08-31T09:15:00Z", now), "45m", "age in minutes")
equal(Model.ageString("2026-08-31T04:00:00Z", now), "6h", "age in hours")
equal(Model.ageString("2026-08-28T10:00:00", now), "3d", "age in days, zone-less timestamps are UTC")
equal(Model.parseIso("2026-08-31T10:00:00"), Model.parseIso("2026-08-31T10:00:00Z"), "zone-less timestamps parse as UTC")
equal(Model.ageString("", now), "", "empty timestamp")

const tickets = [
  { Id: "a", Title: "Low", Priority: { Id: 4, Name: "Low" }, UpdatedOn: "2026-08-31T09:00:00Z", LeadAssigneeId: 5, ClientId: 1, Status: { Id: 1, Name: "New" } },
  { Id: "b", Title: "Urgent", Priority: { Id: 1, Name: "Urgent" }, UpdatedOn: "2026-08-30T09:00:00Z", LeadAssigneeId: 5, ClientId: 1, IsUnread: true, Status: { Id: 1, Name: "New" } },
  { Id: "c", Title: "Normal newer", Priority: { Id: 3, Name: "Normal" }, UpdatedOn: "2026-08-31T09:30:00Z", LeadAssigneeId: 9, ClientId: 2, IsWaitingOnThem: true, Status: { Id: 2, Name: "Waiting" } },
  { Id: "d", Title: "Normal older", Priority: { Id: 3, Name: "Normal" }, UpdatedOn: "2026-08-31T08:30:00Z", ClientId: 2, Status: { Id: 2, Name: "Waiting" } },
  { Id: "e", Title: "None", Priority: { Id: 0, Name: "None" }, UpdatedOn: "2026-08-31T09:50:00Z", ClientId: 2, Status: { Id: 2, Name: "Waiting" } }
]
equal(Model.sortTickets(tickets).map(t => t.Id), ["b", "c", "d", "a", "e"], "urgent first, then newest within priority, none last")

const ctx = { clientNames: { "1": "Acme", "2": "Globex" }, userNames: { "5": "Me", "9": "Other" }, technicianId: 5, now }
const rows = Model.buildRows(tickets, ctx, t => "https://x/" + t.Id)
equal(rows[0].ticketId, "b", "rows follow sort order")
equal([rows[0].clientName, rows[0].isUnread, rows[0].mine, rows[0].url], ["Acme", true, true, "https://x/b"], "row projection")
equal([rows[1].waiting, rows[1].mine, rows[1].assigneeName], [true, false, "Other"], "waiting and assignee")
equal(rows[2].assigneeName, "Unassigned", "unassigned label")
equal(rows[0].displayNumber, "#", "display number falls back to number")

equal(Model.counts(tickets.slice(0, 3)), { total: 3, unread: 1, urgent: 1, waiting: 1 }, "counts")

const previous = Model.indexOf([tickets[0], tickets[1]])
assert(Object.getPrototypeOf(previous) === null, "index is prototype-free")
equal(Model.diffForNotifications(Object.create(null), tickets, 5, false), [], "first poll never notifies")
equal(Model.diffForNotifications(Object.create(null), [tickets[0]], 5, true).map(e => e.kind), ["assigned"], "assignment after an empty initialized queue notifies")
const next = [
  Object.assign({}, tickets[0]),
  Object.assign({}, tickets[1], { UpdatedOn: "2026-08-31T09:59:00Z", IsUnread: true }),
  tickets[2]
]
const events = Model.diffForNotifications(previous, next, 3, true)
equal(events.map(e => e.kind + ":" + e.ticket.Id), ["assigned:c"], "urgent already unread does not re-notify; new normal ticket does")
const next2 = [Object.assign({}, tickets[1], { IsUnread: false })]
const prev2 = Model.indexOf(next2)
const moved = [Object.assign({}, next2[0], { UpdatedOn: "2026-08-31T10:00:00Z", IsUnread: true })]
equal(Model.diffForNotifications(prev2, moved, 1, true).map(e => e.kind), ["updated"], "read → unread with new UpdatedOn notifies")
equal(Model.diffForNotifications(previous, [tickets[4]], 4, true), [], "priority None never notifies below 'everything'")
equal(Model.diffForNotifications(previous, [tickets[4]], 5, true).length, 1, "priority None notifies at 'everything'")
equal(Model.diffForNotifications(previous, [tickets[2]], 1, true), [], "normal ticket filtered at urgent-only")

const text = Model.notificationText({ kind: "updated", ticket: { DisplayNumber: "T-1", Title: "Printer", LastUpdate: { Summary: "Replied" } } })
equal(text, { headline: "Updated: T-1", body: "Printer — Replied" }, "notification text")

equal(Model.validateDraft({ title: " ", clientId: 1 }, { statusId: 1, groupId: 1, typeId: 1 }), "A title is required.", "draft needs title")
equal(Model.validateDraft({ title: "x", clientId: 0 }, { statusId: 1, groupId: 1, typeId: 1 }), "Pick a client.", "draft needs client")
equal(Model.validateDraft({ title: "x", clientId: 1 }, { statusId: 0, groupId: 1, typeId: 1 }), "Set a default status in Settings.", "draft needs status default")
equal(Model.validateDraft({ title: "x", clientId: 1 }, { statusId: 1, groupId: 1, typeId: 1 }), "", "valid draft")
equal(Model.attachmentFileName("/home/x/Pictures/shot.png"), "shot.png", "attachment file name")
equal(Model.priorityGlyph(1) !== Model.priorityGlyph(3), true, "priority glyphs differ")

done("test_model")
