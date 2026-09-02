import QtQuick
import Quickshell
import Quickshell.Io

// Browser discovery and argv-safe URL launching.
QtObject {
  id: root
  property string browserDesktop: ""
  property var browsers: []
  property string browserWarning: ""
  property bool scanning: false
  property int scanToken: 0
  property int findToken: 0
  property int categoryToken: 0
  property int nameToken: 0
  property string findOutput: ""
  property string categoryOutput: ""
  property string nameOutput: ""
  property string activeStage: ""
  readonly property int maxOutputBytes: 1024 * 1024
  readonly property string boundedHelperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/gorelo-bounded")).replace(/^file:\/\//, ""))

  function refreshBrowsers() {
    if (root.scanning || findProcess.running || categoryProcess.running || nameProcess.running) return
    var token = ++root.scanToken
    root.scanning = true
    root.findOutput = ""
    root.categoryOutput = ""
    root.nameOutput = ""
    root.findToken = token
    root.startStage("find", findProcess, ["find", "/usr/share/applications", Quickshell.env("HOME") + "/.local/share/applications",
      "/var/lib/flatpak/exports/share/applications",
      Quickshell.env("HOME") + "/.local/share/flatpak/exports/share/applications",
      "-maxdepth", "1", "-name", "*.desktop", "-print0"])
  }
  function finishScan(browsers) {
    scanDeadline.stop()
    root.activeStage = ""
    root.browsers = browsers
    root.scanning = false
  }
  function startStage(stage, process, command) {
    root.activeStage = stage
    process.command = ["bash", root.boundedHelperPath].concat(command)
    scanDeadline.restart()
    process.running = true
  }
  function stageExited(stage) {
    if (root.activeStage === stage) {
      scanDeadline.stop()
      root.activeStage = ""
    }
    if (!findProcess.running && !categoryProcess.running && !nameProcess.running) scanKillDeadline.stop()
  }
  function truncated(output, exitCode) {
    return exitCode === 90 || String(output || "").length >= root.maxOutputBytes
  }
  function availableDesktop() {
    if (!root.browserDesktop) { root.browserWarning = ""; return "" }
    for (var i = 0; i < root.browsers.length; i++) {
      if (root.browsers[i].path === root.browserDesktop) { root.browserWarning = ""; return root.browserDesktop }
    }
    root.browserWarning = "The selected browser is no longer available; using the system default."
    return ""
  }
  function openUrlCommand(url) {
    var desktop = root.availableDesktop()
    return desktop ? ["gio", "launch", desktop, url] : ["xdg-open", url]
  }
  function openUrl(url) {
    if (!url) return false
    var desktop = root.availableDesktop()
    if (desktop) Quickshell.execDetached(["gio", "launch", desktop, url])
    else Qt.openUrlExternally(url)
    return true
  }

  property Process findProcess: Process {
    command: []
    environment: ({ "GORELO_MAX_BYTES": String(root.maxOutputBytes) })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.scanning && root.findToken === root.scanToken) root.findOutput = String(text || "")
    }
    onExited: function(exitCode) {
      var token = root.findToken
      var output = root.findOutput
      root.findOutput = ""
      root.stageExited("find")
      if (!root.scanning || token !== root.scanToken) return
      if (root.truncated(output, exitCode) || (exitCode !== 0 && exitCode !== 1)) { root.finishScan([]); return }
      var paths = output.split("\0").filter(function(path) { return path !== "" })
      if (!paths.length) { root.finishScan([]); return }
      root.categoryToken = token
      root.startStage("category", categoryProcess, ["grep", "-lsE", "^Categories=.*WebBrowser", "--"].concat(paths))
    }
  }

  property Process categoryProcess: Process {
    command: []
    environment: ({ "GORELO_MAX_BYTES": String(root.maxOutputBytes) })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.scanning && root.categoryToken === root.scanToken) root.categoryOutput = String(text || "")
    }
    onExited: function(exitCode) {
      var token = root.categoryToken
      var output = root.categoryOutput
      root.categoryOutput = ""
      root.stageExited("category")
      if (!root.scanning || token !== root.scanToken) return
      if (root.truncated(output, exitCode) || (exitCode !== 0 && exitCode !== 1)) { root.finishScan([]); return }
      var paths = output.split("\n").filter(function(path) { return path !== "" })
      if (!paths.length) { root.finishScan([]); return }
      root.nameToken = token
      root.startStage("name", nameProcess, ["grep", "-m1", "-H", "^Name=", "--"].concat(paths))
    }
  }

  property Process nameProcess: Process {
    command: []
    environment: ({ "GORELO_MAX_BYTES": String(root.maxOutputBytes) })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.scanning && root.nameToken === root.scanToken) root.nameOutput = String(text || "")
    }
    onExited: function(exitCode) {
      var token = root.nameToken
      var output = root.nameOutput
      root.nameOutput = ""
      root.stageExited("name")
      if (!root.scanning || token !== root.scanToken) return
      if (root.truncated(output, exitCode) || (exitCode !== 0 && exitCode !== 1)) { root.finishScan([]); return }
      var lines = output.split("\n")
      var seen = Object.create(null)
      var out = []
      for (var i = 0; i < lines.length; i++) {
        var separator = lines[i].indexOf(":")
        if (separator < 0) continue
        var path = lines[i].substring(0, separator).trim()
        var value = lines[i].substring(separator + 1)
        if (value.indexOf("Name=") !== 0) continue
        var name = value.substring(5).trim()
        if (!path || !name || seen[name]) continue
        seen[name] = true
        out.push({ path: path, name: name })
      }
      out.sort(function(a, b) { return a.name.localeCompare(b.name) })
      root.finishScan(out)
    }
  }

  property Timer scanDeadline: Timer {
    interval: 15000
    onTriggered: {
      if (!root.scanning) return
      root.scanToken++
      root.findOutput = ""
      root.categoryOutput = ""
      root.nameOutput = ""
      root.finishScan([])
      if (findProcess.running) findProcess.signal(15)
      if (categoryProcess.running) categoryProcess.signal(15)
      if (nameProcess.running) nameProcess.signal(15)
      scanKillDeadline.restart()
    }
  }
  property Timer scanKillDeadline: Timer {
    interval: 2000
    onTriggered: {
      if (findProcess.running) findProcess.signal(9)
      if (categoryProcess.running) categoryProcess.signal(9)
      if (nameProcess.running) nameProcess.signal(9)
    }
  }
}
