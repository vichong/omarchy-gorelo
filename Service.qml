import QtQuick
import Quickshell
import Quickshell.Io
import "Api.js" as Api
import "Model.js" as Model
import "ConfigStore.js" as ConfigStore

// Owner of all Gorelo state: configuration, the API key (memory only, loaded
// from the keyring), reference data, the ticket poll loop, desktop
// notifications and ticket creation. Mounted once per session; the bar widget
// and the overlay reach it through `shell.serviceFor("gorelo")`.
QtObject {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy/gorelo"
  readonly property string configPath: configDir + "/config.json"
  readonly property string pluginId: manifest && manifest.id ? manifest.id : "gorelo"

  // ------------------------------------------------------------ config

  property string region: "usw"
  property int technicianId: 0
  property string technicianName: ""
  property int pollSeconds: 90
  property bool notify: true
  property int notifyMinPriority: 3
  property var statusIds: []
  property int defaultStatusId: 0
  property int defaultGroupId: 0
  property int defaultTypeId: 0
  property int defaultClientId: 0
  property string ticketUrlTemplate: ConfigStore.DEFAULT_TICKET_URL
  property string activeTab: "mine"
  property bool openAfterCreate: true
  property bool configLoaded: false
  property string configError: ""

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  // FileView will not create a missing parent directory; do it once at startup.
  property Process configDirProcess: Process {
    command: ["mkdir", "-p", root.configDir]
  }

  Component.onCompleted: root.configDirProcess.running = true

  function currentConfig() {
    return {
      region: root.region,
      technicianId: root.technicianId,
      technicianName: root.technicianName,
      pollSeconds: root.pollSeconds,
      notify: root.notify,
      notifyMinPriority: root.notifyMinPriority,
      statusIds: root.statusIds.slice(),
      defaultStatusId: root.defaultStatusId,
      defaultGroupId: root.defaultGroupId,
      defaultTypeId: root.defaultTypeId,
      defaultClientId: root.defaultClientId,
      ticketUrlTemplate: root.ticketUrlTemplate,
      activeTab: root.activeTab,
      openAfterCreate: root.openAfterCreate
    }
  }

  function saveConfig(patch) {
    var config = ConfigStore.merge(root.currentConfig(), patch)
    var text = ConfigStore.serialize(config)
    configFile.setText(text)
    // FileView does not re-emit onLoaded for its own write.
    root.applyConfig(text)
  }

  function applyConfig(text) {
    var parsed = ConfigStore.parse(text)
    var c = parsed.config
    root.configError = parsed.error
    var regionChanged = root.region !== c.region
    var filterChanged = JSON.stringify(root.statusIds) !== JSON.stringify(c.statusIds)
      || root.technicianId !== c.technicianId
    var tabChanged = root.activeTab !== c.activeTab

    root.region = c.region
    root.technicianId = c.technicianId
    root.technicianName = c.technicianName
    root.pollSeconds = c.pollSeconds
    root.notify = c.notify
    root.notifyMinPriority = c.notifyMinPriority
    root.statusIds = c.statusIds
    root.defaultStatusId = c.defaultStatusId
    root.defaultGroupId = c.defaultGroupId
    root.defaultTypeId = c.defaultTypeId
    root.defaultClientId = c.defaultClientId
    root.ticketUrlTemplate = c.ticketUrlTemplate
    root.activeTab = c.activeTab
    root.openAfterCreate = c.openAfterCreate

    var first = !root.configLoaded
    root.configLoaded = true

    if (first || regionChanged) {
      // Supersede every in-flight request before dropping the key: a late
      // response for the old region must not land in the new one's state.
      root.generation++
      root.apiKey = ""
      root.resetData()
      root.phase = "idle"
      root.lastError = ""
      root.lastErrorKind = ""
      if (!credentials.busy) credentials.lookup(root.region)
    } else if (filterChanged && root.connected) {
      root.mineIndex = Object.create(null)
      root.firstPollDone = false
      root.poll()
    } else if (tabChanged) {
      root.rebuildRows()
    }
  }

  function setActiveTab(tab) {
    var next = tab === "all" ? "all" : "mine"
    if (next === root.activeTab) return
    root.activeTab = next
    root.rebuildRows()
    tabSaveDebounce.restart()
  }

  property Timer tabSaveDebounce: Timer {
    interval: 300
    onTriggered: root.saveConfig({ activeTab: root.activeTab })
  }

  // ------------------------------------------------------------ credentials

  // Memory only. Never written to config, logs, IPC output or argv.
  property string apiKey: ""
  readonly property bool hasKey: apiKey !== ""
  readonly property bool credentialBusy: credentials.busy

  property CredentialManager credentials: CredentialManager {
    onKeyReady: function(key, region) {
      if (region !== root.region) return
      root.apiKey = key
      root.connect()
    }
    onMissing: function(region) {
      if (region !== root.region) return
      root.apiKey = ""
      root.phase = "idle"
      root.lastError = ""
      root.lastErrorKind = ""
    }
    onCleared: function(region) {
      if (region !== root.region) return
      root.apiKey = ""
      root.generation++
      root.resetData()
      root.phase = "idle"
      root.lastError = ""
      root.lastErrorKind = ""
    }
    onFailed: function(message, region) {
      if (region && region !== root.region) return
      root.phase = "error"
      root.lastError = message
      root.lastErrorKind = "credential"
    }
  }

  // Settings → Connect. A blank key keeps the stored one for that region.
  function applyConnection(region, key) {
    if (!Api.isRegion(region)) return false
    if (root.credentialBusy) {
      root.lastError = "Wait for the current keyring operation to finish."
      return false
    }
    var trimmed = String(key || "").trim()
    if (region !== root.region) {
      // applyConfig handles the region switch (drops the key, looks the new
      // region's key up). A freshly typed key is stored right after.
      root.saveConfig({ region: region, technicianId: 0, technicianName: "",
                        statusIds: [], defaultStatusId: 0, defaultGroupId: 0,
                        defaultTypeId: 0, defaultClientId: 0 })
    }
    if (trimmed) {
      root.phase = "connecting"
      root.lastError = ""
      root.lastErrorKind = ""
      // Storing replaces the pending lookup's answer: keyReady fires from
      // the store and connect() runs with the new key.
      return credentials.store(trimmed, region)
    }
    if (!root.hasKey && !root.credentialBusy) credentials.lookup(region)
    else if (root.hasKey) root.connect()
    return true
  }

  function removeConnection() {
    if (root.credentialBusy) {
      root.lastError = "Wait for the current keyring operation to finish."
      return
    }
    credentials.clear(root.region)
  }

  // ------------------------------------------------------------ state

  // idle | connecting | connected | error
  property string phase: "idle"
  property string lastError: ""
  // credential | network | ratelimit | api | config | ""
  property string lastErrorKind: ""
  property int generation: 0
  readonly property bool configured: hasKey
  readonly property bool connected: phase === "connected"
  readonly property bool needsTechnician: connected && technicianId === 0

  property var statuses: []
  property var types: []
  property var groups: []
  property var users: []
  property var clients: []
  property var statusNames: ({})
  property var clientNames: ({})
  property var userNames: ({})
  property bool referenceLoaded: false

  property var mineTickets: []
  property var allTickets: []
  property var mineIndex: ({})
  property bool firstPollDone: false
  property bool polling: false
  property string lastPolledAt: ""
  property int pollBackoff: 0
  property int ticketRevision: 0
  property ListModel rows: ListModel {}

  readonly property var effectiveStatusIds: statusIds.length ? statusIds : Api.defaultStatusIds(statuses)
  readonly property var mineCounts: { root.ticketRevision; return Model.counts(root.mineTickets) }
  readonly property var allCounts: { root.ticketRevision; return Model.counts(root.allTickets) }

  readonly property string activitySummary: {
    root.ticketRevision
    if (!root.connected) return ""
    if (root.needsTechnician) return "Pick who you are in settings"
    var c = root.mineCounts
    var parts = [c.total + (c.total === 1 ? " ticket" : " tickets")]
    if (c.unread) parts.push(c.unread + " unread")
    if (c.urgent) parts.push(c.urgent + " urgent")
    return parts.join(" · ")
  }

  function resetData() {
    root.statuses = []
    root.types = []
    root.groups = []
    root.users = []
    root.clients = []
    root.statusNames = Object.create(null)
    root.clientNames = Object.create(null)
    root.userNames = Object.create(null)
    root.referenceLoaded = false
    root.mineTickets = []
    root.allTickets = []
    root.mineIndex = Object.create(null)
    root.firstPollDone = false
    root.polling = false
    root.pollBackoff = 0
    root.rows.clear()
    root.ticketRevision++
  }

  function fail(kind, message) {
    root.lastError = message
    root.lastErrorKind = kind
    if (kind === "credential" || kind === "config") {
      root.phase = "error"
      root.polling = false
    }
  }

  // ------------------------------------------------------------ HTTP

  // In-flight XMLHttpRequests, aborted by the watchdog when they outlive
  // requestTimeoutMs. Qt's QML XHR has no reliable timeout of its own.
  property var inflight: []
  readonly property int requestTimeoutMs: 25000

  property Timer watchdog: Timer {
    interval: 5000
    repeat: true
    running: root.inflight.length > 0
    onTriggered: {
      var now = Date.now()
      var keep = []
      for (var i = 0; i < root.inflight.length; i++) {
        var entry = root.inflight[i]
        if (now - entry.started > root.requestTimeoutMs) {
          try { entry.xhr.abort() } catch (e) {}
        } else {
          keep.push(entry)
        }
      }
      root.inflight = keep
    }
  }

  function forgetRequest(xhr) {
    var keep = []
    for (var i = 0; i < root.inflight.length; i++) {
      if (root.inflight[i].xhr !== xhr) keep.push(root.inflight[i])
    }
    root.inflight = keep
  }

  // callback(result) where result is Api.parseResponse's shape. Responses
  // from a superseded generation (region switch, key removal) are dropped.
  function request(method, path, body, callback) {
    if (!root.hasKey) {
      callback({ ok: false, status: 0, kind: "credential", error: "No API key configured.", data: null, pagination: null })
      return
    }
    var gen = root.generation
    var xhr = new XMLHttpRequest()
    var url = Api.baseUrl(root.region) + path
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.forgetRequest(xhr)
      if (gen !== root.generation) return
      callback(Api.parseResponse(xhr.status, xhr.responseText))
    }
    xhr.open(method, url)
    xhr.setRequestHeader("X-API-Key", root.apiKey)
    xhr.setRequestHeader("Accept", "application/json")
    if (body !== null && body !== undefined) {
      xhr.setRequestHeader("Content-Type", "application/json")
      xhr.send(JSON.stringify(body))
    } else {
      xhr.send()
    }
    var list = root.inflight.slice()
    list.push({ xhr: xhr, started: Date.now() })
    root.inflight = list
  }

  // Follow cursor pagination up to maxPages pages, then callback(items, error).
  function requestAll(path, params, maxPages, callback) {
    var items = []
    var pages = 0
    function step(cursor) {
      var p = {}
      for (var k in params) p[k] = params[k]
      if (cursor) p.Cursor = cursor
      root.request("GET", path + Api.query(p), null, function(result) {
        if (!result.ok) { callback(items, result); return }
        var data = Array.isArray(result.data) ? result.data : []
        for (var i = 0; i < data.length; i++) items.push(data[i])
        pages++
        var next = Api.nextCursor(result.pagination)
        if (next && pages < maxPages) step(next)
        else callback(items, null)
      })
    }
    step("")
  }

  // ------------------------------------------------------------ connect

  function connect() {
    if (!root.hasKey) return
    root.generation++
    root.phase = "connecting"
    root.lastError = ""
    root.lastErrorKind = ""
    root.loadReference(function(ok) {
      if (!ok) return
      root.phase = "connected"
      root.pollBackoff = 0
      root.poll()
    })
  }

  function retryConnection() {
    if (root.hasKey) root.connect()
    else if (!root.credentialBusy) credentials.lookup(root.region)
  }

  function refresh(full) {
    if (!root.connected) { root.retryConnection(); return }
    if (full === true) {
      root.loadReference(function(ok) { if (ok) root.poll() })
    } else {
      root.poll()
    }
  }

  // statuses → types → groups → users → clients, in that order, then done(ok).
  function loadReference(done) {
    var gen = root.generation
    function bail(result) {
      if (gen !== root.generation) return
      root.fail(result.kind, result.error)
      if (result.kind !== "credential" && result.kind !== "config") {
        // Transient: stay where we are and let the poll timer retry.
        if (root.phase === "connecting") root.phase = "error"
      }
      done(false)
    }
    root.request("GET", "/v1/tickets/statuses", null, function(r1) {
      if (gen !== root.generation) return
      if (!r1.ok) { bail(r1); return }
      root.statuses = Api.sortStatuses(Array.isArray(r1.data) ? r1.data : [])
      root.statusNames = Api.nameMap(root.statuses)
      root.request("GET", "/v1/tickets/types", null, function(r2) {
        if (gen !== root.generation) return
        if (!r2.ok) { bail(r2); return }
        root.types = Array.isArray(r2.data) ? r2.data : []
        root.request("GET", "/v1/organization/groups", null, function(r3) {
          if (gen !== root.generation) return
          if (!r3.ok) { bail(r3); return }
          root.groups = Array.isArray(r3.data) ? r3.data : []
          root.requestAll("/v1/organization/users", { PageSize: 200 }, 10, function(users, err) {
            if (gen !== root.generation) return
            if (err) { bail(err); return }
            root.users = users
            root.userNames = Api.nameMap(users, Api.userDisplayName)
            root.requestAll("/v1/clients", { PageSize: 200 }, 25, function(clients, err2) {
              if (gen !== root.generation) return
              if (err2) { bail(err2); return }
              root.clients = clients
              root.clientNames = Api.nameMap(clients)
              root.referenceLoaded = true
              root.lastError = ""
              root.lastErrorKind = ""
              done(true)
            })
          })
        })
      })
    })
  }

  property Timer referenceRefresh: Timer {
    interval: 30 * 60 * 1000
    repeat: true
    running: root.connected
    onTriggered: root.loadReference(function() {})
  }

  // ------------------------------------------------------------ polling

  readonly property int effectivePollMs: Math.min(600000, root.pollSeconds * 1000 * Math.pow(2, root.pollBackoff))

  property Timer pollTimer: Timer {
    interval: root.effectivePollMs
    repeat: true
    running: root.connected
    onTriggered: root.poll()
  }

  function poll() {
    if (!root.hasKey || root.polling) return
    if (root.phase !== "connected" && root.phase !== "connecting") return
    root.polling = true
    var gen = root.generation
    var statusFilter = root.effectiveStatusIds
    var mineParams = {
      PageSize: 100, SortBy: "updatedOn", SortOrder: "desc",
      StatusIds: statusFilter, LeadAssigneeIds: root.technicianId ? [root.technicianId] : []
    }
    var allParams = { PageSize: 100, SortBy: "updatedOn", SortOrder: "desc", StatusIds: statusFilter }

    function finishPoll(mine, all) {
      if (gen !== root.generation) return
      root.polling = false
      root.pollBackoff = 0
      root.lastPolledAt = new Date().toISOString()
      if (root.phase !== "connected") root.phase = "connected"
      root.lastError = ""
      root.lastErrorKind = ""

      if (root.notify && root.technicianId) {
        var events = Model.diffForNotifications(root.mineIndex, mine, root.notifyMinPriority)
        for (var i = 0; i < events.length; i++) root.sendNotification(events[i])
      }
      root.mineIndex = Model.indexOf(mine)
      root.firstPollDone = true
      root.mineTickets = mine
      root.allTickets = all
      root.ticketRevision++
      root.rebuildRows()
    }

    function pollFailed(result) {
      if (gen !== root.generation) return
      root.polling = false
      root.fail(result.kind, result.error)
      if (result.kind === "ratelimit" || result.kind === "network") {
        root.pollBackoff = Math.min(4, root.pollBackoff + 1)
      }
    }

    function fetchAll(mine) {
      root.request("GET", "/v1/tickets" + Api.query(allParams), null, function(r) {
        if (!r.ok) { pollFailed(r); return }
        finishPoll(mine, Api.validTicketList(r.data))
      })
    }

    if (root.technicianId) {
      root.request("GET", "/v1/tickets" + Api.query(mineParams), null, function(r) {
        if (!r.ok) { pollFailed(r); return }
        fetchAll(Api.validTicketList(r.data))
      })
    } else {
      fetchAll([])
    }
  }

  function rowContext() {
    return {
      clientNames: root.clientNames,
      userNames: root.userNames,
      statusNames: root.statusNames,
      technicianId: root.technicianId,
      now: Date.now()
    }
  }

  function urlFor(ticket) {
    return Api.ticketUrl(root.ticketUrlTemplate, ticket)
  }

  function rebuildRows() {
    var source = root.activeTab === "all" ? root.allTickets : root.mineTickets
    var list = Model.buildRows(source, root.rowContext(), root.urlFor)
    root.rows.clear()
    for (var i = 0; i < list.length; i++) root.rows.append(list[i])
  }

  function ticketFor(ticketId) {
    var id = String(ticketId)
    for (var i = 0; i < root.allTickets.length; i++) if (String(root.allTickets[i].Id) === id) return root.allTickets[i]
    for (var j = 0; j < root.mineTickets.length; j++) if (String(root.mineTickets[j].Id) === id) return root.mineTickets[j]
    return null
  }

  // ------------------------------------------------------------ notifications

  function sendNotification(event) {
    var text = Model.notificationText(event)
    var ticket = event.ticket
    var url = root.urlFor(ticket)
    var priority = Model.priorityIdOf(ticket)
    var args = ["omarchy-notification-send", "--app-name", "Gorelo", "-g", Model.BRAND_ICON,
                "-u", priority === 1 ? "critical" : "normal",
                "-r", "gorelo-" + String(ticket.Id),
                text.headline, text.body]
    if (url) args = args.concat(["--exec", "xdg-open", url])
    Quickshell.execDetached(args)
  }

  function toast(headline, body) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Gorelo",
                             "-g", Model.BRAND_ICON, "-t", "4000", headline, body || ""])
  }

  // ------------------------------------------------------------ actions

  property string actionError: ""
  property bool actionBusy: false

  function openTicket(ticketId) {
    var ticket = root.ticketFor(ticketId)
    var url = ticket ? root.urlFor(ticket) : Api.ticketUrl(root.ticketUrlTemplate, { Id: String(ticketId) })
    if (!url) return false
    Quickshell.execDetached(["xdg-open", url])
    return true
  }

  function openWebApp() {
    Quickshell.execDetached(["xdg-open", "https://app.gorelo.io/"])
  }

  function patchTicket(ticketId, patch, label) {
    if (!root.connected) return false
    root.actionBusy = true
    root.actionError = ""
    root.request("PATCH", "/v1/tickets/" + encodeURIComponent(String(ticketId)), patch, function(r) {
      root.actionBusy = false
      if (!r.ok) {
        root.actionError = label + " failed: " + r.error
        return
      }
      root.poll()
    })
    return true
  }

  function setStatus(ticketId, statusId) {
    var id = parseInt(statusId, 10)
    if (isNaN(id) || id <= 0) return false
    return root.patchTicket(ticketId, { StatusId: id, UpdatedByName: root.technicianName || undefined }, "Status change")
  }

  function assignToMe(ticketId) {
    if (!root.technicianId) return false
    return root.patchTicket(ticketId, { LeadAssigneeId: root.technicianId, UpdatedByName: root.technicianName || undefined }, "Assignment")
  }

  function addPrivateNote(ticketId, text) {
    var body = String(text || "").trim()
    if (!body || !root.connected) return false
    root.actionBusy = true
    root.actionError = ""
    var payload = { ConversationTypeId: Api.CONVERSATION_PRIVATE, Body: Api.escapeHtml(body) }
    if (root.technicianName) payload.CreatedByName = root.technicianName
    root.request("POST", "/v1/tickets/" + encodeURIComponent(String(ticketId)) + "/comments", payload, function(r) {
      root.actionBusy = false
      if (!r.ok) {
        root.actionError = "Note failed: " + r.error
        return
      }
      root.poll()
    })
    return true
  }

  // ------------------------------------------------------------ quick ticket

  property var draft: Model.emptyDraft()
  // Emitted once a create-ticket flow ends; warning is empty on full success.
  signal created(string id, string warning)
  property bool creating: false
  property string createError: ""
  property string lastCreatedId: ""
  property bool capturing: false

  function updateDraft(patch) {
    var next = {}
    for (var k in root.draft) next[k] = root.draft[k]
    for (var p in patch) next[p] = patch[p]
    root.draft = next
  }

  function clearDraft() {
    root.draft = Model.emptyDraft()
    root.createError = ""
  }

  readonly property var createDefaults: ({
    statusId: root.defaultStatusId, groupId: root.defaultGroupId, typeId: root.defaultTypeId
  })

  function createTicket() {
    if (root.creating) return false
    var problem = Model.validateDraft(root.draft, root.createDefaults)
    if (problem) { root.createError = problem; return false }
    if (!root.connected) { root.createError = "Not connected to Gorelo."; return false }

    var d = root.draft
    var body = {
      Title: String(d.title).trim(),
      ClientId: d.clientId,
      StatusId: root.defaultStatusId,
      GroupId: root.defaultGroupId,
      TypeId: root.defaultTypeId,
      PriorityId: d.priorityId,
      IsUnread: false
    }
    if (String(d.description || "").trim()) body.Description = String(d.description).trim()
    if (root.technicianId) body.LeadAssigneeId = root.technicianId
    if (root.technicianName) body.CreatedByName = root.technicianName

    root.creating = true
    root.createError = ""
    var attachment = String(d.attachmentPath || "")
    root.request("POST", "/v1/tickets", body, function(r) {
      if (!r.ok) {
        root.creating = false
        root.createError = r.error
        return
      }
      var id = r.data && r.data.Id ? String(r.data.Id) : ""
      root.lastCreatedId = id
      if (attachment && id) {
        root.uploadAttachment(id, attachment, function(uploadError, file) {
          if (uploadError) {
            root.finishCreate(id, "Ticket created, but the screenshot upload failed: " + uploadError)
            return
          }
          var payload = { ConversationTypeId: Api.CONVERSATION_PRIVATE, Body: "Screenshot",
                          Attachments: [{ Name: file.Name, Url: file.Url }] }
          if (root.technicianName) payload.CreatedByName = root.technicianName
          root.request("POST", "/v1/tickets/" + encodeURIComponent(id) + "/comments", payload, function(r2) {
            root.finishCreate(id, r2.ok ? "" : "Ticket created, but attaching the screenshot failed: " + r2.error)
          })
        })
      } else {
        root.finishCreate(id, "")
      }
    })
    return true
  }

  function finishCreate(id, warning) {
    root.creating = false
    root.clearDraft()
    if (warning) root.createError = warning
    var ticket = { Id: id }
    root.toast("Ticket created", warning || "")
    if (root.openAfterCreate && id) Quickshell.execDetached(["xdg-open", root.urlFor(ticket)])
    root.created(id, warning)
    root.poll()
  }

  // curl does the multipart upload; the key reaches it through a config
  // file on stdin (`-K -`), never argv.
  property string uploadTicketId: ""
  property var uploadCallback: null
  property string uploadOutput: ""

  property Process uploadProcess: Process {
    command: []
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.uploadOutput = String(text || "")
    }
    onStarted: {
      uploadProcess.write("header = \"X-API-Key: " + root.apiKey + "\"\n")
      uploadProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      var cb = root.uploadCallback
      root.uploadCallback = null
      if (!cb) return
      var raw = root.uploadOutput
      root.uploadOutput = ""
      var lines = raw.trim().split("\n")
      var code = parseInt(lines.pop(), 10)
      var parsed = Api.parseResponse(isNaN(code) ? 0 : code, lines.join("\n"))
      if (exitCode !== 0 && !parsed.ok) { cb(parsed.error || ("curl exited " + exitCode), null); return }
      if (!parsed.ok) { cb(parsed.error, null); return }
      var file = parsed.data
      if (!file || !file.Name || !file.Url) { cb("Unexpected upload response.", null); return }
      cb("", file)
    }
  }

  function uploadAttachment(ticketId, path, callback) {
    if (root.uploadCallback || uploadProcess.running) { callback("An upload is already running.", null); return }
    if (path.indexOf('"') !== -1 || path.indexOf("\n") !== -1) { callback("Unsupported characters in the file path.", null); return }
    root.uploadCallback = callback
    root.uploadOutput = ""
    root.uploadTicketId = String(ticketId)
    var url = Api.baseUrl(root.region) + "/v1/tickets/" + encodeURIComponent(String(ticketId)) + "/attachments"
    uploadProcess.command = ["curl", "-sS", "--max-time", "90", "-K", "-",
                             "-F", "file=@\"" + path + "\"",
                             "-w", "\n%{http_code}", url]
    uploadProcess.stdinEnabled = true
    uploadProcess.running = true
  }

  // Region select → save → the overlay re-summons itself with the path in
  // the draft. The overlay dismisses first so it is not in the shot.
  property string capturePath: ""

  property Process captureProcess: Process {
    command: ["omarchy", "capture", "screenshot", "region", "save"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.capturePath = String(text || "").trim().split("\n").pop()
    }
    onExited: function(exitCode) {
      root.capturing = false
      var path = exitCode === 0 ? root.capturePath : ""
      root.capturePath = ""
      if (path) root.updateDraft({ attachmentPath: path })
      if (root.shell && typeof root.shell.summon === "function") {
        root.shell.summon(root.pluginId, JSON.stringify({ tab: "new" }))
      }
    }
  }

  property Timer captureDelay: Timer {
    interval: 350
    onTriggered: captureProcess.running = true
  }

  function captureScreenshot() {
    if (root.capturing || captureProcess.running) return false
    root.capturing = true
    root.capturePath = ""
    captureDelay.restart()
    return true
  }

  // Redacted: no key, no client names, no ticket titles.
  function statusLine() {
    return "phase=" + root.phase
      + " region=" + root.region
      + " key=" + (root.hasKey ? "present" : "absent")
      + " technician=" + root.technicianId
      + " reference=" + root.referenceLoaded
      + " mine=" + root.mineTickets.length
      + " all=" + root.allTickets.length
      + " backoff=" + root.pollBackoff
      + (root.lastPolledAt ? " polled=" + root.lastPolledAt : "")
      + (root.lastError ? " error=" + root.lastErrorKind + ":" + root.lastError : "")
  }
}
