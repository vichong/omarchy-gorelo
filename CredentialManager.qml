import QtQuick
import Quickshell.Io

// Serialized system-keyring adapter for the Gorelo API key. The key travels to
// secret-tool over stdin, never in argv, and is scoped to the region it was
// entered for so switching regions never reuses a key silently.
QtObject {
  id: root

  readonly property bool busy: writePending || clearPending || lookupPending
    || storeProcess.running || clearProcess.running || lookupProcess.running

  property int operationToken: 0

  property bool writePending: false
  property bool writeStarted: false
  property string writeKey: ""
  property string writeRegion: ""
  property int writeToken: 0
  property int writeProcessToken: 0

  property bool clearPending: false
  property bool clearStarted: false
  property string clearRegion: ""
  property int clearToken: 0
  property int clearProcessToken: 0

  property bool lookupPending: false
  property bool lookupStarted: false
  property string lookupRegion: ""
  property string lookupKey: ""
  property int lookupToken: 0
  property int lookupProcessToken: 0

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
    root.writeToken = ++root.operationToken
    root.writeProcessToken = root.writeToken
    root.writePending = true
    root.writeStarted = false
    storeProcess.command = [
      "secret-tool", "store", "--label=Gorelo API key (Omarchy)",
      "service", "gorelo", "region", root.writeRegion
    ]
    storeProcess.stdinEnabled = true
    writeDeadline.restart()
    storeProcess.running = true
    return true
  }

  function clear(region) {
    if (root.busy || !region) {
      root.failed("A keyring operation is already in progress.", region || "")
      return false
    }
    root.clearRegion = String(region)
    root.clearToken = ++root.operationToken
    root.clearProcessToken = root.clearToken
    root.clearPending = true
    root.clearStarted = false
    clearProcess.command = ["secret-tool", "clear", "service", "gorelo", "region", root.clearRegion]
    clearDeadline.restart()
    clearProcess.running = true
    return true
  }

  function lookup(region) {
    if (root.busy || !region) return false
    root.lookupRegion = String(region)
    root.lookupKey = ""
    root.lookupToken = ++root.operationToken
    root.lookupProcessToken = root.lookupToken
    root.lookupPending = true
    root.lookupStarted = false
    lookupProcess.command = ["secret-tool", "lookup", "service", "gorelo", "region", root.lookupRegion]
    lookupDeadline.restart()
    lookupProcess.running = true
    return true
  }

  property Timer writeDeadline: Timer {
    interval: 60000
    onTriggered: {
      if (!root.writePending) return
      var region = root.writeRegion
      root.writeToken = ++root.operationToken
      root.writeKey = ""
      root.writeRegion = ""
      root.writePending = false
      root.writeStarted = false
      if (storeProcess.running) storeProcess.signal(15)
      root.failed("Timed out while storing the API key.", region)
    }
  }

  property Timer clearDeadline: Timer {
    interval: 60000
    onTriggered: {
      if (!root.clearPending) return
      var region = root.clearRegion
      root.clearToken = ++root.operationToken
      root.clearRegion = ""
      root.clearPending = false
      root.clearStarted = false
      if (clearProcess.running) clearProcess.signal(15)
      root.failed("Timed out while removing the API key.", region)
    }
  }

  property Timer lookupDeadline: Timer {
    interval: 60000
    onTriggered: {
      if (!root.lookupPending) return
      var region = root.lookupRegion
      root.lookupToken = ++root.operationToken
      root.lookupRegion = ""
      root.lookupKey = ""
      root.lookupPending = false
      root.lookupStarted = false
      if (lookupProcess.running) lookupProcess.signal(15)
      root.failed("Timed out while reading the API key.", region)
    }
  }

  property Process storeProcess: Process {
    command: []
    stdinEnabled: true
    onStarted: {
      if (!root.writePending || root.writeProcessToken !== root.writeToken) {
        storeProcess.signal(15)
        return
      }
      root.writeStarted = true
      storeProcess.write(root.writeKey + "\n")
      storeProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (!root.writePending || root.writeProcessToken !== root.writeToken) return
      writeDeadline.stop()
      var key = root.writeKey
      var region = root.writeRegion
      root.writeKey = ""
      root.writeRegion = ""
      root.writePending = false
      root.writeStarted = false
      root.writeProcessToken = 0
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
      if (!root.clearPending || root.clearProcessToken !== root.clearToken) {
        clearProcess.signal(15)
        return
      }
      root.clearStarted = true
    }
    onExited: function(exitCode) {
      if (!root.clearPending || root.clearProcessToken !== root.clearToken) return
      clearDeadline.stop()
      var region = root.clearRegion
      root.clearRegion = ""
      root.clearPending = false
      root.clearStarted = false
      root.clearProcessToken = 0
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
      if (!root.lookupPending || root.lookupProcessToken !== root.lookupToken) {
        lookupProcess.signal(15)
        return
      }
      root.lookupStarted = true
    }
    onExited: function(exitCode) {
      if (!root.lookupPending || root.lookupProcessToken !== root.lookupToken) return
      lookupDeadline.stop()
      var region = root.lookupRegion
      root.lookupPending = false
      root.lookupStarted = false
      root.lookupProcessToken = 0
      var key = exitCode === 0 ? root.lookupKey : ""
      root.lookupKey = ""
      root.lookupRegion = ""
      if (key) root.keyReady(key, region)
      else root.missing(region)
    }
  }
}
