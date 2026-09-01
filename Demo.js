.pragma library

// Pure, fresh demo fixtures. Dates are generated when requested so the panel
// always shows useful live-looking ages; callers own and may mutate the arrays.

function ago(now, milliseconds) {
  return new Date(now - milliseconds).toISOString()
}

function demoReference() {
  return {
    clients: [
      { Id: 1, Name: "Acme Pty Ltd" },
      { Id: 2, Name: "Globex" },
      { Id: 3, Name: "Initech" },
      { Id: 4, Name: "Wayne Enterprises" }
    ],
    statuses: [
      // Gorelo's out-of-the-box statuses and colours (as created with a new
      // tenancy): New, Open, On Hold, Solved, Closed.
      { Id: 1, Name: "New", SortOrder: 1, Color: "#FF5252", BaseStatusId: 1 },
      { Id: 2, Name: "Open", SortOrder: 1, Color: "#DF7E00", BaseStatusId: 2 },
      { Id: 3, Name: "On Hold", SortOrder: 1, Color: "#2196F3", BaseStatusId: 6 },
      { Id: 4, Name: "Solved", SortOrder: 1, Color: "#4CAF50", BaseStatusId: 3 },
      { Id: 5, Name: "Closed", SortOrder: 1, Color: "#939dac", BaseStatusId: 4 }
    ],
    groups: [
      { Id: 1, Name: "Service Desk" },
      { Id: 2, Name: "Projects" }
    ],
    types: [
      { Id: 1, Name: "Incident" },
      { Id: 2, Name: "Service Request" },
      { Id: 3, Name: "Change" }
    ],
    users: [
      { Id: 1, FirstName: "Demo", LastName: "Tech", Email: "demo.tech@example.invalid" },
      { Id: 2, FirstName: "Alex", LastName: "Morgan", Email: "alex.morgan@example.invalid" },
      { Id: 3, FirstName: "Sam", LastName: "Rivera", Email: "sam.rivera@example.invalid" }
    ]
  }
}

function ticket(id, title, clientId, statusId, assigneeId, priorityId,
                updatedOn, unread, waiting, summary) {
  var reference = demoReference()
  var status = reference.statuses[statusId - 1]
  var priorityNames = ["None", "Urgent", "High", "Normal", "Low"]
  return {
    Id: "demo-ticket-" + id,
    Number: id,
    DisplayNumber: "DEMO-" + id,
    Title: title,
    ClientId: clientId,
    StatusId: statusId,
    Status: { Id: status.Id, Name: status.Name },
    GroupId: statusId >= 4 ? 2 : 1,
    TypeId: statusId === 3 ? 2 : 1,
    LeadAssigneeId: assigneeId,
    Priority: { Id: priorityId, Name: priorityNames[priorityId] },
    UpdatedOn: updatedOn,
    IsUnread: unread === true,
    IsWaitingOnThem: waiting === true,
    LastUpdate: { Summary: summary }
  }
}

function demoTickets(now) {
  var at = typeof now === "number" ? now : Date.now()
  var minute = 60 * 1000
  var hour = 60 * minute
  var day = 24 * hour
  return [
    ticket(1042, "Backup failed on domain controller", 1, 1, 1, 1,
           ago(at, 8 * minute), true, false, "Nightly image backup failed with a VSS writer error."),
    ticket(1043, "VPN drop-outs for remote team", 2, 2, 2, 1,
           ago(at, 42 * minute), true, false, "Three users disconnected during the morning peak."),
    ticket(1044, "Finance printer jams on every duplex job", 1, 2, 1, 2,
           ago(at, 2 * hour), false, false, "Roller kit ordered; temporary queue is available."),
    ticket(1045, "Shared mailbox is full", 3, 1, 1, 2,
           ago(at, 5 * hour), true, false, "Archive policy is not moving items older than two years."),
    ticket(1046, "New starter onboarding for Priya Shah", 4, 2, 1, 2,
           ago(at, 21 * hour), false, false, "Laptop is built and waiting for manager approval."),
    ticket(1047, "Laptop battery drains while asleep", 2, 3, 1, 3,
           ago(at, 2 * day), false, true, "Asked the user for a battery report after the BIOS update."),
    ticket(1048, "MFA reset after phone replacement", 1, 1, 1, 3,
           ago(at, 3 * day), true, false, "Identity confirmed with the client's authorised contact."),
    ticket(1049, "Microsoft 365 licence renewal", 3, 3, 1, 3,
           ago(at, 5 * day), false, true, "Quote sent for approval before the renewal date."),
    ticket(1050, "Reception Wi-Fi cannot reach guest portal", 4, 2, 3, 3,
           ago(at, 8 * day), false, false, "Access point logs show intermittent DNS timeouts."),
    ticket(1051, "Accounts application running slowly", 2, 3, 1, 3,
           ago(at, 11 * day), false, true, "Waiting for a screen recording from the accounts team."),
    ticket(1052, "Replace expiring firewall certificate", 1, 4, 2, 3,
           ago(at, 15 * day), false, false, "Certificate replaced and monitoring checks are green."),
    ticket(1053, "Teams camera unavailable in meeting rooms", 4, 2, 1, 3,
           ago(at, 19 * day), false, false, "USB firmware update fixed two of three rooms."),
    ticket(1054, "Archive former employee mailbox", 3, 5, 3, 4,
           ago(at, 24 * day), false, false, "Mailbox exported and retention hold confirmed."),
    ticket(1055, "Replace worn label printer", 2, 4, 3, 4,
           ago(at, 28 * day), false, false, "Replacement installed and test labels printed cleanly.")
  ]
}

function device(id, name, displayName, clientId, online, user, os, localIp,
                publicIp, disconnectedOn) {
  return {
    Id: "demo-device-" + id,
    Name: name,
    DisplayName: displayName,
    ClientId: clientId,
    Status: { Id: online ? 1 : 2, Name: online ? "Online" : "Offline" },
    LastLoggedOnUser: user,
    OsName: os,
    LocalIPAddress: localIp,
    PublicIPAddress: publicIp,
    LastDisconnectDateTime: online ? "" : disconnectedOn
  }
}

function demoDevices(now) {
  var at = typeof now === "number" ? now : Date.now()
  var hour = 60 * 60 * 1000
  var day = 24 * hour
  return [
    device(1, "ACME-DC01", "Acme Domain Controller", 1, true, "ACME\\administrator", "Windows Server 2022", "10.10.0.10", "203.0.113.10", ""),
    device(2, "ACME-LT-014", "Jordan's Laptop", 1, true, "ACME\\jsmith", "Windows 11 Pro", "10.10.1.44", "203.0.113.10", ""),
    device(3, "GLOBEX-RDS01", "Globex Remote Desktop", 2, false, "GLOBEX\\mchen", "Windows Server 2019", "10.20.0.20", "198.51.100.24", ago(at, 3 * hour)),
    device(4, "GLOBEX-WS-022", "Reception Workstation", 2, true, "GLOBEX\\reception", "Windows 11 Pro", "10.20.1.22", "198.51.100.24", ""),
    device(5, "INITECH-LT-007", "Peter's Laptop", 3, false, "INITECH\\pgibbons", "Windows 11 Enterprise", "10.30.1.17", "192.0.2.33", ago(at, 2 * day)),
    device(6, "INITECH-FS01", "Initech File Server", 3, true, "INITECH\\svc_backup", "Windows Server 2022", "10.30.0.12", "192.0.2.33", ""),
    device(7, "WAYNE-EXEC-01", "Executive Laptop", 4, true, "WAYNE\\bwayne", "Windows 11 Pro", "10.40.1.5", "203.0.113.72", ""),
    device(8, "WAYNE-WH-03", "Warehouse Tablet", 4, false, "WAYNE\\warehouse", "Windows 10 IoT", "10.40.2.38", "203.0.113.72", ago(at, 9 * day))
  ]
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// The demo backend owns one of these values. Every operation returns a fresh
// store, keeping the state transitions deterministic and node-testable.
function createStore(now) {
  var at = typeof now === "number" ? now : Date.now()
  return {
    reference: demoReference(),
    tickets: demoTickets(at),
    devices: demoDevices(at),
    showcaseCount: 0,
    showcased: false
  }
}

function ticketIndex(store, id) {
  var tickets = store && Array.isArray(store.tickets) ? store.tickets : []
  for (var i = 0; i < tickets.length; i++) if (String(tickets[i].Id) === String(id)) return i
  return -1
}

function statusFor(store, id) {
  var statuses = store && store.reference && Array.isArray(store.reference.statuses)
    ? store.reference.statuses : []
  for (var i = 0; i < statuses.length; i++) if (statuses[i].Id === id) return statuses[i]
  return null
}

function applyPatch(store, id, patch, now) {
  var next = clone(store)
  var index = ticketIndex(next, id)
  if (index === -1) return { store: next, ticket: null }
  var target = next.tickets[index]
  var changes = patch && typeof patch === "object" ? patch : {}
  for (var key in changes) {
    if (!Object.prototype.hasOwnProperty.call(changes, key) || changes[key] === undefined) continue
    if (key === "StatusId") {
      var statusId = parseInt(changes[key], 10)
      var status = statusFor(next, statusId)
      if (status) {
        target.StatusId = statusId
        target.Status = { Id: statusId, Name: String(status.Name) }
      }
    } else {
      target[key] = changes[key]
    }
  }
  target.UpdatedOn = new Date(typeof now === "number" ? now : Date.now()).toISOString()
  target.IsUnread = false
  target.LastUpdate = { Summary: "Updated by Demo Tech." }
  return { store: next, ticket: target }
}

function addComment(store, id, payload, now) {
  var result = applyPatch(store, id, {}, now)
  if (result.ticket) {
    var text = payload && payload.PlainBody !== undefined ? payload.PlainBody
      : (payload && payload.Body !== undefined ? payload.Body : "")
    result.ticket.LastUpdate = { Summary: String(text || "") }
  }
  return result
}

function priorityName(id) {
  return ["None", "Urgent", "High", "Normal", "Low"][id] || "None"
}

function createTicket(store, body, now) {
  var next = clone(store)
  var number = 1000
  for (var i = 0; i < next.tickets.length; i++) number = Math.max(number, parseInt(next.tickets[i].Number, 10) || 0)
  number++
  var status = statusFor(next, body.StatusId) || { Id: body.StatusId, Name: "New" }
  var created = {
    Id: "demo-ticket-" + number,
    Number: number,
    DisplayNumber: "DEMO-" + number,
    Title: String(body.Title || ""),
    Description: String(body.Description || ""),
    ClientId: body.ClientId,
    StatusId: body.StatusId,
    Status: { Id: status.Id, Name: String(status.Name) },
    GroupId: body.GroupId,
    TypeId: body.TypeId,
    LeadAssigneeId: body.LeadAssigneeId || 1,
    Priority: { Id: body.PriorityId, Name: priorityName(body.PriorityId) },
    UpdatedOn: new Date(typeof now === "number" ? now : Date.now()).toISOString(),
    IsUnread: false,
    IsWaitingOnThem: false,
    LastUpdate: { Summary: String(body.Description || "Created from the Omarchy demo.") }
  }
  next.tickets.push(created)
  return { store: next, ticket: created }
}

function contains(value, needle) {
  return String(value || "").toLowerCase().indexOf(needle) !== -1
}

function referenceName(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i].Id === id) return String(list[i].Name || "")
  return ""
}

function search(store, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return { tickets: store.tickets.slice(), devices: store.devices.slice() }
  var clients = store.reference.clients
  var users = store.reference.users
  var tickets = store.tickets.filter(function(item) {
    var user = null
    for (var i = 0; i < users.length; i++) if (users[i].Id === item.LeadAssigneeId) user = users[i]
    return contains(item.DisplayNumber, needle) || contains(item.Number, needle)
      || contains(item.Title, needle) || contains(referenceName(clients, item.ClientId), needle)
      || contains(item.Status && item.Status.Name, needle)
      || contains(user && (String(user.FirstName || "") + " " + String(user.LastName || "")), needle)
  })
  var devices = store.devices.filter(function(item) {
    return contains(item.Name, needle) || contains(item.DisplayName, needle)
      || contains(item.Description, needle) || contains(item.LastLoggedOnUser, needle)
      || contains(item.LastLoggedOnUserUpn, needle) || contains(item.SerialNo, needle)
      || contains(referenceName(clients, item.ClientId), needle)
  })
  return { tickets: tickets, devices: devices }
}

function nextShowcase(store, now) {
  var next = clone(store)
  if (next.showcaseCount === 1 && !next.showcased) {
    for (var i = 0; i < next.tickets.length; i++) {
      var candidate = next.tickets[i]
      if (candidate.Priority && candidate.Priority.Id === 1 && candidate.LeadAssigneeId !== 1) {
        candidate.LeadAssigneeId = 1
        candidate.UpdatedOn = new Date(typeof now === "number" ? now : Date.now()).toISOString()
        candidate.IsUnread = true
        candidate.LastUpdate = { Summary: "Assigned to Demo Tech for immediate follow-up." }
        next.showcased = true
        break
      }
    }
  }
  next.showcaseCount++
  return next
}
