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

  function refreshBrowsers() {
    if (root.scanning) return
    root.scanning = true
    findProcess.running = true
  }
  function finishScan(browsers) {
    root.browsers = browsers
    root.scanning = false
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
    command: ["find", "/usr/share/applications", Quickshell.env("HOME") + "/.local/share/applications",
      "/var/lib/flatpak/exports/share/applications",
      Quickshell.env("HOME") + "/.local/share/flatpak/exports/share/applications",
      "-maxdepth", "1", "-name", "*.desktop", "-print0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "")
        if (output.length > 1024 * 1024) { root.finishScan([]); return }
        var paths = output.split("\0").filter(function(path) { return path !== "" })
        if (!paths.length) { root.finishScan([]); return }
        categoryProcess.command = ["grep", "-lsE", "^Categories=.*WebBrowser", "--"].concat(paths)
        categoryProcess.running = true
      }
    }
  }

  property Process categoryProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "")
        if (output.length > 1024 * 1024) { root.finishScan([]); return }
        var paths = output.split("\n").filter(function(path) { return path !== "" })
        if (!paths.length) { root.finishScan([]); return }
        nameProcess.command = ["grep", "-m1", "-H", "^Name=", "--"].concat(paths)
        nameProcess.running = true
      }
    }
  }

  property Process nameProcess: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "")
        if (output.length > 1024 * 1024) { root.finishScan([]); return }
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
  }
}
