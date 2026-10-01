.pragma library
.import "Api.js" as Api

// Narrow mutation/read lifetime seam. Storage, queue membership and QML stay
// in Service; backend callbacks are the only asynchronous boundary here.
function create(io) {
  var pending = Object.create(null)
  var unresolved = Object.create(null)
  var epoch = 0
  var generation = 0
  function confirm(ticket, status) {
    io.confirm("Ticket #" + (ticket.Number || ticket.DisplayNumber || ticket.Id) + (Api.isClosedStatus(status) ? " closed" : " changed to " + status.Name))
  }
  function reconcile(id, operation) {
    var token = generation
    epoch++; pending[id] = "Checking status…"; io.changed()
    var completed = false
    io.backend.getTicket(id, function(result) {
      if (completed || token !== generation) return
      completed = true; epoch++; delete pending[id]
      if (!result.ok || !result.data || String(result.data.Id) !== id || !result.data.Status || !Number.isInteger(result.data.Status.Id)) {
        unresolved[id] = operation
        io.error("The status change could not be confirmed. Open in Gorelo to check; selecting again checks the status before any retry.")
      } else {
        delete unresolved[id]
        io.apply(result.data)
        if (result.data.Status.Id === operation.status.Id) confirm(operation.ticket, operation.status)
        else io.error("Gorelo currently reports " + result.data.Status.Name + ". Check in Gorelo before retrying.")
      }
      io.changed()
      if (operation.callback) {
        var done = operation.callback; operation.callback = null
        var matched = !!(result.ok && result.data && String(result.data.Id) === id && result.data.Status && result.data.Status.Id === operation.status.Id)
        done(matched, matched ? "" : "The requested status was not confirmed. Check in Gorelo before retrying.")
      }
      if (io.refresh) io.refresh()
    })
  }
  function setStatus(ticket, status, technician, callback) {
    if (status.AskForReason === true) { io.error("This status requires a reason, which the public API cannot send. Open in Gorelo to complete the change."); return false }
    var id = String(ticket.Id)
    if (pending[id]) return false
    if (unresolved[id]) { reconcile(id, unresolved[id]); return false }
    var token = generation
    epoch++
    pending[id] = Api.isClosedStatus(status) ? "Closing…" : "Saving…"
    io.changed()
    var completed = false
    io.backend.patchTicket(id, { StatusId: status.Id, UpdatedByName: technician || undefined }, function(result) {
      if (completed || token !== generation) return
      completed = true
      if (!result.ok && (result.kind === "network" || result.kind === "protocol" || result.status >= 500)) {
        reconcile(id, { ticket: ticket, status: status, callback: callback }); return
      }
      epoch++
      delete pending[id]
      if (!result.ok) {
        io.error("Status change failed: " + result.error + " Open in Gorelo to check or retry.")
        io.changed()
        if (callback) callback(false, result.error)
        if (io.refresh) io.refresh()
        return
      }
      var next = {}
      for (var key in ticket) next[key] = ticket[key]
      next.Status = status; next.StatusId = status.Id
      io.apply(next)
      io.changed()
      confirm(ticket, status)
      if (callback) callback(true, "")
      if (io.refresh) io.refresh()
    })
    return true
  }
  return {
    setStatus: setStatus, pending: function(id) { return pending[String(id)] || "" },
    beginRead: function() { return epoch },
    validRead: function(token) { return token === epoch && Object.keys(pending).length === 0 },
    reset: function() { generation++; epoch++; pending = Object.create(null); unresolved = Object.create(null); io.changed() }
  }
}
