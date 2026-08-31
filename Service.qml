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
  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.vichong.gorelo"

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
  property string browserDesktop: ""
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

  Component.onCompleted: {
    root.configDirProcess.running = true
    root.refreshBrowsers()
  }

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
      openAfterCreate: root.openAfterCreate,
      browserDesktop: root.browserDesktop
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
    root.browserDesktop = c.browserDesktop

    var first = !root.configLoaded
    root.configLoaded = true

    if (first || regionChanged) {
      // Supersede every in-flight request before dropping the key: a late
      // response for the old region must not land in the new one's state.
      root.supersedeRequests()
      root.apiKey = ""
      root.resetData()
      root.phase = "idle"
      root.lastError = ""
      root.lastErrorKind = ""
      root.lastErrorCode = ""
      var pending = root.pendingConnection
      if (pending && pending.region === root.region && pending.key) {
        root.pendingConnection = null
        root.phase = "connecting"
        credentials.store(pending.key, pending.region)
        pending.key = ""
      } else if (!credentials.busy) {
        credentials.lookup(root.region)
      } else {
        // A keyring operation for the old region is still running; its
        // result is ignored (region mismatch), so look up once it ends.
        root.pendingLookupRegion = root.region
      }
    } else if (filterChanged && root.connected) {
      root.mineIndex = Object.create(null)
      root.firstPollDone = false
      root.pollSerial++
      root.pollRequested = true
      if (!root.polling) root.poll()
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
  property var pendingConnection: null
  property string pendingLookupRegion: ""

  onCredentialBusyChanged: {
    if (root.credentialBusy || !root.pendingLookupRegion) return
    var region = root.pendingLookupRegion
    root.pendingLookupRegion = ""
    if (region === root.region && !root.hasKey) credentials.lookup(region)
  }

  property CredentialManager credentials: CredentialManager {
    onKeyReady: function(key, region) {
      if (region !== root.region) return
      if (root.keyHasUnsupportedCharacters(key)) {
        root.apiKey = ""
        root.fail("config", "The stored API key contains unsupported quotes, backslashes, or control characters.", "")
        return
      }
      root.apiKey = key
      root.connect()
    }
    onMissing: function(region) {
      if (region !== root.region) return
      root.apiKey = ""
      root.phase = "idle"
      root.lastError = ""
      root.lastErrorKind = ""
      root.lastErrorCode = ""
    }
    onCleared: function(region) {
      if (region !== root.region) return
      root.apiKey = ""
      root.supersedeRequests()
      root.resetData()
      root.phase = "idle"
      root.lastError = ""
      root.lastErrorKind = ""
      root.lastErrorCode = ""
    }
    onFailed: function(message, region) {
      if (region && region !== root.region) return
      root.phase = "error"
      root.lastError = message
      root.lastErrorKind = "credential"
      root.lastErrorCode = ""
    }
  }

  // Settings → Connect. A blank key keeps the stored one for that region.
  function keyHasUnsupportedCharacters(key) {
    return /["\\\x00-\x1f\x7f]/.test(String(key || ""))
  }

  function applyConnection(region, key) {
    if (!Api.isRegion(region)) return false
    if (root.credentialBusy) {
      root.lastError = "Wait for the current keyring operation to finish."
      root.lastErrorKind = "credential"
      root.lastErrorCode = ""
      return false
    }
    var switchingRegion = region !== root.region
    var raw = String(key || "")
    if (raw && root.keyHasUnsupportedCharacters(raw)) {
      root.phase = "error"
      root.lastError = "The API key contains unsupported quotes, backslashes, or control characters."
      root.lastErrorKind = "config"
      root.lastErrorCode = ""
      return false
    }
    var trimmed = raw.trim()
    if (switchingRegion) {
      // applyConfig owns the region switch. When a key was supplied it stores
      // that key directly and deliberately does not start a competing lookup.
      root.pendingConnection = trimmed ? { region: region, key: trimmed } : null
      root.saveConfig({ region: region, technicianId: 0, technicianName: "",
                        statusIds: [], defaultStatusId: 0, defaultGroupId: 0,
                        defaultTypeId: 0, defaultClientId: 0 })
    }
    if (trimmed) {
      root.phase = "connecting"
      root.lastError = ""
      root.lastErrorKind = ""
      root.lastErrorCode = ""
      if (switchingRegion) return true
      return credentials.store(trimmed, region)
    }
    if (!root.hasKey && !root.credentialBusy) credentials.lookup(region)
    else if (root.hasKey) root.connect()
    return true
  }

  function removeConnection() {
    if (root.credentialBusy) {
      root.lastError = "Wait for the current keyring operation to finish."
      root.lastErrorKind = "credential"
      root.lastErrorCode = ""
      return
    }
    credentials.clear(root.region)
  }

  // ------------------------------------------------------------ state

  // idle | connecting | connected | error
  property string phase: "idle"
  property string lastError: ""
  // credential | network | ratelimit | api | protocol | config | ""
  property string lastErrorKind: ""
  property string lastErrorCode: ""
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
  property bool pollRequested: false
  property int pollSerial: 0
  property bool mineTruncated: false
  property bool allTruncated: false
  readonly property bool truncated: activeTab === "all" ? allTruncated : mineTruncated
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
    if (root.mineTruncated) parts.push("showing first 500")
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
    root.pollRequested = false
    root.mineTruncated = false
    root.allTruncated = false
    root.pollBackoff = 0
    root.rows.clear()
    root.ticketRevision++
  }

  function fail(kind, message, code) {
    root.lastError = message
    root.lastErrorKind = kind
    root.lastErrorCode = code || ""
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
      var requests = root.inflight.slice()
      for (var i = 0; i < requests.length; i++) {
        var entry = requests[i]
        if (now - entry.started > root.requestTimeoutMs) {
          entry.complete(root.networkError("The Gorelo API request timed out."))
          try { entry.xhr.abort() } catch (e) {}
        }
      }
    }
  }

  function forgetRequest(xhr) {
    var keep = []
    for (var i = 0; i < root.inflight.length; i++) {
      if (root.inflight[i].xhr !== xhr) keep.push(root.inflight[i])
    }
    root.inflight = keep
  }

  function networkError(message) {
    return { ok: false, status: 0, kind: "network", error: message,
             code: "", data: null, pagination: null }
  }

  // The only generation bump. It also releases every owner-side busy flag,
  // so dropped callbacks can never wedge polling, actions or ticket creation.
  function supersedeRequests() {
    var requests = root.inflight.slice()
    for (var i = 0; i < requests.length; i++) {
      var entry = requests[i]
      entry.superseded = true
      entry.complete(root.networkError("Request superseded."))
      try { entry.xhr.abort() } catch (e) {}
    }
    root.inflight = []
    root.polling = false
    root.pollRequested = false
    root.pendingActions = 0
    root.creating = false
    root.cancelUpload()
    root.generation++
  }

  // callback(result) where result is Api.parseResponse's shape. Responses
  // from a superseded generation (region switch, key removal) are dropped.
  function request(method, path, body, callback) {
    if (!root.hasKey) {
      callback({ ok: false, status: 0, kind: "credential", error: "No API key configured.",
                 code: "", data: null, pagination: null })
      return
    }
    var gen = root.generation
    var xhr = new XMLHttpRequest()
    var url = Api.baseUrl(root.region) + path
    var entry = { xhr: xhr, started: Date.now(), done: false, superseded: false, complete: null }
    function complete(result) {
      if (entry.done) return
      entry.done = true
      root.forgetRequest(xhr)
      if (entry.superseded || gen !== root.generation) return
      callback(result)
    }
    entry.complete = complete
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      complete(Api.parseResponse(xhr.status, xhr.responseText))
    }
    var list = root.inflight.slice()
    list.push(entry)
    root.inflight = list
    try {
      xhr.open(method, url)
      xhr.setRequestHeader("X-API-Key", root.apiKey)
      xhr.setRequestHeader("Accept", "application/json")
      if (body !== null && body !== undefined) {
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
      } else {
        xhr.send()
      }
    } catch (e) {
      complete(root.networkError("Could not start the Gorelo API request."))
    }
  }

  // Follow cursor pagination up to maxPages pages, then
  // callback(items, error, truncated).
  function requestAll(path, params, maxPages, callback) {
    var items = []
    var pages = 0
    function step(cursor) {
      var p = {}
      for (var k in params) p[k] = params[k]
      if (cursor) p.Cursor = cursor
      root.request("GET", path + Api.query(p), null, function(result) {
        if (!result.ok) { callback(items, result, false); return }
        var data = Array.isArray(result.data) ? result.data : []
        for (var i = 0; i < data.length; i++) items.push(data[i])
        pages++
        var next = Api.nextCursor(result.pagination)
        if (next && pages < maxPages) step(next)
        else callback(items, null, !!next)
      })
    }
    step("")
  }

  // ------------------------------------------------------------ connect

  function connect() {
    if (!root.hasKey) return
    root.supersedeRequests()
    root.phase = "connecting"
    root.lastError = ""
    root.lastErrorKind = ""
    root.lastErrorCode = ""
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
      root.fail(result.kind, result.error, result.code)
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
              root.lastErrorCode = ""
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
    if (root.polling) { root.pollRequested = true; return }
    if (!root.hasKey) return
    if (root.phase !== "connected" && root.phase !== "connecting") return
    root.polling = true
    root.pollRequested = false
    var gen = root.generation
    var serial = root.pollSerial
    var technician = root.technicianId
    var statusFilter = root.effectiveStatusIds.slice()
    var mineParams = {
      PageSize: 100, SortBy: "updatedOn", SortOrder: "desc",
      StatusIds: statusFilter, LeadAssigneeIds: technician ? [technician] : []
    }
    var allParams = { PageSize: 100, SortBy: "updatedOn", SortOrder: "desc", StatusIds: statusFilter }

    function stale() {
      return gen !== root.generation || serial !== root.pollSerial
    }

    function finishStalePoll() {
      if (gen !== root.generation) return
      root.polling = false
      if (root.pollRequested || serial !== root.pollSerial) {
        root.pollRequested = false
        Qt.callLater(function() { root.poll() })
      }
    }

    function finishPoll(mine, all, mineWasTruncated, allWasTruncated) {
      if (stale()) { finishStalePoll(); return }
      if (gen !== root.generation) return
      root.polling = false
      root.pollBackoff = 0
      root.lastPolledAt = new Date().toISOString()
      if (root.phase !== "connected") root.phase = "connected"
      root.lastError = ""
      root.lastErrorKind = ""
      root.lastErrorCode = ""

      if (root.notify && technician) {
        var events = Model.diffForNotifications(root.mineIndex, mine, root.notifyMinPriority, root.firstPollDone)
        for (var i = 0; i < events.length; i++) root.sendNotification(events[i])
      }
      root.mineIndex = Model.indexOf(mine)
      root.firstPollDone = true
      root.mineTickets = mine
      root.allTickets = all
      root.mineTruncated = mineWasTruncated
      root.allTruncated = allWasTruncated
      root.ticketRevision++
      root.rebuildRows()
      if (root.pollRequested) {
        root.pollRequested = false
        Qt.callLater(function() { root.poll() })
      }
    }

    function pollFailed(result) {
      if (stale()) { finishStalePoll(); return }
      root.polling = false
      root.fail(result.kind, result.error, result.code)
      if (result.kind === "ratelimit" || result.kind === "network") {
        root.pollBackoff = Math.min(4, root.pollBackoff + 1)
      }
    }

    function fetchAll(mine, mineWasTruncated) {
      if (stale()) { finishStalePoll(); return }
      root.requestAll("/v1/tickets", allParams, 5, function(all, err, allWasTruncated) {
        if (err) { pollFailed(err); return }
        finishPoll(mine, Api.validTicketList(all), mineWasTruncated, allWasTruncated)
      })
    }

    if (technician) {
      root.requestAll("/v1/tickets", mineParams, 5, function(mine, err, mineWasTruncated) {
        if (err) { pollFailed(err); return }
        fetchAll(Api.validTicketList(mine), mineWasTruncated)
      })
    } else {
      fetchAll([], false)
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
    if (url) args = args.concat(["--exec"].concat(root.openUrlCommand(url)))
    Quickshell.execDetached(args)
  }

  function toast(headline, body) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Gorelo",
                             "-g", Model.BRAND_ICON, "-t", "4000", headline, body || ""])
  }

  // ------------------------------------------------------------ actions

  property string actionError: ""
  property int pendingActions: 0
  readonly property bool actionBusy: pendingActions > 0

  // ------------------------------------------------------------ browsers

  // Installed browsers, from .desktop entries in the WebBrowser category:
  // [{ path, name }]. Refreshed at startup and whenever settings open.
  property var browsers: []

  property Process browserScanProcess: Process {
    command: ["bash", "-c", "for d in /usr/share/applications \"$HOME/.local/share/applications\" /var/lib/flatpak/exports/share/applications \"$HOME/.local/share/flatpak/exports/share/applications\"; do [ -d \"$d\" ] || continue; grep -lsE '^Categories=.*WebBrowser' \"$d\"/*.desktop; done 2>/dev/null | while read -r f; do printf '%s\\t%s\\n' \"$f\" \"$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-)\"; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var seen = Object.create(null)
        var out = []
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2) continue
          var path = parts[0].trim()
          var name = parts[1].trim()
          if (!path || !name || seen[name]) continue
          seen[name] = true
          out.push({ path: path, name: name })
        }
        out.sort(function(a, b) { return a.name.localeCompare(b.name) })
        root.browsers = out
      }
    }
  }

  function refreshBrowsers() {
    if (!browserScanProcess.running) browserScanProcess.running = true
  }

  // argv that opens a URL in the chosen browser, or the system default.
  function openUrlCommand(url) {
    if (root.browserDesktop) return ["gio", "launch", root.browserDesktop, url]
    return ["xdg-open", url]
  }

  function openUrl(url) {
    if (!url) return false
    if (root.browserDesktop) Quickshell.execDetached(root.openUrlCommand(url))
    else Qt.openUrlExternally(url)
    return true
  }

  function openTicket(ticketId) {
    var ticket = root.ticketFor(ticketId)
    var url = ticket ? root.urlFor(ticket) : Api.ticketUrl(root.ticketUrlTemplate, { Id: String(ticketId) })
    return root.openUrl(url)
  }

  function openWebApp() {
    root.openUrl("https://app.gorelo.io/")
  }

  function patchTicket(ticketId, patch, label, callback) {
    if (!root.connected) {
      if (callback) callback(false, "Not connected to Gorelo.")
      return false
    }
    root.pendingActions++
    root.actionError = ""
    root.request("PATCH", "/v1/tickets/" + encodeURIComponent(String(ticketId)), patch, function(r) {
      root.pendingActions = Math.max(0, root.pendingActions - 1)
      if (!r.ok) {
        root.actionError = label + " failed: " + r.error
        if (callback) callback(false, r.error)
        return
      }
      if (callback) callback(true, "")
      root.poll()
    })
    return true
  }

  function setStatus(ticketId, statusId, callback) {
    var id = parseInt(statusId, 10)
    if (isNaN(id) || id <= 0) {
      if (callback) callback(false, "Invalid status.")
      return false
    }
    return root.patchTicket(ticketId, { StatusId: id, UpdatedByName: root.technicianName || undefined }, "Status change", callback)
  }

  function assignToMe(ticketId, callback) {
    if (!root.technicianId) {
      if (callback) callback(false, "No technician selected.")
      return false
    }
    return root.patchTicket(ticketId, { LeadAssigneeId: root.technicianId, UpdatedByName: root.technicianName || undefined }, "Assignment", callback)
  }

  function addPrivateNote(ticketId, text, callback) {
    var body = String(text || "").trim()
    if (!body || !root.connected) {
      if (callback) callback(false, !body ? "A note is required." : "Not connected to Gorelo.")
      return false
    }
    root.pendingActions++
    root.actionError = ""
    var payload = { ConversationTypeId: Api.CONVERSATION_PRIVATE, Body: Api.escapeHtml(body) }
    if (root.technicianName) payload.CreatedByName = root.technicianName
    root.request("POST", "/v1/tickets/" + encodeURIComponent(String(ticketId)) + "/comments", payload, function(r) {
      root.pendingActions = Math.max(0, root.pendingActions - 1)
      if (!r.ok) {
        root.actionError = "Note failed: " + r.error
        if (callback) callback(false, r.error)
        return
      }
      if (callback) callback(true, "")
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
  property int draftRevision: 0

  function updateDraft(patch) {
    var oldAttachment = String(root.draft.attachmentPath || "")
    var next = {}
    for (var k in root.draft) next[k] = root.draft[k]
    for (var p in patch) next[p] = patch[p]
    root.draft = next
    var newAttachment = String(next.attachmentPath || "")
    if (oldAttachment && oldAttachment !== newAttachment) root.deleteAttachment(oldAttachment)
  }

  function clearDraft() {
    var attachment = String(root.draft.attachmentPath || "")
    root.draft = Model.emptyDraft()
    root.draftRevision++
    root.createError = ""
    if (attachment) root.deleteAttachment(attachment)
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
    if (root.openAfterCreate && id) root.openUrl(root.urlFor(ticket))
    root.created(id, warning)
    root.poll()
  }

  // curl does the multipart upload; the key reaches it through a config
  // file on stdin (`-K -`), never argv.
  property var uploadOperation: null
  property string uploadOutput: ""

  function curlConfigEscape(value) {
    return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
  }

  function finishUpload(error, file) {
    var operation = root.uploadOperation
    if (!operation || operation.done) return
    operation.done = true
    uploadDeadline.stop()
    root.uploadOperation = null
    root.uploadOutput = ""
    root.deleteAttachment(operation.path)
    if (operation.generation !== root.generation) return
    operation.callback(error, file)
  }

  function cancelUpload() {
    var operation = root.uploadOperation
    uploadDeadline.stop()
    root.uploadOperation = null
    root.uploadOutput = ""
    if (operation) {
      if (String(root.draft.attachmentPath || "") === operation.path) {
        root.updateDraft({ attachmentPath: "" })
      } else {
        root.deleteAttachment(operation.path)
      }
    }
    if (uploadProcess.running) uploadProcess.signal(15)
  }

  property Timer uploadDeadline: Timer {
    interval: 120000
    onTriggered: {
      if (!root.uploadOperation) return
      root.finishUpload("The screenshot upload timed out.", null)
      if (uploadProcess.running) uploadProcess.signal(15)
    }
  }

  property Process uploadProcess: Process {
    command: []
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.uploadOutput = String(text || "")
    }
    onStarted: {
      var operation = root.uploadOperation
      if (!operation) {
        uploadProcess.signal(15)
        return
      }
      uploadProcess.write("header = \"X-API-Key: " + root.curlConfigEscape(operation.apiKey) + "\"\n")
      uploadProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      var operation = root.uploadOperation
      if (!operation) return
      var raw = root.uploadOutput
      var lines = raw.trim().split("\n")
      var code = parseInt(lines.pop(), 10)
      var parsed = Api.parseResponse(isNaN(code) ? 0 : code, lines.join("\n"))
      if (exitCode !== 0 && !parsed.ok) { root.finishUpload(parsed.error || ("curl exited " + exitCode), null); return }
      if (!parsed.ok) { root.finishUpload(parsed.error, null); return }
      var file = parsed.data
      if (!file || !file.Name || !file.Url) { root.finishUpload("Unexpected upload response.", null); return }
      root.finishUpload("", file)
    }
  }

  function uploadAttachment(ticketId, path, callback) {
    if (root.uploadOperation || uploadProcess.running) { callback("An upload is already running.", null); return }
    if (path.indexOf('"') !== -1 || path.indexOf("\n") !== -1) { callback("Unsupported characters in the file path.", null); return }
    root.uploadOutput = ""
    var url = Api.baseUrl(root.region) + "/v1/tickets/" + encodeURIComponent(String(ticketId)) + "/attachments"
    root.uploadOperation = {
      generation: root.generation, region: root.region, apiKey: root.apiKey,
      ticketId: String(ticketId), url: url, path: String(path),
      callback: callback, done: false
    }
    uploadProcess.command = ["curl", "-sS", "--max-time", "115", "-K", "-",
                             "-F", "file=@\"" + path + "\"",
                             "-w", "\n%{http_code}", url]
    uploadProcess.stdinEnabled = true
    uploadDeadline.restart()
    uploadProcess.running = true
  }

  // Region select → save → the overlay re-summons itself with the path in
  // the draft. The overlay dismisses first so it is not in the shot.
  property string capturePath: ""
  readonly property string screenshotDir: Quickshell.env("XDG_RUNTIME_DIR") + "/gorelo"
  property int captureRevision: -1
  property bool capturePending: false
  property var deleteQueue: []

  function deleteAttachment(path) {
    var target = String(path || "")
    if (!target || target.indexOf(root.screenshotDir + "/") !== 0) return
    var queue = root.deleteQueue.slice()
    queue.push(target)
    root.deleteQueue = queue
    if (!cleanupProcess.running) root.startNextDelete()
  }

  function startNextDelete() {
    if (!root.deleteQueue.length || cleanupProcess.running) return
    cleanupProcess.command = ["rm", "-f", root.deleteQueue[0]]
    cleanupProcess.running = true
  }

  property Process cleanupProcess: Process {
    command: []
    onExited: {
      var queue = root.deleteQueue.slice()
      if (queue.length) queue.shift()
      root.deleteQueue = queue
      root.startNextDelete()
    }
  }

  function summonNewTicket() {
    if (root.shell && typeof root.shell.summon === "function") {
      root.shell.summon(root.pluginId, JSON.stringify({ tab: "new" }))
    }
  }

  property Process captureDirProcess: Process {
    command: ["mkdir", "-m", "700", "-p", root.screenshotDir]
    onExited: function(exitCode) {
      if (!root.capturePending) return
      if (exitCode === 0) captureDelay.restart()
      else {
        root.capturePending = false
        root.capturing = false
        root.captureRevision = -1
        captureDeadline.stop()
        root.createError = "Could not create the private screenshot directory."
        root.summonNewTicket()
      }
    }
  }

  property Process captureProcess: Process {
    command: ["omarchy", "capture", "screenshot", "region", "save"]
    environment: ({ "OMARCHY_SCREENSHOT_DIR": root.screenshotDir })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.capturePath = String(text || "").trim().split("\n").pop()
    }
    onExited: function(exitCode) {
      if (!root.capturePending) {
        if (root.capturePath) root.deleteAttachment(root.capturePath)
        root.capturePath = ""
        return
      }
      root.capturePending = false
      root.capturing = false
      captureDeadline.stop()
      var path = exitCode === 0 ? root.capturePath : ""
      root.capturePath = ""
      var current = root.captureRevision === root.draftRevision
      if (path && current) root.updateDraft({ attachmentPath: path })
      else if (path) root.deleteAttachment(path)
      root.captureRevision = -1
      // The draft was discarded or sent while the region picker was open;
      // reopening an empty form would only be confusing.
      if (current) root.summonNewTicket()
    }
  }

  property Timer captureDeadline: Timer {
    interval: 5 * 60 * 1000
    onTriggered: {
      if (!root.capturePending) return
      root.capturePending = false
      root.capturing = false
      root.captureRevision = -1
      root.createError = "Screenshot capture timed out."
      captureDelay.stop()
      if (captureDirProcess.running) captureDirProcess.signal(15)
      if (captureProcess.running) captureProcess.signal(15)
      root.summonNewTicket()
    }
  }

  property Timer captureDelay: Timer {
    interval: 350
    onTriggered: if (root.capturePending) captureProcess.running = true
  }

  function captureScreenshot() {
    if (root.capturing || root.capturePending || captureDirProcess.running || captureProcess.running) return false
    root.capturing = true
    root.capturePending = true
    root.captureRevision = root.draftRevision
    root.capturePath = ""
    captureDeadline.restart()
    captureDirProcess.running = true
    return true
  }

  // Redacted: no key, no client names, no ticket titles.
  function statusLine() {
    var safeCode = String(root.lastErrorCode || "").replace(/[^A-Za-z0-9._-]/g, "")
    return "phase=" + root.phase
      + " region=" + root.region
      + " key=" + (root.hasKey ? "present" : "absent")
      + " technician=" + (root.technicianId ? "set" : "unset")
      + " reference=" + root.referenceLoaded
      + " mine=" + root.mineTickets.length
      + " all=" + root.allTickets.length
      + " backoff=" + root.pollBackoff
      + (root.lastPolledAt ? " polled=" + root.lastPolledAt : "")
      + (root.lastErrorKind ? " error=" + root.lastErrorKind
          + (safeCode ? ":" + safeCode : "") : "")
  }
}
