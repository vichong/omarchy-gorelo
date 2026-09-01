import QtQuick
import "Api.js" as Api
import "Demo.js" as Demo
import "Model.js" as Model

// In-memory implementation of the same interface as LiveBackend.
QtObject {
  id: root
  property var store: Demo.createStore(Date.now())
  property var deleteAttachment: null
  property var referenceCallback: null

  function success(data) {
    return { ok: true, status: 200, kind: "", error: "", code: "", data: data, pagination: null, truncated: false }
  }
  function loadReference(callback) { root.referenceCallback = callback; referenceDelay.restart() }
  function listTickets(params, callback) {
    if (params && Array.isArray(params.LeadAssigneeIds)) root.store = Demo.nextShowcase(root.store, Date.now())
    var tickets = root.store.tickets.slice()
    var statuses = params && Array.isArray(params.StatusIds) ? params.StatusIds : []
    var assignees = params && Array.isArray(params.LeadAssigneeIds) ? params.LeadAssigneeIds : []
    tickets = tickets.filter(function(ticket) {
      var status = ticket.Status && ticket.Status.Id
      return (!statuses.length || statuses.indexOf(status) !== -1)
        && (!assignees.length || assignees.indexOf(ticket.LeadAssigneeId) !== -1)
    })
    callback(root.success(tickets))
  }
  function searchTickets(query, callback) { callback(root.success(Demo.search(root.store, query).tickets)) }
  function listDevices(callback) { callback(root.success(root.store.devices.slice())) }
  function searchDevices(query, callback) { callback(root.success(Demo.search(root.store, query).devices)) }
  function patchTicket(id, patch, callback) {
    var result = Demo.applyPatch(root.store, id, patch, Date.now())
    root.store = result.store
    callback(result.ticket ? root.success(result.ticket) : Api.errorResult("api", "Ticket not found."))
  }
  function addComment(id, payload, callback) {
    var normalized = {}
    for (var key in payload) normalized[key] = payload[key]
    normalized.PlainBody = String(payload && payload.Body || "")
      .replace(/<br>/g, "\n").replace(/&quot;/g, "\"").replace(/&gt;/g, ">")
      .replace(/&lt;/g, "<").replace(/&amp;/g, "&")
    var result = Demo.addComment(root.store, id, normalized, Date.now())
    root.store = result.store
    callback(result.ticket ? root.success(result.ticket) : Api.errorResult("api", "Ticket not found."))
  }
  function createTicket(body, callback) {
    var result = Demo.createTicket(root.store, body, Date.now())
    root.store = result.store
    callback(root.success(result.ticket))
  }
  function uploadAttachment(id, path, callback) {
    var name = Model.attachmentFileName(path) || "demo-screenshot.png"
    if (root.deleteAttachment) root.deleteAttachment(String(path))
    callback(root.success({ Name: name, Url: "demo://attachment/" + encodeURIComponent(name) }))
  }
  function supersede() { referenceDelay.stop(); root.referenceCallback = null }
  function reset() {
    var consumed = root.store && root.store.showcased === true
    root.store = Demo.createStore(Date.now())
    root.store.showcased = consumed
  }

  property Timer referenceDelay: Timer {
    interval: 400
    onTriggered: {
      var callback = root.referenceCallback
      root.referenceCallback = null
      if (callback) callback(root.success(root.store.reference))
    }
  }
}
