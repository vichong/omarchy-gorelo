import QtQuick
import Quickshell.Io
import "Api.js" as Api

// Live Gorelo transport. Every callback is generation-gated; supersede()
// aborts XHR and upload work before advancing the connection generation.
QtObject {
  id: root

  property string region: "usw"
  property string apiKey: ""
  property int generation: 0
  property var deleteAttachment: null
  property var inflight: []
  readonly property int requestTimeoutMs: 25000

  function success(data, pagination) {
    return { ok: true, status: 200, kind: "", error: "", code: "",
             data: data, pagination: pagination || null }
  }

  function forget(xhr) {
    var keep = []
    for (var i = 0; i < root.inflight.length; i++) if (root.inflight[i].xhr !== xhr) keep.push(root.inflight[i])
    root.inflight = keep
  }

  function request(method, path, body, callback) {
    if (!root.apiKey) { callback(Api.errorResult("credential", "No API key configured.")); return null }
    var token = root.generation
    var xhr = new XMLHttpRequest()
    var entry = { xhr: xhr, started: Date.now(), done: false, superseded: false, complete: null, abort: null }
    function complete(result) {
      if (entry.done) return
      entry.done = true
      root.forget(xhr)
      if (!entry.superseded && token === root.generation) callback(result)
    }
    entry.complete = complete
    entry.abort = function() {
      if (entry.done) return
      entry.superseded = true
      complete(Api.errorResult("network", "Request superseded."))
      try { xhr.abort() } catch (e) {}
    }
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var responseUrl = String(xhr.responseURL || "")
      if (responseUrl && responseUrl.indexOf(Api.baseUrl(root.region)) !== 0) {
        complete(Api.errorResult("protocol", "Unexpected redirect"))
        return
      }
      complete(Api.parseResponse(xhr.status, xhr.responseText))
    }
    var list = root.inflight.slice()
    list.push(entry)
    root.inflight = list
    try {
      xhr.open(method, Api.baseUrl(root.region) + path)
      xhr.setRequestHeader("X-API-Key", root.apiKey)
      xhr.setRequestHeader("Accept", "application/json")
      if (body !== null && body !== undefined) {
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
      } else xhr.send()
    } catch (e) {
      complete(Api.errorResult("network", "Could not start the Gorelo API request."))
    }
    return entry
  }

  function requestAll(path, params, maxPages, callback) {
    var items = []
    var pages = 0
    function step(cursor) {
      var query = {}
      for (var key in params) query[key] = params[key]
      if (cursor) query.Cursor = cursor
      root.request("GET", path + Api.query(query), null, function(result) {
        if (!result.ok) {
          var failure = Api.errorResult(result.kind, result.error)
          failure.status = result.status; failure.code = result.code; failure.data = items; failure.truncated = false
          callback(failure); return
        }
        var data = Array.isArray(result.data) ? result.data : []
        for (var i = 0; i < data.length; i++) items.push(data[i])
        pages++
        var next = Api.nextCursor(result.pagination)
        if (next && pages < maxPages) step(next)
        else {
          var done = root.success(items, result.pagination)
          done.truncated = !!next
          callback(done)
        }
      })
    }
    step("")
  }

  function loadReference(callback) {
    var data = { statuses: [], types: [], groups: [], users: [], clients: [] }
    root.request("GET", "/v1/tickets/statuses", null, function(a) {
      if (!a.ok) { callback(a); return }
      data.statuses = Array.isArray(a.data) ? a.data : []
      root.request("GET", "/v1/tickets/types", null, function(b) {
        if (!b.ok) { callback(b); return }
        data.types = Array.isArray(b.data) ? b.data : []
        root.request("GET", "/v1/organization/groups", null, function(c) {
          if (!c.ok) { callback(c); return }
          data.groups = Array.isArray(c.data) ? c.data : []
          root.requestAll("/v1/organization/users", { PageSize: 200 }, 10, function(d) {
            if (!d.ok) { callback(d); return }
            data.users = d.data
            root.requestAll("/v1/clients", { PageSize: 200 }, 25, function(e) {
              if (!e.ok) { callback(e); return }
              data.clients = e.data
              callback(root.success(data))
            })
          })
        })
      })
    })
  }

  function listTickets(params, callback) { root.requestAll("/v1/tickets", params, 5, callback) }
  function searchTickets(query, callback) {
    return root.request("GET", "/v1/tickets" + Api.query({ Query: query, PageSize: 50, SortBy: "updatedOn", SortOrder: "desc" }), null, callback)
  }
  function listDevices(callback) { root.requestAll("/v1/assets/agents", { PageSize: 200 }, 10, callback) }
  function searchDevices(query, callback) {
    return root.request("GET", "/v1/assets/agents" + Api.query({ Query: query, PageSize: 25 }), null, callback)
  }
  function patchTicket(id, patch, callback) {
    root.request("PATCH", "/v1/tickets/" + encodeURIComponent(String(id)), patch, callback)
  }
  function addComment(id, payload, callback) {
    root.request("POST", "/v1/tickets/" + encodeURIComponent(String(id)) + "/comments", payload, callback)
  }
  function createTicket(body, callback) { root.request("POST", "/v1/tickets", body, callback) }

  function curlEscape(value) { return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"") }

  function finishUpload(result) {
    var operation = root.uploadOperation
    if (!operation || operation.done) return
    operation.done = true
    uploadDeadline.stop()
    root.uploadOperation = null
    root.uploadOutput = ""
    if (root.deleteAttachment) root.deleteAttachment(operation.path)
    if (operation.generation === root.generation) operation.callback(result)
  }

  function uploadAttachment(id, path, callback) {
    var target = String(path || "")
    if (root.uploadOperation || uploadProcess.running) { callback(Api.errorResult("config", "An upload is already running.")); return }
    if (target.indexOf('"') !== -1 || target.indexOf("\n") !== -1) {
      callback(Api.errorResult("config", "Unsupported characters in the file path.")); return
    }
    root.uploadOutput = ""
    root.uploadOperation = { generation: root.generation, apiKey: root.apiKey, path: target,
                             callback: callback, done: false }
    var url = Api.baseUrl(root.region) + "/v1/tickets/" + encodeURIComponent(String(id)) + "/attachments"
    uploadProcess.command = ["curl", "-sS", "--max-time", "115", "-K", "-",
                             "-F", "file=@\"" + target + "\"", "-w", "\n%{http_code}", url]
    uploadProcess.stdinEnabled = true
    uploadDeadline.restart()
    uploadProcess.running = true
  }

  function supersede() {
    var requests = root.inflight.slice()
    for (var i = 0; i < requests.length; i++) requests[i].abort()
    root.inflight = []
    var operation = root.uploadOperation
    root.uploadOperation = null
    root.uploadOutput = ""
    uploadDeadline.stop()
    if (operation && root.deleteAttachment) root.deleteAttachment(operation.path)
    if (uploadProcess.running) uploadProcess.signal(15)
    root.generation++
  }

  property Timer watchdog: Timer {
    interval: 5000
    repeat: true
    running: root.inflight.length > 0
    onTriggered: {
      var requests = root.inflight.slice()
      var now = Date.now()
      for (var i = 0; i < requests.length; i++) {
        if (now - requests[i].started > root.requestTimeoutMs) {
          requests[i].complete(Api.errorResult("network", "The Gorelo API request timed out."))
          try { requests[i].xhr.abort() } catch (e) {}
        }
      }
    }
  }

  property var uploadOperation: null
  property string uploadOutput: ""
  property Timer uploadDeadline: Timer {
    interval: 120000
    onTriggered: {
      root.finishUpload(Api.errorResult("network", "The screenshot upload timed out."))
      if (uploadProcess.running) uploadProcess.signal(15)
    }
  }
  property Process uploadProcess: Process {
    command: []
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.uploadOutput = String(text || "") }
    onStarted: {
      if (!root.uploadOperation) { uploadProcess.signal(15); return }
      uploadProcess.write("header = \"X-API-Key: " + root.curlEscape(root.uploadOperation.apiKey) + "\"\n")
      uploadProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (!root.uploadOperation) return
      var lines = root.uploadOutput.trim().split("\n")
      var code = parseInt(lines.pop(), 10)
      var parsed = Api.parseResponse(isNaN(code) ? 0 : code, lines.join("\n"))
      if (exitCode !== 0 && !parsed.ok) { root.finishUpload(Api.errorResult(parsed.kind, parsed.error || ("curl exited " + exitCode))); return }
      if (!parsed.ok) { root.finishUpload(parsed); return }
      if (!parsed.data || !parsed.data.Name || !parsed.data.Url) {
        root.finishUpload(Api.errorResult("protocol", "Unexpected upload response.")); return
      }
      root.finishUpload(parsed)
    }
  }
}
