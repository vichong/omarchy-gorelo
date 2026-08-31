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

const searchable = [
  { Id: "s1", DisplayNumber: "INC-1042", Number: 1042, Title: "Printer offline", ClientId: 1,
    LeadAssigneeId: 5, Status: { Id: 1, Name: "In Progress" } },
  { Id: "s2", Number: 2088, Title: "Replace firewall", ClientId: 2,
    LeadAssigneeId: 9, Status: { Id: 2, Name: "Waiting" } }
]
equal(Model.filterTickets(searchable, ctx, "INC-1042").map(t => t.Id), ["s1"], "display number matches with prefix")
equal(Model.filterTickets(searchable, ctx, "1042").map(t => t.Id), ["s1"], "ticket number matches without prefix")
equal(Model.filterTickets(searchable, ctx, "printer").map(t => t.Id), ["s1"], "title substring matches")
equal(Model.filterTickets(searchable, ctx, "globex").map(t => t.Id), ["s2"], "client name matches")
equal(Model.filterTickets(searchable, ctx, "in progress").map(t => t.Id), ["s1"], "status name matches")
equal(Model.filterTickets(searchable, ctx, "other").map(t => t.Id), ["s2"], "assignee name matches")
equal(Model.filterTickets(searchable, ctx, "gLoBeX").map(t => t.Id), ["s2"], "matching is case-insensitive")
equal(Model.filterTickets(searchable, ctx, ""), searchable, "empty query returns everything")
equal(Model.filterTickets(searchable, ctx, "   \t"), searchable, "whitespace-only query returns everything")

const devices = [
  { Id: "d1", Name: "WS-ALPHA", DisplayName: "Ada Laptop", Description: "Design workstation",
    ClientId: 1, LastLoggedOnUser: "Ada", LastLoggedOnUserUpn: "ada@example.com", SerialNo: "SER-1",
    Status: { Id: 1, Name: "Online" }, OsName: "Windows 11", LocalIPAddress: "10.0.0.2", PublicIPAddress: "1.2.3.4" },
  { Id: "d2", Name: "WS-BETA", ClientId: 2, LastLoggedOnUserUpn: "bob@example.com", SerialNo: "SER-2",
    Status: { Id: 2, Name: "Disconnected" }, Os: "Windows", LastDisconnectDateTime: "2026-08-31T09:00:00Z" },
  { Id: "d3", Name: "SERVER-Z", ClientId: 1, Status: { Name: "ONLINE - idle" } }
]
equal(Model.matchesDevice(devices[0], ctx, "alpha"), true, "device host name matches")
equal(Model.matchesDevice(devices[0], ctx, "ada laptop"), true, "device display name matches")
equal(Model.matchesDevice(devices[0], ctx, "design"), true, "device description matches")
equal(Model.matchesDevice(devices[0], ctx, "ada"), true, "last logged-on user matches")
equal(Model.matchesDevice(devices[1], ctx, "bob@example"), true, "last logged-on UPN matches")
equal(Model.matchesDevice(devices[1], ctx, "globex"), true, "device client name matches")
equal(Model.matchesDevice(devices[0], ctx, "ser-1"), true, "device serial matches")
equal(Model.matchesDevice(devices[1], ctx, "nope"), false, "unrelated device does not match")
equal(Model.filterDevices(devices, ctx, "", 2).map(d => d.Id), ["d1", "d3"], "devices sort online first and respect limit")
equal(Model.filterDevices(devices, ctx, "", 8).map(d => d.Id), ["d1", "d3", "d2"], "devices sort by display or host name")
const refreshedDevice = Object.assign({}, devices[0], { DisplayName: "Ada's new laptop" })
equal(Model.mergeDevices(devices, [refreshedDevice]).find(d => d.Id === "d1").DisplayName,
  "Ada's new laptop", "device additions replace matching base records")
equal(Model.updateDeviceHits([devices[0], devices[1]], [refreshedDevice, devices[2]], 2).map(d => d.Id),
  ["d1", "d3"], "recent direct hits replace old values, move forward, and respect their cap")
const deviceRow = Model.projectDeviceRow(devices[1], ctx, d => "https://x/" + d.Id)
equal([deviceRow.deviceId, deviceRow.name, deviceRow.hostName, deviceRow.clientName], ["d2", "WS-BETA", "WS-BETA", "Globex"], "device identity projection")
equal([deviceRow.online, deviceRow.statusName, deviceRow.lastUser, deviceRow.lastSeen], [false, "Disconnected", "bob@example.com", "1h"], "offline device projection")
equal([deviceRow.os, deviceRow.url], ["Windows", "https://x/d2"], "device detail projection")
equal(Model.projectDeviceRow(devices[0], ctx).lastSeen, "", "online device has no last-seen age")

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
const tag = Model.notificationTag("ticket-123")
assert(Number.isInteger(tag) && tag > 0 && tag <= 0xffffffff, "notification tag is a positive uint32")
equal(Model.notificationTag("ticket-123"), tag, "notification tag is stable")
assert(Model.notificationTag("ticket-124") !== tag, "different ticket ids get different notification tags")
equal(Model.escapeMarkup("AT&T <urgent> > normal"), "AT&amp;T &lt;urgent&gt; &gt; normal", "notification markup is escaped")
const fiveEvents = [1, 2, 3, 4, 5]
equal(Model.summarizeNotificationEvents(fiveEvents, 5), { events: fiveEvents, summary: "" }, "notification cap allows individual events")
equal(Model.summarizeNotificationEvents(fiveEvents.concat(6), 5),
  { events: [], summary: "6 tickets assigned or updated" }, "events above the cap become one summary")
equal(Model.summarizeNotificationEvents(null, 5), { events: [], summary: "" }, "invalid notification events are empty")

equal(Model.validateDraft({ title: " ", clientId: 1 }, { statusId: 1, groupId: 1, typeId: 1 }), "A title is required.", "draft needs title")
equal(Model.validateDraft({ title: "x", clientId: 0 }, { statusId: 1, groupId: 1, typeId: 1 }), "Pick a client.", "draft needs client")
equal(Model.validateDraft({ title: "x", clientId: 1 }, { statusId: 0, groupId: 1, typeId: 1 }), "Set a default status in Settings.", "draft needs status default")
equal(Model.validateDraft({ title: "x", clientId: 1 }, { statusId: 1, groupId: 1, typeId: 1 }), "", "valid draft")
equal(Model.attachmentFileName("/home/x/Pictures/shot.png"), "shot.png", "attachment file name")
equal(Model.priorityGlyph(1) !== Model.priorityGlyph(3), true, "priority glyphs differ")

done("test_model")
