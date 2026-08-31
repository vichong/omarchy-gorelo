import QtQuick
import Quickshell
import Quickshell.Io

// Private screenshot capture and bounded attachment cleanup.
QtObject {
  id: root

  property int draftRevision: 0
  property var updateDraft: null
  property var reportError: null
  property var summon: null
  property bool capturing: false
  property int captureRevision: -1
  property bool capturePending: false
  property string capturePath: ""
  property var deleteQueue: []
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string screenshotDir: runtimeDir ? runtimeDir + "/gorelo" : ""

  function deleteAttachment(path) {
    var target = String(path || "")
    if (!root.screenshotDir) return
    var prefix = root.screenshotDir + "/"
    if (!target || target.indexOf(prefix) !== 0) return
    var basename = target.slice(prefix.length)
    if (!basename || basename.indexOf("/") !== -1 || basename.indexOf("..") !== -1
        || basename.indexOf("screenshot-") !== 0) return
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

  function fail(message) {
    root.capturePending = false
    root.capturing = false
    root.captureRevision = -1
    captureDeadline.stop()
    if (root.reportError) root.reportError(message)
    if (root.summon) root.summon()
  }

  function captureScreenshot() {
    if (root.capturing || root.capturePending || captureDirProcess.running || captureProcess.running) return false
    if (!root.screenshotDir) {
      if (root.reportError) root.reportError("No private runtime directory (XDG_RUNTIME_DIR) — screenshots disabled.")
      return false
    }
    root.capturing = true
    root.capturePending = true
    root.captureRevision = root.draftRevision
    root.capturePath = ""
    captureDeadline.restart()
    captureDirProcess.running = true
    return true
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
  property Process captureDirProcess: Process {
    command: ["mkdir", "-m", "700", "-p", root.screenshotDir]
    onExited: function(exitCode) {
      if (!root.capturePending) return
      if (exitCode === 0) captureDelay.restart()
      else root.fail("Could not create the private screenshot directory.")
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
      if (path && current && root.updateDraft) root.updateDraft({ attachmentPath: path })
      else if (path) root.deleteAttachment(path)
      root.captureRevision = -1
      if (current && root.summon) root.summon()
    }
  }
  property Timer captureDeadline: Timer {
    interval: 5 * 60 * 1000
    onTriggered: {
      captureDelay.stop()
      if (captureDirProcess.running) captureDirProcess.signal(15)
      if (captureProcess.running) captureProcess.signal(15)
      root.fail("Screenshot capture timed out.")
    }
  }
  property Timer captureDelay: Timer {
    interval: 350
    onTriggered: if (root.capturePending) captureProcess.running = true
  }
}
