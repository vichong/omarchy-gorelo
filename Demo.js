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
      { Id: 1, Name: "New", SortOrder: 10, Color: "#e72525" },
      { Id: 2, Name: "In Progress", SortOrder: 20, Color: "#f29100" },
      { Id: 3, Name: "Waiting on Client", SortOrder: 30, Color: "#b5ce00" },
      { Id: 4, Name: "Resolved", SortOrder: 40, Color: "#71d0bb" },
      { Id: 5, Name: "Closed", SortOrder: 50, Color: "#6fba2c" }
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
