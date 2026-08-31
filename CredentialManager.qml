import QtQuick
import Quickshell.Io

// Serialized system-keyring adapter for the Gorelo API key. The key travels to
// secret-tool over stdin, never in argv, and is scoped to the region it was
// entered for so switching regions never reuses a key silently.
QtObject {
  id: root

  readonly property bool busy: writePending || clearPending || lookupPending

  property bool writePending: false
  property bool writeStarted: false
  property string writeKey: ""
  property string writeRegion: ""

  property bool clearPending: false
  property bool clearStarted: false
  property string clearRegion: ""

  property bool lookupPending: false
  property bool lookupStarted: false
  property string lookupRegion: ""
  property string lookupKey: ""

  signal keyReady(string key, string region)
  signal missing(string region)
  signal cleared(string region)
  signal failed(string message, string region)

  function store(key, region) {
    if (root.busy || !key || !region) {
      root.failed("A keyring operation is already in progress.", region || "")
      return false
    }
    root.writeKey = String(key)
    root.writeRegion = String(region)
    root.writePending = true
    root.writeStarted = false
    storeProcess.command = [
      "secret-tool", "store", "--label=Gorelo API key (Omarchy)",
      "service", "gorelo", "region", root.writeRegion
    ]
    storeProcess.stdinEnabled = true
    storeProcess.running = true
    writeStartTimeout.restart()
    return true
  }

  function clear(region) {
    if (root.busy || !region) {
      root.failed("A keyring operation is already in progress.", region || "")
      return false
    }
    root.clearRegion = String(region)
    root.clearPending = true
    root.clearStarted = false
    clearProcess.command = ["secret-tool", "clear", "service", "gorelo", "region", root.clearRegion]
    clearProcess.running = true
    clearStartTimeout.restart()
    return true
  }

  function lookup(region) {
    if (root.busy || !region) return false
    root.lookupRegion = String(region)
    root.lookupKey = ""
    root.lookupPending = true
    root.lookupStarted = false
    lookupProcess.command = ["secret-tool", "lookup", "service", "gorelo", "region", root.lookupRegion]
    lookupProcess.running = true
    lookupStartTimeout.restart()
    return true
  }

  property Timer writeStartTimeout: Timer {
    interval: 5000
    onTriggered: {
      if (!root.writePending || root.writeStarted) return
      var region = root.writeRegion
      root.writeKey = ""
      root.writeRegion = ""
      root.writePending = false
      root.failed("Could not start secret-tool to store the API key.", region)
      if (storeProcess.running) storeProcess.signal(15)
    }
  }

  property Timer clearStartTimeout: Timer {
    interval: 5000
    onTriggered: {
      if (!root.clearPending || root.clearStarted) return
      var region = root.clearRegion
      root.clearRegion = ""
      root.clearPending = false
      root.failed("Could not start secret-tool to remove the API key.", region)
      if (clearProcess.running) clearProcess.signal(15)
    }
  }

  property Timer lookupStartTimeout: Timer {
    interval: 5000
    onTriggered: {
      if (!root.lookupPending || root.lookupStarted) return
      var region = root.lookupRegion
      root.lookupPending = false
      root.failed("Could not start secret-tool to read the API key.", region)
      if (lookupProcess.running) lookupProcess.signal(15)
    }
  }

  property Process storeProcess: Process {
    command: []
    stdinEnabled: true
    onStarted: {
      if (!root.writePending) {
        storeProcess.signal(15)
        return
      }
      root.writeStarted = true
      writeStartTimeout.stop()
      storeProcess.write(root.writeKey + "\n")
      storeProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (!root.writePending) return
      writeStartTimeout.stop()
      var key = root.writeKey
      var region = root.writeRegion
      root.writeKey = ""
      root.writeRegion = ""
      root.writePending = false
      root.writeStarted = false
      if (exitCode !== 0) {
        root.failed("Could not write the API key to the keyring.", region)
        return
      }
      root.keyReady(key, region)
    }
  }

  property Process clearProcess: Process {
    command: []
    onStarted: {
      if (!root.clearPending) {
        clearProcess.signal(15)
        return
      }
      root.clearStarted = true
      clearStartTimeout.stop()
    }
    onExited: function(exitCode) {
      if (!root.clearPending) return
      clearStartTimeout.stop()
      var region = root.clearRegion
      root.clearRegion = ""
      root.clearPending = false
      root.clearStarted = false
      // Exit 1 means no matching item; the desired state is already reached.
      if (exitCode !== 0 && exitCode !== 1) {
        root.failed("Could not remove the API key from the keyring.", region)
        return
      }
      root.cleared(region)
    }
  }

  property Process lookupProcess: Process {
    command: []
    stdout: SplitParser {
      onRead: function(value) {
        if (root.lookupPending && !root.lookupKey) root.lookupKey = String(value || "").trim()
      }
    }
    onStarted: {
      if (!root.lookupPending) {
        lookupProcess.signal(15)
        return
      }
      root.lookupStarted = true
      lookupStartTimeout.stop()
    }
    onExited: function(exitCode) {
      if (!root.lookupPending) return
      lookupStartTimeout.stop()
      var region = root.lookupRegion
      root.lookupPending = false
      root.lookupStarted = false
      var key = exitCode === 0 ? root.lookupKey : ""
      root.lookupKey = ""
      if (key) root.keyReady(key, region)
      else root.missing(region)
    }
  }
}
