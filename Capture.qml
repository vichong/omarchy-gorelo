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
  readonly property string attachmentHelperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/gorelo-attachment")).replace(/^file:\/\//, ""))

  function validAttachmentName(value) {
    var name = String(value || "")
    return /^screenshot-[A-Za-z0-9._-]+\.png$/.test(name) && name.indexOf("..") === -1
  }

  function nameFromCaptureHint(value) {
    var hint = String(value || "")
    var prefix = root.screenshotDir + "/"
    if (!root.screenshotDir || hint.indexOf(prefix) !== 0) return ""
    var name = hint.slice(prefix.length)
    return root.validAttachmentName(name) ? name : ""
  }

  function deleteAttachment(path) {
    var name = String(path || "")
    if (!root.screenshotDir) return
    var prefix = root.screenshotDir + "/"
    // Accept a full path only as a legacy hint, then discard everything but
    // the validated basename before invoking the descriptor-binding helper.
    if (name.indexOf(prefix) === 0) name = name.slice(prefix.length)
    if (!root.validAttachmentName(name)) return
    var queue = root.deleteQueue.slice()
    queue.push(name)
    root.deleteQueue = queue
    if (!cleanupProcess.running) root.startNextDelete()
  }

  function startNextDelete() {
    if (!root.deleteQueue.length || cleanupProcess.running) return
    cleanupProcess.command = ["bash", root.attachmentHelperPath, "delete", root.screenshotDir, root.deleteQueue[0]]
    cleanupDeadline.restart()
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
      cleanupDeadline.stop()
      cleanupKillDeadline.stop()
      var queue = root.deleteQueue.slice()
      if (queue.length) queue.shift()
      root.deleteQueue = queue
      root.startNextDelete()
    }
  }
  property Timer cleanupDeadline: Timer {
    interval: 10000
    onTriggered: {
      if (cleanupProcess.running) {
        cleanupProcess.signal(15)
        cleanupKillDeadline.restart()
      }
    }
  }
  property Timer cleanupKillDeadline: Timer {
    interval: 2000
    onTriggered: if (cleanupProcess.running) cleanupProcess.signal(9)
  }
  property Process captureDirProcess: Process {
    command: ["mkdir", "-m", "700", "-p", root.screenshotDir]
    onExited: function(exitCode) {
      if (!captureProcess.running) captureKillDeadline.stop()
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
      if (!captureDirProcess.running) captureKillDeadline.stop()
      if (!root.capturePending) {
        var lateName = root.nameFromCaptureHint(root.capturePath)
        if (lateName) root.deleteAttachment(lateName)
        root.capturePath = ""
        return
      }
      root.capturePending = false
      root.capturing = false
      captureDeadline.stop()
      var hint = exitCode === 0 ? root.capturePath : ""
      var name = root.nameFromCaptureHint(hint)
      root.capturePath = ""
      var current = root.captureRevision === root.draftRevision
      if (name && current && root.updateDraft) root.updateDraft({ attachmentPath: name })
      else if (name) root.deleteAttachment(name)
      else if (hint && current && root.reportError) root.reportError("The screenshot tool returned an unsafe attachment path.")
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
      if (captureDirProcess.running || captureProcess.running) captureKillDeadline.restart()
      root.fail("Screenshot capture timed out.")
    }
  }
  property Timer captureKillDeadline: Timer {
    interval: 2000
    onTriggered: {
      if (captureDirProcess.running) captureDirProcess.signal(9)
      if (captureProcess.running) captureProcess.signal(9)
    }
  }
  property Timer captureDelay: Timer {
    interval: 350
    onTriggered: if (root.capturePending) captureProcess.running = true
  }
}
