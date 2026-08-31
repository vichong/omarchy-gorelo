const { loadModule, assert, equal, done } = require("./helpers")
const Demo = loadModule("Demo.js")

const now = Date.parse("2026-08-31T10:00:00Z")
const reference = Demo.demoReference()
const tickets = Demo.demoTickets(now)
const devices = Demo.demoDevices(now)

equal([reference.clients.length, reference.statuses.length, reference.groups.length,
  reference.types.length, reference.users.length], [4, 5, 2, 3, 3], "reference fixture counts")
equal(tickets.length, 14, "ticket fixture count")
equal(devices.length, 8, "device fixture count")

const priorityCounts = { 1: 0, 2: 0, 3: 0, 4: 0 }
tickets.forEach(ticket => { priorityCounts[ticket.Priority.Id]++ })
equal(priorityCounts, { 1: 2, 2: 3, 3: 7, 4: 2 }, "documented priority distribution")
equal(tickets.filter(ticket => ticket.LeadAssigneeId === 1).length, 9,
  "nine tickets start assigned to Demo Tech")

const clientIds = new Set(reference.clients.map(item => item.Id))
const statusIds = new Set(reference.statuses.map(item => item.Id))
const userIds = new Set(reference.users.map(item => item.Id))
tickets.forEach(ticket => {
  assert(clientIds.has(ticket.ClientId), ticket.DisplayNumber + " has a fixture client")
  assert(statusIds.has(ticket.StatusId), ticket.DisplayNumber + " has a fixture status id")
  equal(ticket.Status.Id, ticket.StatusId, ticket.DisplayNumber + " has a consistent status object")
  assert(userIds.has(ticket.LeadAssigneeId), ticket.DisplayNumber + " has a fixture assignee")
})

equal(new Set(tickets.map(ticket => ticket.DisplayNumber)).size, tickets.length,
  "ticket display numbers are unique")
assert(devices.some(device => device.Status.Name === "Online"), "devices include an online entry")
assert(devices.some(device => device.Status.Name === "Offline"), "devices include an offline entry")
devices.forEach(device => {
  assert(clientIds.has(device.ClientId), device.Name + " has a fixture client")
})
assert(tickets.some(ticket => {
  const age = now - Date.parse(ticket.UpdatedOn)
  return age >= 0 && age <= 5 * 7 * 24 * 60 * 60 * 1000
}), "ticket ages are relative to the supplied time")

const store = Demo.createStore(now)
equal([store.tickets.length, store.devices.length, store.showcaseCount], [14, 8, 0], "store starts from fixtures")
const patched = Demo.applyPatch(store, "demo-ticket-1042", { StatusId: 3, LeadAssigneeId: 2 }, now + 1000)
equal([patched.ticket.Status.Name, patched.ticket.LeadAssigneeId, patched.ticket.IsUnread],
  ["Waiting on Client", 2, false], "patch updates status and assignment")
equal(store.tickets.find(ticket => ticket.Id === "demo-ticket-1042").StatusId, 1, "patch does not mutate input")
const commented = Demo.addComment(patched.store, "demo-ticket-1042", { PlainBody: "Checked backups" }, now + 2000)
equal(commented.ticket.LastUpdate.Summary, "Checked backups", "comment becomes the demo summary")
const created = Demo.createTicket(store, {
  Title: "New demo ticket", ClientId: 1, StatusId: 1, GroupId: 1, TypeId: 1, PriorityId: 2, LeadAssigneeId: 1
}, now + 3000)
equal([created.store.tickets.length, created.ticket.DisplayNumber, created.ticket.Priority.Name],
  [15, "DEMO-1056", "High"], "create appends a fully projected ticket")
equal(Demo.search(store, "globex").devices.length, 2, "search finds devices by client")
equal(Demo.search(store, "backup failed").tickets.map(ticket => ticket.Id), ["demo-ticket-1042"],
  "search finds ticket title")
const showcase1 = Demo.nextShowcase(store, now + 4000)
const showcase2 = Demo.nextShowcase(showcase1, now + 5000)
equal(showcase1.showcased, false, "first showcase tick leaves fixtures alone")
equal(showcase2.tickets.filter(ticket => ticket.LeadAssigneeId === 1).length, 10,
  "second showcase tick assigns one urgent ticket")
equal(Demo.nextShowcase(showcase2, now + 6000).tickets.filter(ticket => ticket.LeadAssigneeId === 1).length, 10,
  "showcase assignment happens once")

done("test_demo")
