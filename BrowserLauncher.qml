import QtQuick
import Quickshell
import Quickshell.Io

// Browser discovery and argv-safe URL launching.
QtObject {
  id: root
  property string browserDesktop: ""
  property var browsers: []
  property string browserWarning: ""

  function refreshBrowsers() { if (!scanProcess.running) scanProcess.running = true }
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

  property Process scanProcess: Process {
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
}
