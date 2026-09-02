import QtQuick
import Quickshell.Io

// Serialized system-keyring adapter. The key is written only to stdin and is
// scoped by region. One process, deadline and token cover every operation.
QtObject {
  id: root

  readonly property bool busy: pending || operationProcess.running
  property bool pending: false
  property int operationToken: 0
  property int processToken: 0
  property string operation: ""
  property string operationRegion: ""
  property string operationKey: ""
  property string operationOutput: ""
  readonly property int maxLookupBytes: 4096
  readonly property string boundedHelperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/gorelo-bounded")).replace(/^file:\/\//, ""))

  signal keyReady(string key, string region)
  signal missing(string region)
  signal cleared(string region)
  signal failed(string message, string region)

  function begin(kind, region, key) {
    if (root.busy || !region || (kind === "store" && !key)) {
      if (kind !== "lookup") root.failed("A keyring operation is already in progress.", region || "")
      return false
    }
    root.operation = kind
    root.operationRegion = String(region)
    root.operationKey = String(key || "")
    root.operationOutput = ""
    root.processToken = ++root.operationToken
    root.pending = true
    if (kind === "store") {
      operationProcess.command = ["bash", root.boundedHelperPath, "secret-tool", "store",
                                  "--label=Gorelo API key (Omarchy)", "service", "gorelo",
                                  "region", root.operationRegion]
      operationProcess.stdinEnabled = true
    } else if (kind === "clear") {
      operationProcess.command = ["bash", root.boundedHelperPath, "secret-tool", "clear",
                                  "service", "gorelo", "region", root.operationRegion]
      operationProcess.stdinEnabled = false
    } else {
      operationProcess.command = ["bash", root.boundedHelperPath, "secret-tool", "lookup",
                                  "service", "gorelo", "region", root.operationRegion]
      operationProcess.stdinEnabled = false
    }
    deadline.restart()
    operationProcess.running = true
    return true
  }

  function store(key, region) { return root.begin("store", region, key) }
  function clear(region) { return root.begin("clear", region, "") }
  function lookup(region) { return root.begin("lookup", region, "") }

  function finish(exitCode) {
    if (!root.pending || root.processToken !== root.operationToken) return
    deadline.stop()
    var kind = root.operation
    var region = root.operationRegion
    var key = root.operationKey
    var output = root.operationOutput
    root.pending = false
    root.operation = ""
    root.operationRegion = ""
    root.operationKey = ""
    root.operationOutput = ""
    root.processToken = 0
    if (kind === "store") {
      if (exitCode === 0) root.keyReady(key, region)
      else root.failed("Could not write the API key to the keyring.", region)
    } else if (kind === "clear") {
      if (exitCode === 0 || exitCode === 1) root.cleared(region)
      else root.failed("Could not remove the API key from the keyring.", region)
    } else {
      var truncated = exitCode === 90 || output.length >= root.maxLookupBytes
      var found = exitCode === 0 && !truncated ? output.split(/\r?\n/)[0].trim() : ""
      if (found) root.keyReady(found, region)
      else root.missing(region)
    }
  }

  property Timer deadline: Timer {
    interval: 60000
    onTriggered: {
      if (!root.pending) return
      var kind = root.operation
      var region = root.operationRegion
      root.operationToken++
      root.pending = false
      root.operation = ""
      root.operationRegion = ""
      root.operationKey = ""
      root.operationOutput = ""
      root.processToken = 0
      if (operationProcess.running) operationProcess.signal(15)
      killDeadline.restart()
      var verb = kind === "store" ? "storing" : (kind === "clear" ? "removing" : "reading")
      root.failed("Timed out while " + verb + " the API key.", region)
    }
  }
  property Timer killDeadline: Timer {
    interval: 2000
    onTriggered: if (operationProcess.running) operationProcess.signal(9)
  }

  property Process operationProcess: Process {
    command: []
    environment: ({ "GORELO_MAX_BYTES": String(root.maxLookupBytes) })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pending && root.processToken === root.operationToken) root.operationOutput = String(text || "")
      }
    }
    onStarted: {
      if (!root.pending || root.processToken !== root.operationToken) {
        operationProcess.signal(15)
        killDeadline.restart()
        return
      }
      if (root.operation === "store") {
        operationProcess.write(root.operationKey + "\n")
        operationProcess.stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      deadline.stop()
      killDeadline.stop()
      root.finish(exitCode)
      operationProcess.stdinEnabled = false
    }
  }
}
