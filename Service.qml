import QtQuick
import Quickshell
import Quickshell.Io
import "Api.js" as Api
import "Model.js" as Model
import "ConfigStore.js" as ConfigStore

// Orchestration only: generation guards a connection lifetime; operation
// Serial counters guard work within it. Revision properties notify changes.
QtObject {
  id: root
  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy/gorelo"
  readonly property string configPath: configDir + "/config.json"
  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.vichong.gorelo"

  property string region: "usw"
  property bool demoMode: false
  property int technicianId: 0
  property string technicianName: ""
  property int pollSeconds: ConfigStore.POLL_DEFAULT
  property bool notify: true
  property int notifyMinPriority: 3
  property var statusIds: []
  property int defaultStatusId: 0
  property int defaultGroupId: 0
  property int defaultTypeId: 0
  property string ticketUrlTemplate: ConfigStore.DEFAULT_TICKET_URL
  property string deviceUrlTemplate: ConfigStore.DEFAULT_DEVICE_URL
  property string activeTab: "mine"
  property bool openAfterCreate: true
  property string browserDesktop: ""
  property bool configLoaded: false
  property string configError: ""

  property FileView configFile: FileView {
    path: root.configPath; watchChanges: true; printErrors: false; atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }
  property Process configDirProcess: Process { command: ["mkdir", "-p", root.configDir] }
  Component.onCompleted: {
    configDirProcess.running = true
    browserLauncher.refreshBrowsers()
  }
  function currentConfig() {
    return {
      region: region, demoMode: demoMode, technicianId: technicianId, technicianName: technicianName,
      pollSeconds: pollSeconds, notify: notify, notifyMinPriority: notifyMinPriority,
      statusIds: statusIds.slice(), defaultStatusId: defaultStatusId, defaultGroupId: defaultGroupId,
      defaultTypeId: defaultTypeId, ticketUrlTemplate: ticketUrlTemplate,
      deviceUrlTemplate: deviceUrlTemplate, activeTab: activeTab,
      openAfterCreate: openAfterCreate, browserDesktop: browserDesktop
    }
  }
  function saveConfig(patch) {
    var text = ConfigStore.serialize(ConfigStore.merge(currentConfig(), patch))
    configFile.setText(text)
    applyConfig(text)
  }
  function applyConfig(text) {
    var parsed = ConfigStore.parse(text)
    var c = parsed.config
    configError = parsed.error
    var connectionChanged = !configLoaded || region !== c.region || demoMode !== c.demoMode
    var filterChanged = JSON.stringify(statusIds) !== JSON.stringify(c.statusIds) || technicianId !== c.technicianId
    var tabChanged = activeTab !== c.activeTab
    var browserChanged = browserDesktop !== c.browserDesktop
    region = c.region; demoMode = c.demoMode; technicianId = c.technicianId; technicianName = c.technicianName
    pollSeconds = c.pollSeconds; notify = c.notify; notifyMinPriority = c.notifyMinPriority; statusIds = c.statusIds
    defaultStatusId = c.defaultStatusId; defaultGroupId = c.defaultGroupId; defaultTypeId = c.defaultTypeId
    ticketUrlTemplate = c.ticketUrlTemplate; deviceUrlTemplate = c.deviceUrlTemplate
    activeTab = c.activeTab; openAfterCreate = c.openAfterCreate; browserDesktop = c.browserDesktop
    if (browserChanged) browserLauncher.browserWarning = ""
    configLoaded = true
    if (connectionChanged) {
      supersedeRequests(); apiKey = ""; resetData(); phase = "idle"; clearError()
      if (root.demoMode) { demoBackend.reset(); connect(); return }
      var pending = pendingConnection
      if (pending && pending.region === region && pending.key) {
        pendingConnection = null; phase = "connecting"; credentials.store(pending.key, pending.region); pending.key = ""
      } else if (!credentials.busy) credentials.lookup(region)
      else pendingLookupRegion = region
    } else if (filterChanged && connected) {
      mineIndex = Object.create(null); firstPollDone = false; pollSerial++; pollRequested = true
      if (!polling) poll()
    } else if (tabChanged) {
      rebuildRows()
      if (connected && activeTab === "all") poll()
    }
  }
  function setActiveTab(tab) {
    var next = tab === "all" ? "all" : "mine"
    var changed = next !== activeTab
    leaveSearch()
    if (!changed) { rebuildRows(); return }
    activeTab = next; rebuildRows()
    if (connected && next === "all") poll()
    tabSaveDebounce.restart()
  }
  property Timer tabSaveDebounce: Timer { interval: 300; onTriggered: root.saveConfig({ activeTab: root.activeTab }) }

  property LiveBackend liveBackend: LiveBackend {
    region: root.region; apiKey: root.apiKey; deleteAttachment: root.deleteAttachment
  }
  property DemoBackend demoBackend: DemoBackend { deleteAttachment: root.deleteAttachment }
  property var backend: demoMode ? demoBackend : liveBackend
  property Capture capture: Capture {
    draftRevision: root.draftRevision
    updateDraft: root.updateDraft
    reportError: function(message) { root.createError = message }
    summon: root.summonNewTicket
  }
  readonly property bool capturing: capture.capturing
  readonly property int captureRevision: capture.captureRevision
  property BrowserLauncher browserLauncher: BrowserLauncher { browserDesktop: root.browserDesktop }
  readonly property var browsers: browserLauncher.browsers
  readonly property string browserWarning: browserLauncher.browserWarning
  function refreshBrowsers() { browserLauncher.refreshBrowsers() }
  function openUrlCommand(url) { return browserLauncher.openUrlCommand(url) }

  property string apiKey: ""
  readonly property bool hasKey: backend === demoBackend || apiKey !== ""
  readonly property bool credentialBusy: credentials.busy
  property var pendingConnection: null
  property string pendingLookupRegion: ""
  onCredentialBusyChanged: {
    if (backend !== liveBackend || credentialBusy || !pendingLookupRegion) return
    var wanted = pendingLookupRegion; pendingLookupRegion = ""
    if (wanted === region && !hasKey) credentials.lookup(wanted)
  }
  property CredentialManager credentials: CredentialManager {
    onKeyReady: function(key, keyRegion) {
      if (root.backend !== root.liveBackend || keyRegion !== root.region) return
      if (root.keyHasUnsupportedCharacters(key)) {
        root.apiKey = ""; root.setError("config", "The stored API key contains unsupported quotes, backslashes, or control characters.", ""); return
      }
      root.apiKey = key; root.connect()
    }
    onMissing: function(keyRegion) {
      if (root.backend !== root.liveBackend || keyRegion !== root.region) return
      root.apiKey = ""; root.phase = "idle"; root.clearError()
    }
    onCleared: function(keyRegion) {
      if (root.backend !== root.liveBackend || keyRegion !== root.region) return
      root.apiKey = ""; root.supersedeRequests(); root.resetData(); root.phase = "idle"; root.clearError()
    }
    onFailed: function(message, keyRegion) {
      if (root.backend !== root.liveBackend || (keyRegion && keyRegion !== root.region)) return
      root.phase = "error"; root.setError("credential", message, "")
    }
  }
  function keyHasUnsupportedCharacters(key) { return /["\\\x00-\x1f\x7f]/.test(String(key || "")) }
  function keyringReady() {
    if (!credentialBusy) return true
    // A notice only: it must not flip a connected panel into "error" (which
    // stops polling and never auto-retries for credential kinds).
    lastErrorKind = "credential"; lastError = "Wait for the current keyring operation to finish."; lastErrorCode = ""
    return false
  }
  function applyConnection(nextRegion, key) {
    if (backend !== liveBackend || !Api.isRegion(nextRegion) || !keyringReady()) return false
    var switching = nextRegion !== region
    var raw = String(key || "")
    if (raw && keyHasUnsupportedCharacters(raw)) {
      phase = "error"; setError("config", "The API key contains unsupported quotes, backslashes, or control characters.", ""); return false
    }
    var trimmed = raw.trim()
    if (switching) {
      pendingConnection = trimmed ? { region: nextRegion, key: trimmed } : null
      saveConfig({ region: nextRegion, technicianId: 0, technicianName: "", statusIds: [],
                   defaultStatusId: 0, defaultGroupId: 0, defaultTypeId: 0 })
    }
    if (trimmed) {
      phase = "connecting"; clearError()
      if (switching) return true
      return credentials.store(trimmed, nextRegion)
    }
    if (!hasKey && !credentialBusy) credentials.lookup(nextRegion)
    else if (hasKey) connect()
    return true
  }
  function removeConnection() { if (backend === liveBackend && keyringReady()) credentials.clear(region) }
  function setDemoMode(enabled) {
    var next = enabled === true
    if ((backend === demoBackend) === next) return true
    if (!keyringReady()) return false
    var patch = { demoMode: next }
    saveConfig(patch); return true
  }

  property string phase: "idle"
  property string lastError: ""
  property string lastErrorKind: ""
  property string lastErrorCode: ""
  property int generation: 0
  readonly property bool configured: hasKey
  readonly property bool connected: phase === "connected"
  readonly property int effectiveTechnicianId: backend === demoBackend ? 1 : technicianId
  readonly property string effectiveTechnicianName: backend === demoBackend ? "Demo Tech" : technicianName
  readonly property int effectiveDefaultStatusId: backend === demoBackend ? 1 : defaultStatusId
  readonly property int effectiveDefaultGroupId: backend === demoBackend ? 1 : defaultGroupId
  readonly property int effectiveDefaultTypeId: backend === demoBackend ? 1 : defaultTypeId
  readonly property bool needsTechnician: connected && effectiveTechnicianId === 0

  property var statuses: []
  property var types: []
  property var groups: []
  property var users: []
  property var clients: []
  property var statusNames: Object.create(null)
  property var typeNames: Object.create(null)
  property var groupNames: Object.create(null)
  property var clientNames: Object.create(null)
  property var userNames: Object.create(null)
  property bool referenceLoaded: false
  property var devices: []
  property bool devicesLoaded: false
  property bool devicesLoading: false
  property string devicesError: ""
  property bool devicesTruncated: false
  property int deviceLoadSerial: 0
  property var deviceHits: []
  property bool deviceSearching: false
  property string deviceSearchError: ""
  property ListModel deviceRows: ListModel {}
  property var mineTickets: []
  property var allTickets: []
  property string searchQuery: ""
  property bool searchActive: false
  property bool searching: false
  property var searchResults: []
  property string searchError: ""
  property int searchSerial: 0
  property string searchPendingQuery: ""
  property int searchPendingCount: 0
  property var searchRequests: []
  property var mineIndex: Object.create(null)
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
  property int rowsRevision: 0
  property ListModel rows: ListModel {}
  readonly property var effectiveStatusIds: backend === demoBackend
    ? Api.defaultStatusIds(statuses) : (statusIds.length ? statusIds : Api.defaultStatusIds(statuses))
  readonly property var mineCounts: { ticketRevision; return Model.counts(mineTickets) }
  readonly property var allCounts: { ticketRevision; return Model.counts(allTickets) }
  readonly property string activitySummary: {
    ticketRevision
    if (!connected) return ""
    if (needsTechnician) return "Pick who you are in settings"
    var c = mineCounts
    var parts = [c.total + (c.total === 1 ? " ticket" : " tickets")]
    if (c.unread) parts.push(c.unread + " unread")
    if (c.urgent) parts.push(c.urgent + " urgent")
    if (mineTruncated) parts.push("showing first 500")
    return parts.join(" · ")
  }
  readonly property bool transientError: lastErrorKind === "ratelimit" || lastErrorKind === "network"
    || lastErrorKind === "protocol" || lastErrorKind === "api"
  function setError(kind, message, code) {
    lastErrorKind = String(kind || ""); lastError = String(message || ""); lastErrorCode = String(code || "")
    if (kind === "credential" || kind === "config") { phase = "error"; polling = false }
  }
  function clearError() { lastErrorKind = ""; lastError = ""; lastErrorCode = "" }

  function resetData() {
    clearDraft()
    statuses = []; types = []; groups = []; users = []; clients = []
    statusNames = Object.create(null); typeNames = Object.create(null); groupNames = Object.create(null)
    clientNames = Object.create(null); userNames = Object.create(null); referenceLoaded = false
    devices = []; devicesLoaded = false; devicesLoading = false; devicesError = ""; devicesTruncated = false
    deviceLoadSerial++; deviceHits = []; deviceSearching = false; deviceSearchError = ""
    mineTickets = []; allTickets = []; searchQuery = ""; searchActive = false; searching = false
    searchResults = []; searchError = ""; searchSerial++; searchPendingQuery = ""; searchPendingCount = 0
    searchRequests = []; mineIndex = Object.create(null); firstPollDone = false
    polling = false; pollRequested = false; mineTruncated = false; allTruncated = false; pollBackoff = 0
    rows.clear(); deviceRows.clear(); rowsRevision++; ticketRevision++
  }
  function supersedeRequests() {
    var upload = liveBackend.uploadOperation
    if (upload && String(draft.attachmentPath || "") === String(upload.path || "")) updateDraft({ attachmentPath: "" })
    backend.supersede()
    if (backend === liveBackend) demoBackend.supersede()
    else liveBackend.supersede()
    polling = false; pollRequested = false; pendingActions = 0; creating = false
    searching = false; deviceSearching = false; searchPendingQuery = ""; searchPendingCount = 0
    searchRequests = []; devicesLoading = false; generation++
  }

  property int reconnectAttempts: 0
  property Timer reconnectTimer: Timer {
    interval: Math.min(300000, 30000 * Math.pow(2, Math.min(4, root.reconnectAttempts)))
    onTriggered: if (!root.connected && root.hasKey && root.phase === "error" && root.transientError) root.connect()
  }
  function connect() {
    if (!hasKey) return
    supersedeRequests(); reconnectTimer.stop(); phase = "connecting"; clearError()
    loadReference(function(ok) {
      if (!ok) {
        if (phase === "error" && transientError) {
          reconnectTimer.restart(); reconnectAttempts = Math.min(8, reconnectAttempts + 1)
        }
        return
      }
      reconnectAttempts = 0; phase = "connected"; pollBackoff = 0; poll()
    })
  }
  function retryConnection() {
    reconnectAttempts = 0
    if (hasKey) connect()
    else if (!credentialBusy) credentials.lookup(region)
  }
  function refresh() { if (!connected) retryConnection(); else poll() }
  function refreshReference() {
    if (!connected) { retryConnection(); return }
    loadReference(function(ok) { if (ok) poll() })
  }
  function loadReference(done) {
    var token = generation
    backend.loadReference(function(result) {
      if (token !== generation) return
      if (!result.ok) {
        setError(result.kind, result.error, result.code)
        if (phase === "connecting") phase = "error"
        done(false); return
      }
      var data = result.data || {}
      statuses = Api.sortStatuses(Array.isArray(data.statuses) ? data.statuses : [])
      types = Array.isArray(data.types) ? data.types : []
      groups = Array.isArray(data.groups) ? data.groups : []
      users = Array.isArray(data.users) ? data.users : []
      clients = Array.isArray(data.clients) ? data.clients : []
      statusNames = Api.nameMap(statuses); typeNames = Api.nameMap(types); groupNames = Api.nameMap(groups)
      userNames = Api.nameMap(users, Api.userDisplayName); clientNames = Api.nameMap(clients)
      referenceLoaded = true; clearError(); done(true)
    })
  }
  property Timer referenceRefresh: Timer {
    interval: 30 * 60 * 1000; repeat: true; running: root.connected
    onTriggered: {
      var reloadDevices = root.devicesLoaded
      root.loadReference(function(ok) { if (ok && reloadDevices && root.connected) root.loadDevices() })
    }
  }

  readonly property int effectivePollMs: Math.min(600000, pollSeconds * 1000 * Math.pow(2, pollBackoff))
  property Timer pollTimer: Timer {
    interval: root.effectivePollMs; repeat: true; running: root.connected; onTriggered: root.poll()
  }
  function poll() {
    if (polling) { pollRequested = true; return }
    if (!hasKey || (phase !== "connected" && phase !== "connecting")) return
    polling = true; pollRequested = false
    var token = generation
    var serial = pollSerial
    var technician = effectiveTechnicianId
    var fetchAll = activeTab === "all"
    var filter = effectiveStatusIds.slice()
    var mineParams = { PageSize: 100, SortBy: "updatedOn", SortOrder: "desc",
                       StatusIds: filter, LeadAssigneeIds: technician ? [technician] : [] }
    var allParams = { PageSize: 100, SortBy: "updatedOn", SortOrder: "desc", StatusIds: filter }
    function stale() { return token !== generation || serial !== pollSerial }
    function finishStale() {
      if (token !== generation) return
      polling = false
      if (pollRequested || serial !== pollSerial) { pollRequested = false; Qt.callLater(root.poll) }
    }
    function failed(result) {
      if (stale()) { finishStale(); return }
      polling = false; setError(result.kind, result.error, result.code)
      if (result.kind === "ratelimit" || result.kind === "network") pollBackoff = Math.min(4, pollBackoff + 1)
    }
    function finish(mine, all, mineCut, allCut) {
      if (stale()) { finishStale(); return }
      polling = false; pollBackoff = 0; lastPolledAt = new Date().toISOString(); phase = "connected"; clearError()
      if (notify && technician) {
        var events = Model.diffForNotifications(mineIndex, mine, notifyMinPriority, firstPollDone)
        var batch = Model.summarizeNotificationEvents(events, 5)
        if (batch.summary) sendNotificationSummary(batch.summary)
        else for (var i = 0; i < batch.events.length; i++) sendNotification(batch.events[i])
      }
      mineIndex = Model.indexOf(mine); firstPollDone = true; mineTickets = mine; allTickets = all
      mineTruncated = mineCut; allTruncated = allCut; ticketRevision++; rebuildRows()
      if (pollRequested) { pollRequested = false; Qt.callLater(root.poll) }
    }
    function fetchAllTickets(mine, mineCut) {
      if (stale()) { finishStale(); return }
      if (!fetchAll || activeTab !== "all") { finish(mine, allTickets, mineCut, allTruncated); return }
      backend.listTickets(allParams, function(result) {
        if (!result.ok) { failed(result); return }
        finish(mine, Api.validTicketList(result.data), mineCut, result.truncated === true)
      })
    }
    if (technician) {
      backend.listTickets(mineParams, function(result) {
        if (!result.ok) { failed(result); return }
        fetchAllTickets(Api.validTicketList(result.data), result.truncated === true)
      })
    } else fetchAllTickets([], false)
  }

  function rowContext() {
    return { clientNames: clientNames, userNames: userNames, statusNames: statusNames,
             technicianId: effectiveTechnicianId, now: Date.now() }
  }
  function urlFor(ticket) { return Api.ticketUrl(ticketUrlTemplate, ticket) }
  function urlForDevice(device) { return Api.deviceUrl(deviceUrlTemplate, device) }
  function allDevices() { return Model.mergeDevices(devices, deviceHits) }
  function loadDevices() {
    if (!connected || devicesLoading) return false
    var token = generation
    var serial = ++deviceLoadSerial
    devicesLoading = true; devicesError = ""
    backend.listDevices(function(result) {
      if (token !== generation || serial !== deviceLoadSerial) return
      devicesLoading = false
      if (!result.ok) { devicesError = result.error; rebuildRows(); return }
      var items = Array.isArray(result.data) ? result.data : []
      devices = items.slice(0, 2000); devicesLoaded = true
      devicesTruncated = result.truncated === true || items.length > 2000
      devicesError = ""; rebuildRows()
    })
    return true
  }
  property Timer searchDebounce: Timer { interval: 120; onTriggered: root.rebuildRows() }
  function abortSearchRequests() {
    var requests = searchRequests.slice()
    searchRequests = []; searchPendingQuery = ""; searchPendingCount = 0
    for (var i = 0; i < requests.length; i++) {
      if (requests[i] && typeof requests[i].abort === "function") requests[i].abort()
    }
    searching = false; deviceSearching = false
  }
  function leaveSearch() {
    abortSearchRequests(); searchSerial++; searchActive = false; searching = false
    deviceSearching = false; searchResults = []; searchError = ""; deviceSearchError = ""
  }
  function setSearchQuery(text) {
    var next = String(text || "")
    if (next === searchQuery) return
    searchQuery = next; deviceSearchError = ""; leaveSearch()
    if (!next.trim()) { searchDebounce.stop(); rebuildRows(); return }
    if (connected && !devicesLoaded && !devicesLoading) loadDevices()
    searchDebounce.restart()
  }
  function finishSearchRequest(query, serial) {
    if (serial !== searchSerial || query !== searchPendingQuery) return
    searchPendingCount = Math.max(0, searchPendingCount - 1)
    if (searchPendingCount === 0) { searchPendingQuery = ""; searchRequests = [] }
  }
  function runSearch() {
    var query = searchQuery.trim()
    if (!query || !connected || (searchPendingCount > 0 && searchPendingQuery === query)) return false
    abortSearchRequests(); searchDebounce.stop()
    var token = generation
    var serial = ++searchSerial
    searchActive = true; searching = true; deviceSearching = true
    searchResults = []; searchError = ""; deviceSearchError = ""
    searchPendingQuery = query; searchPendingCount = 2; rebuildRows()
    var ticketRequest = backend.searchTickets(query, function(result) {
      if (token !== generation || serial !== searchSerial) return
      searching = false; finishSearchRequest(query, serial)
      if (!result.ok) { searchError = result.error; searchResults = [] }
      else { searchError = ""; searchResults = Api.validTicketList(result.data) }
      rebuildRows()
    })
    var deviceRequest = backend.searchDevices(query, function(result) {
      if (token !== generation || serial !== searchSerial) return
      deviceSearching = false; finishSearchRequest(query, serial)
      if (!result.ok) deviceSearchError = result.error
      else { deviceHits = Model.updateDeviceHits(deviceHits, result.data, 200); deviceSearchError = "" }
      rebuildRows()
    })
    searchRequests = [ticketRequest, deviceRequest]
    return true
  }
  function clearSearch() { searchDebounce.stop(); leaveSearch(); searchQuery = ""; rebuildRows() }
  function rebuildRows() {
    var source = searchActive ? searchResults : (activeTab === "all" ? allTickets : mineTickets)
    var context = rowContext()
    var filtered = searchActive ? source.slice() : Model.filterTickets(source, context, searchQuery)
    var list = Model.buildRows(filtered, context, urlFor)
    rows.clear()
    for (var i = 0; i < list.length; i++) rows.append(list[i])
    deviceRows.clear()
    var query = searchQuery.trim()
    if (query) {
      var matches = Model.filterDevices(allDevices(), context, query, 8)
      for (var j = 0; j < matches.length; j++) deviceRows.append(Model.projectDeviceRow(matches[j], context, urlForDevice))
    }
    rowsRevision++
  }
  function indexOfTicket(id) {
    for (var i = 0; i < rows.count; i++) if (String(rows.get(i).ticketId) === String(id || "")) return i
    return -1
  }
  function indexOfDevice(id) {
    for (var i = 0; i < deviceRows.count; i++) if (String(deviceRows.get(i).deviceId) === String(id || "")) return i
    return -1
  }
  function ticketFor(id) {
    var wanted = String(id)
    var sources = [searchResults, allTickets, mineTickets]
    for (var s = 0; s < sources.length; s++) for (var i = 0; i < sources[s].length; i++) {
      if (String(sources[s][i].Id) === wanted) return sources[s][i]
    }
    return null
  }
  function deviceFor(id) {
    var list = allDevices()
    for (var i = 0; i < list.length; i++) if (String(list[i].Id) === String(id)) return list[i]
    return null
  }

  function sendNotification(event) {
    var text = Model.notificationText(event)
    var ticket = event.ticket
    var url = urlFor(ticket)
    var args = ["omarchy-notification-send", "--app-name", "Gorelo", "-g", Model.BRAND_ICON,
                "-u", Model.priorityIdOf(ticket) === 1 ? "critical" : "normal",
                "-r", String(Model.notificationTag(ticket.Id)),
                Model.escapeMarkup(text.headline), Model.escapeMarkup(text.body)]
    if (url && !root.demoMode) args = args.concat(["--exec"].concat(openUrlCommand(url)))
    Quickshell.execDetached(args)
  }
  function sendNotificationSummary(summary) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Gorelo", "-g", Model.BRAND_ICON,
                             "-r", String(Model.notificationTag("notification-summary")),
                             "Gorelo", Model.escapeMarkup(summary)])
  }
  function toast(headline, body) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Gorelo", "-g", Model.BRAND_ICON,
                             "-t", "4000", Model.escapeMarkup(headline), Model.escapeMarkup(body || "")])
  }
  function openUrl(url) {
    if (!url) return false
    if (root.demoMode) { toast("Demo mode", "Would open " + url); return true }
    return browserLauncher.openUrl(url)
  }
  function openTicket(id) {
    var ticket = ticketFor(id)
    return openUrl(ticket ? urlFor(ticket) : Api.ticketUrl(ticketUrlTemplate, { Id: String(id) }))
  }
  function openDevice(id) {
    var device = deviceFor(id)
    return openUrl(device ? urlForDevice(device) : Api.deviceUrl(deviceUrlTemplate, { Id: String(id), Name: "" }))
  }

  property string actionError: ""
  property int pendingActions: 0
  readonly property bool actionBusy: pendingActions > 0
  function patchTicket(ticketId, patch, label, callback) {
    if (!connected) { if (callback) callback(false, "Not connected to Gorelo."); return false }
    pendingActions++; actionError = ""
    backend.patchTicket(ticketId, patch, function(result) {
      pendingActions = Math.max(0, pendingActions - 1)
      if (!result.ok) {
        actionError = label + " failed: " + result.error
        if (callback) callback(false, result.error)
        return
      }
      if (callback) callback(true, "")
      refreshAfterMutation()
    })
    return true
  }
  function refreshAfterMutation() { if (searchActive) runSearch(); poll() }
  function setStatus(ticketId, statusId, callback) {
    var id = parseInt(statusId, 10)
    if (isNaN(id) || id <= 0) { if (callback) callback(false, "Invalid status."); return false }
    return patchTicket(ticketId, { StatusId: id, UpdatedByName: effectiveTechnicianName || undefined },
                       "Status change", callback)
  }
  function assignToMe(ticketId, callback) {
    if (!effectiveTechnicianId) { if (callback) callback(false, "No technician selected."); return false }
    return patchTicket(ticketId, { LeadAssigneeId: effectiveTechnicianId,
                                   UpdatedByName: effectiveTechnicianName || undefined },
                       "Assignment", callback)
  }
  function addPrivateNote(ticketId, text, callback) {
    var note = String(text || "").trim()
    if (!note || !connected) {
      if (callback) callback(false, !note ? "A note is required." : "Not connected to Gorelo.")
      return false
    }
    pendingActions++; actionError = ""
    var payload = { ConversationTypeId: Api.CONVERSATION_PRIVATE, Body: Api.escapeHtml(note) }
    if (effectiveTechnicianName) payload.CreatedByName = effectiveTechnicianName
    backend.addComment(ticketId, payload, function(result) {
      pendingActions = Math.max(0, pendingActions - 1)
      if (!result.ok) {
        actionError = "Note failed: " + result.error
        if (callback) callback(false, result.error)
        return
      }
      if (callback) callback(true, "")
      refreshAfterMutation()
    })
    return true
  }

  property var draft: Model.emptyDraft()
  signal created(string id, string warning)
  property bool creating: false
  property string createError: ""
  property string lastCreatedId: ""
  property int draftRevision: 0
  readonly property var createDefaults: ({
    statusId: effectiveDefaultStatusId, groupId: effectiveDefaultGroupId, typeId: effectiveDefaultTypeId
  })
  function updateDraft(patch) {
    var oldAttachment = String(draft.attachmentPath || "")
    var next = {}
    for (var key in draft) next[key] = draft[key]
    for (var name in patch) next[name] = patch[name]
    draft = next
    var newAttachment = String(next.attachmentPath || "")
    if (oldAttachment && oldAttachment !== newAttachment) deleteAttachment(oldAttachment)
  }
  function clearDraft() {
    var attachment = String(draft.attachmentPath || "")
    draft = Model.emptyDraft(); draftRevision++; createError = ""
    if (attachment) deleteAttachment(attachment)
  }
  function createTicket() {
    if (creating) return false
    var problem = Model.validateDraft(draft, createDefaults)
    if (problem) { createError = problem; return false }
    if (!connected) { createError = "Not connected to Gorelo."; return false }
    if (!clientNames[String(draft.clientId)]) { createError = "Pick a client from the current list."; return false }
    var body = {
      Title: String(draft.title).trim(), ClientId: draft.clientId,
      StatusId: effectiveDefaultStatusId, GroupId: effectiveDefaultGroupId,
      TypeId: effectiveDefaultTypeId, PriorityId: draft.priorityId, IsUnread: false
    }
    if (String(draft.description || "").trim()) body.Description = String(draft.description).trim()
    if (effectiveTechnicianId) body.LeadAssigneeId = effectiveTechnicianId
    if (effectiveTechnicianName) body.CreatedByName = effectiveTechnicianName
    creating = true; createError = ""
    var attachment = String(draft.attachmentPath || "")
    backend.createTicket(body, function(result) {
      if (!result.ok) { creating = false; createError = result.error; return }
      var id = result.data && result.data.Id ? String(result.data.Id) : ""
      lastCreatedId = id
      if (!attachment || !id) { finishCreate(id, ""); return }
      backend.uploadAttachment(id, attachment, function(upload) {
        if (!upload.ok) {
          finishCreate(id, "Ticket created, but the screenshot upload failed: " + upload.error)
          return
        }
        if (backend === demoBackend) { finishCreate(id, ""); return }
        var payload = { ConversationTypeId: Api.CONVERSATION_PRIVATE, Body: "Screenshot",
                        Attachments: [{ Name: upload.data.Name, Url: upload.data.Url }] }
        if (effectiveTechnicianName) payload.CreatedByName = effectiveTechnicianName
        backend.addComment(id, payload, function(comment) {
          finishCreate(id, comment.ok ? "" : "Ticket created, but attaching the screenshot failed: " + comment.error)
        })
      })
    })
    return true
  }
  function finishCreate(id, warning) {
    creating = false; clearDraft()
    if (warning) createError = warning
    toast("Ticket created", warning || "")
    if (openAfterCreate && id) openUrl(urlFor({ Id: id }))
    refreshAfterMutation()
    created(id, warning)
  }
  function deleteAttachment(path) { capture.deleteAttachment(path) }
  function captureScreenshot() { return capture.captureScreenshot() }
  function summonNewTicket() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, JSON.stringify({ tab: "new" }))
  }
  function statusLine() {
    var safeCode = String(lastErrorCode || "").replace(/[^A-Za-z0-9._-]/g, "")
    return "phase=" + phase + " region=" + region + " demo=" + (backend === demoBackend)
      + " key=" + (hasKey ? "present" : "absent")
      + " technician=" + (effectiveTechnicianId ? "set" : "unset")
      + " reference=" + referenceLoaded + " mine=" + mineTickets.length + " all=" + allTickets.length
      + " backoff=" + pollBackoff + (lastPolledAt ? " polled=" + lastPolledAt : "")
      + (lastErrorKind ? " error=" + lastErrorKind + (safeCode ? ":" + safeCode : "") : "")
  }
}
