import QtQuick
import Quickshell
import Quickshell.Io
import "Api.js" as Api

// Live Gorelo transport. Every callback is generation-gated; supersede()
// aborts curl and upload work before advancing the connection generation.
QtObject {
  id: root

  property string region: "usw"
  property string apiKey: ""
  property int generation: 0
  property var deleteAttachment: null
  property var inflight: []
  readonly property int requestTimeoutMs: 25000
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string screenshotDir: runtimeDir ? runtimeDir + "/gorelo" : ""
  readonly property string attachmentHelperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/gorelo-attachment")).replace(/^file:\/\//, ""))

  function success(data, pagination) {
    return { ok: true, status: 200, kind: "", error: "", code: "",
             data: data, pagination: pagination || null }
  }

  function forget(entry) {
    var keep = []
    for (var i = 0; i < root.inflight.length; i++) if (root.inflight[i] !== entry) keep.push(root.inflight[i])
    root.inflight = keep
  }

  function request(method, path, body, callback) {
    if (!root.apiKey) { callback(Api.errorResult("credential", "No API key configured.")); return null }
    if (root.apiKey.indexOf("\n") !== -1 || root.apiKey.indexOf("\r") !== -1) {
      callback(Api.errorResult("credential", "The API key contains unsupported line breaks.")); return null
    }
    var token = root.generation
    var url = Api.baseUrl(root.region) + path
    if (!Api.sameOrigin(url, Api.baseUrl(root.region))) {
      callback(Api.errorResult("protocol", "Refused a request outside the configured Gorelo API origin."))
      return null
    }
    var entry = { method: String(method), url: url, bodyText: body === null || body === undefined ? "" : JSON.stringify(body),
                  apiKey: root.apiKey, generation: token, started: Date.now(), done: false,
                  superseded: false, complete: null, abort: null }
    function complete(result) {
      if (entry.done) return
      entry.done = true
      root.forget(entry)
      if (!entry.superseded && token === root.generation) callback(result)
    }
    entry.complete = complete
    entry.abort = function() {
      if (entry.done) return
      entry.superseded = true
      complete(Api.errorResult("network", "Request superseded."))
      if (root.requestOperation === entry && requestProcess.running) {
        requestProcess.signal(15)
        requestKillDeadline.restart()
      } else {
        root.startNextRequest()
      }
    }
    var list = root.inflight.slice()
    list.push(entry)
    root.inflight = list
    var queue = root.requestQueue.slice()
    queue.push(entry)
    root.requestQueue = queue
    root.startNextRequest()
    return entry
  }

  // A single worker keeps request concurrency bounded. Credentials and JSON
  // bodies enter curl only through its stdin config; redirects are never enabled.
  function startNextRequest() {
    if (root.requestOperation || requestProcess.running) return
    var queue = root.requestQueue.slice()
    var entry = null
    while (queue.length && !entry) {
      var candidate = queue.shift()
      if (!candidate.done) entry = candidate
    }
    root.requestQueue = queue
    if (!entry) return
    root.requestOperation = entry
    root.requestOutput = ""
    requestProcess.command = ["curl", "-sS", "--proto", "=https", "--max-filesize",
                              String(Api.MAX_RESPONSE_BYTES), "--max-time",
                              String(Math.max(1, Math.ceil(root.requestTimeoutMs / 1000))),
                              "-K", "-", "-w", "\n%{http_code}", entry.url]
    requestProcess.stdinEnabled = true
    requestDeadline.restart()
    requestProcess.running = true
  }

  function parseCurlResult(output, exitCode, tooLargeMessage) {
    var text = String(output || "")
    if (exitCode === 63 || text.length > Api.MAX_RESPONSE_BYTES) {
      return Api.errorResult("protocol", tooLargeMessage)
    }
    var marker = text.lastIndexOf("\n")
    var statusText = marker >= 0 ? text.slice(marker + 1).trim() : ""
    var responseBody = marker >= 0 ? text.slice(0, marker) : text
    var status = parseInt(statusText, 10)
    if (!isNaN(status) && status >= 300 && status < 400) {
      return Api.errorResult("protocol", "Unexpected redirect")
    }
    var parsed = Api.parseResponse(isNaN(status) ? 0 : status, responseBody)
    if (exitCode !== 0) {
      if (!parsed.ok && parsed.status > 0) return parsed
      return Api.errorResult("network", "Could not reach the Gorelo API (curl exited " + exitCode + ").")
    }
    return parsed
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
    if (!root.apiKey) { callback(Api.errorResult("credential", "No API key configured.")); return }
    if (root.apiKey.indexOf("\n") !== -1 || root.apiKey.indexOf("\r") !== -1) {
      callback(Api.errorResult("credential", "The API key contains unsupported line breaks.")); return
    }
    if (!root.screenshotDir) { callback(Api.errorResult("config", "No private runtime directory is available.")); return }
    if (!/^screenshot-[A-Za-z0-9._-]+\.png$/.test(target) || target.indexOf("..") !== -1 || target.indexOf("/") !== -1) {
      callback(Api.errorResult("config", "Invalid screenshot attachment name.")); return
    }
    root.uploadOutput = ""
    root.uploadOperation = { generation: root.generation, apiKey: root.apiKey, path: target,
                             callback: callback, done: false }
    var url = Api.baseUrl(root.region) + "/v1/tickets/" + encodeURIComponent(String(id)) + "/attachments"
    if (!Api.sameOrigin(url, Api.baseUrl(root.region))) {
      root.uploadOperation = null
      callback(Api.errorResult("protocol", "Refused an upload outside the configured Gorelo API origin."))
      return
    }
    uploadProcess.command = ["bash", root.attachmentHelperPath, "upload", root.screenshotDir, target, url,
                             String(Api.MAX_RESPONSE_BYTES), "115", String(Api.MAX_ATTACHMENT_BYTES)]
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
    if (uploadProcess.running) { uploadProcess.signal(15); uploadKillDeadline.restart() }
    root.generation++
  }

  property var requestQueue: []
  property var requestOperation: null
  property string requestOutput: ""
  property Timer requestDeadline: Timer {
    interval: root.requestTimeoutMs + 1000
    onTriggered: {
      var operation = root.requestOperation
      if (operation && !operation.done) operation.complete(Api.errorResult("network", "The Gorelo API request timed out."))
      if (requestProcess.running) { requestProcess.signal(15); requestKillDeadline.restart() }
    }
  }
  property Timer requestKillDeadline: Timer {
    interval: 2000
    onTriggered: if (requestProcess.running) requestProcess.signal(9)
  }
  property Process requestProcess: Process {
    command: []
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.requestOutput = String(text || "") }
    onStarted: {
      var operation = root.requestOperation
      if (!operation || operation.done) { requestProcess.signal(15); requestKillDeadline.restart(); return }
      var config = "request = \"" + root.curlEscape(operation.method) + "\"\n"
      config += "header = \"X-API-Key: " + root.curlEscape(operation.apiKey) + "\"\n"
      config += "header = \"Accept: application/json\"\n"
      if (operation.bodyText !== "") {
        config += "header = \"Content-Type: application/json\"\n"
        config += "data-raw = \"" + root.curlEscape(operation.bodyText) + "\"\n"
      }
      requestProcess.write(config)
      requestProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      var operation = root.requestOperation
      var output = root.requestOutput
      requestDeadline.stop()
      requestKillDeadline.stop()
      root.requestOperation = null
      root.requestOutput = ""
      requestProcess.stdinEnabled = true
      if (operation && !operation.done) {
        operation.complete(root.parseCurlResult(output, exitCode, "The Gorelo API response was too large."))
      }
      root.startNextRequest()
    }
  }

  property var uploadOperation: null
  property string uploadOutput: ""
  property Timer uploadDeadline: Timer {
    interval: 120000
    onTriggered: {
      root.finishUpload(Api.errorResult("network", "The screenshot upload timed out."))
      if (uploadProcess.running) { uploadProcess.signal(15); uploadKillDeadline.restart() }
    }
  }
  property Timer uploadKillDeadline: Timer {
    interval: 2000
    onTriggered: if (uploadProcess.running) uploadProcess.signal(9)
  }
  property Process uploadProcess: Process {
    command: []
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.uploadOutput = String(text || "") }
    onStarted: {
      if (!root.uploadOperation) { uploadProcess.signal(15); uploadKillDeadline.restart(); return }
      uploadProcess.write("header = \"X-API-Key: " + root.curlEscape(root.uploadOperation.apiKey) + "\"\n")
      uploadProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      uploadDeadline.stop()
      uploadKillDeadline.stop()
      uploadProcess.stdinEnabled = true
      if (!root.uploadOperation) { root.uploadOutput = ""; return }
      if (exitCode === 64) {
        root.finishUpload(Api.errorResult("config", "The screenshot could not be verified as a private attachment file.")); return
      }
      var parsed = root.parseCurlResult(root.uploadOutput, exitCode, "The upload response was too large.")
      if (!parsed.ok) { root.finishUpload(parsed); return }
      if (!parsed.data || !parsed.data.Name || !parsed.data.Url) {
        root.finishUpload(Api.errorResult("protocol", "Unexpected upload response.")); return
      }
      root.finishUpload(parsed)
    }
  }
}
