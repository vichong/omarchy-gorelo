import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar button plus the ticket queue popup. Owns the keyboard cursor and the
// expanded row; the service owns tickets, reference data and the connection.
Panel {
  id: root
  moduleName: "io.github.vichong.gorelo"
  ipcTarget: "gorelo"
  // We own the target's single IpcHandler, so extra methods can sit
  // alongside the base open/close/toggle.
  manageIpc: false

  readonly property var gorelo: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool serviceReady: gorelo !== null
  readonly property string phase: serviceReady ? gorelo.phase : "idle"
  readonly property bool connected: phase === "connected"

  // Per-instance settings from the shell.json layout entry.
  readonly property bool colorful: setting("colorful", false) === true
  readonly property bool showCount: setting("showCount", true) !== false

  property string expandedTicketId: ""
  property string expandedDeviceId: ""
  property int cursorIndex: 0
  property bool cursorActive: false
  property string cursorTicketId: ""
  property string cursorDeviceId: ""
  property double lastSearchAcceptedAt: 0

  readonly property int rowCount: serviceReady ? gorelo.rows.count : 0
  readonly property int deviceRowCount: serviceReady ? gorelo.deviceRows.count : 0
  readonly property int totalRowCount: rowCount + deviceRowCount
  readonly property int rowsRevision: serviceReady ? gorelo.rowsRevision : 0
  readonly property string tab: serviceReady ? gorelo.activeTab : "mine"
  readonly property var counts: serviceReady ? gorelo.mineCounts : ({ total: 0, unread: 0, urgent: 0, waiting: 0 })
  readonly property var allCounts: serviceReady ? gorelo.allCounts : ({ total: 0, unread: 0, urgent: 0, waiting: 0 })

  onRowsRevisionChanged: restoreRowsState()

  onOpenedChanged: if (!opened) {
    if (serviceReady) gorelo.clearSearch()
    resetCursor(true)
  }

  onCursorActiveChanged: {
    if (cursorActive) rememberCursor()
    else {
      cursorTicketId = ""
      cursorDeviceId = ""
    }
  }

  function rememberCursor() {
    if (!cursorActive || !serviceReady || cursorIndex < 0 || cursorIndex >= totalRowCount) {
      cursorTicketId = ""
      cursorDeviceId = ""
      return
    }
    if (cursorIndex < rowCount) {
      cursorTicketId = String(gorelo.rows.get(cursorIndex).ticketId)
      cursorDeviceId = ""
    } else {
      cursorTicketId = ""
      cursorDeviceId = String(gorelo.deviceRows.get(cursorIndex - rowCount).deviceId)
    }
  }

  function selectCursorIndex(nextIndex) {
    cursorIndex = nextIndex
    rememberCursor()
  }

  function resetCursor(deactivate) {
    cursorIndex = 0
    cursorTicketId = ""
    cursorDeviceId = ""
    expandedTicketId = ""
    expandedDeviceId = ""
    if (deactivate === true) cursorActive = false
  }

  function restoreRowsState() {
    if (!serviceReady) return
    if (expandedTicketId && gorelo.indexOfTicket(expandedTicketId) === -1) expandedTicketId = ""
    if (expandedDeviceId && gorelo.indexOfDevice(expandedDeviceId) === -1) expandedDeviceId = ""

    var restored = -1
    if (cursorActive && cursorTicketId) restored = gorelo.indexOfTicket(cursorTicketId)
    else if (cursorActive && cursorDeviceId) {
      var deviceIndex = gorelo.indexOfDevice(cursorDeviceId)
      if (deviceIndex !== -1) restored = rowCount + deviceIndex
    }
    if (restored !== -1) cursorIndex = restored
    else cursorIndex = totalRowCount > 0 ? Math.max(0, Math.min(totalRowCount - 1, cursorIndex)) : 0
    rememberCursor()
  }

  function acceptSearch() {
    if (!serviceReady) return
    var now = Date.now()
    if (now - lastSearchAcceptedAt < 300) return
    lastSearchAcceptedAt = now
    gorelo.runSearch()
  }

  function moveCursor(delta) {
    if (totalRowCount === 0 || delta === 0) return
    selectCursorIndex(Math.max(0, Math.min(totalRowCount - 1, cursorIndex + delta)))
  }

  function switchTab(delta) {
    if (!serviceReady) return
    gorelo.setActiveTab(tab === "mine" ? "all" : "mine")
    resetCursor(false)
  }

  function currentRow() {
    if (cursorIndex < 0 || cursorIndex >= totalRowCount) return null
    if (cursorIndex < ticketRepeater.count) return ticketRepeater.itemAt(cursorIndex)
    return deviceRepeater.itemAt(cursorIndex - ticketRepeater.count)
  }

  function activateCursor() {
    var row = currentRow()
    if (row) row.activate()
  }



  // The overlay is a separate plugin surface, so it goes through the shell.
  // The popup closes first because the overlay takes exclusive keyboard focus.
  function openOverlay(tab) {
    if (!bar || !bar.shell || typeof bar.shell.summon !== "function") return
    close()
    bar.shell.summon(root.moduleName, JSON.stringify({ tab: tab || "new" }))
  }

  readonly property bool expandedInputOpen: {
    if (!root.expandedTicketId) return false
    for (var i = 0; i < ticketRepeater.count; i++) {
      var item = ticketRepeater.itemAt(i)
      if (item && item.ticketId === root.expandedTicketId) return item.inputOpen
    }
    return false
  }

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color hoverFill: Style.hoverFillFor(fg, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(fg, Color.accent)

  // The bar stays monochrome like the stock widgets: attention is carried by
  // weight (count) and the popup, never by colour. Disconnected dims.
  readonly property color iconColor: {
    var base = bar ? bar.barForeground : Color.foreground
    if (!root.connected) return Qt.darker(base, 1.5)
    return base
  }
  readonly property bool attention: root.connected && (root.counts.urgent > 0 || root.counts.unread > 0)

  readonly property string heroMeta: {
    if (!serviceReady) return "Service unavailable"
    if (!gorelo.configured) return "Not connected"
    switch (phase) {
    case "connected":
      if (gorelo.lastError) return "Retrying · " + gorelo.lastError
      return (gorelo.demoMode ? "Demo · " : "") + (gorelo.activitySummary || "Connected")
    case "connecting": return "Connecting…"
    case "error": return gorelo.transientError && gorelo.lastError
      ? "Retrying · " + gorelo.lastError : "Disconnected"
    default: return "Idle"
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "gorelo"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function status(): string {
      if (!root.serviceReady) return "service: UNREACHABLE"
      return root.gorelo.statusLine()
    }

    function refresh(): void {
      if (root.serviceReady) root.gorelo.refresh()
    }

    //   omarchy-shell gorelo newTicket   (bind to a key for a quick ticket)
    function newTicket(): void { root.openOverlay("new") }
    function settings(): void { root.openOverlay("settings") }

    // Open a ticket in the browser by id.
    function ticket(ticketId: string): string {
      if (!root.serviceReady) return "service unavailable"
      return root.gorelo.openTicket(ticketId) ? "ok" : "no url"
    }

    function tab(name: string): string {
      if (!root.serviceReady) return "service unavailable"
      root.gorelo.setActiveTab(name)
      return root.gorelo.activeTab
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.serviceReady && root.connected ? "Gorelo · " + root.gorelo.activitySummary : "Gorelo"
    fixedWidth: vertical ? -1 : content.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.openOverlay("new")
      else if (mouseButton === Qt.MiddleButton) { if (root.serviceReady) root.gorelo.refresh() }
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.spacing.sm

      Item {
        id: markSlot

        // A bar glyph is centred by its font line box, not its painted
        // pixels, so a vector mark centred geometrically sits low and reads
        // taller. Take the painted box of a reference bar glyph instead: the
        // mark then has the same height and baseline as the shell's icons.
        // glyphRef is laid out exactly like the shell's OpticalGlyph (centred
        // Text, native rendering), so its baseline is where a real icon's
        // baseline lands; tightBoundingRect is baseline-relative.
        readonly property rect glyphBox: glyphMetrics.tightBoundingRect
        readonly property real glyphTop: glyphRef.y + glyphRef.baselineOffset + glyphBox.y

        anchors.verticalCenter: parent.verticalCenter
        width: mark.width
        height: button.height

        Text {
          id: glyphRef

          anchors.centerIn: parent
          opacity: 0
          textFormat: Text.PlainText
          text: "󰖩"
          font.family: root.family
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
        }

        TextMetrics {
          id: glyphMetrics

          font: glyphRef.font
          text: glyphRef.text
        }

        GoreloIcon {
          id: mark

          x: 0
          y: markSlot.glyphTop
          iconSize: Math.max(1, markSlot.glyphBox.height)
          color: root.iconColor
          colorful: root.colorful
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        visible: !button.vertical && root.showCount && root.connected && root.counts.total > 0
        text: String(root.counts.total)
        color: root.iconColor
        font.family: root.family
        font.pixelSize: Style.font.body
        font.weight: root.attention ? Font.DemiBold : Font.Normal
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // An open status dropdown owns j/k, arrows, Enter and Escape.
      blocked: root.expandedInputOpen
      onCloseRequested: {
        if (searchField.activeFocus && searchField.text !== "") {
          root.gorelo.clearSearch()
          keyCatcher.forceActiveFocus()
        } else if (searchField.activeFocus) {
          keyCatcher.forceActiveFocus()
        } else {
          root.close()
        }
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.switchTab(dx)
      }
      onActivateRequested: {
        // The field handles its own Return (onAccepted); ignore it here so the
        // catcher never opens a ticket while the user is typing a search.
        if (searchField.activeFocus) return
        if (root.cursorActive) root.activateCursor()
      }
      // `/` focuses the search, as everywhere else.
      onTextKey: function(key) {
        if (key === "/" && searchField.visible && !searchField.activeFocus) searchField.forceActiveFocus()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        PanelHero {
          width: parent.width
          title: "Tickets"
          meta: root.heroMeta
          foreground: root.fg
          fontFamily: root.family
          iconOpacity: root.connected ? 1.0 : 0.55

          // The big mark carries the brand colours; the bar icon stays in the
          // theme foreground like its neighbours (shell.json `colorful` overrides).
          iconComponent: GoreloIcon {
            iconSize: Style.font.display
            color: root.phase === "error" ? Color.urgent : root.fg
            colorful: root.phase !== "error"
          }

          trailingControl: Component {
            Row {
              spacing: Style.spacing.xs

              PanelActionButton {
                iconText: "󰐕"                  // md-plus
                tooltipText: "New ticket"
                foreground: Qt.darker(root.fg, 1.4)
                fontFamily: root.family
                onClicked: root.openOverlay("new")
              }

              PanelActionButton {
                iconText: "󰑐"                  // md-refresh
                tooltipText: "Refresh"
                foreground: Qt.darker(root.fg, 1.4)
                fontFamily: root.family
                onClicked: if (root.serviceReady) root.gorelo.refresh()
              }

              PanelActionButton {
                iconText: "󰒓"                  // md-cog
                tooltipText: "Settings"
                foreground: Qt.darker(root.fg, 1.4)
                fontFamily: root.family
                onClicked: root.openOverlay("settings")
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        ButtonGroup {
          visible: root.connected && !root.gorelo.needsTechnician
          focusable: false
          foreground: root.fg
          fontFamily: root.family
          fontSize: Style.font.caption
          options: [
            { value: "mine", label: "Mine" + (root.counts.total ? " · " + root.counts.total : "") },
            { value: "all", label: "All open" + (root.tab === "all" && root.allCounts.total ? " · " + root.allCounts.total : "") }
          ]
          value: root.tab
          onChanged: function(value) {
            if (!root.serviceReady) return
            root.gorelo.setActiveTab(value)
            root.resetCursor(false)
          }
        }

        Item {
          width: parent.width
          height: implicitHeight
          implicitHeight: searchField.implicitHeight
          visible: root.connected && !root.gorelo.needsTechnician

          TextField {
            id: searchField
            anchors.fill: parent
            placeholderText: "Search tickets or devices…"
            foreground: root.fg
            font.family: root.family
            rightPadding: clearSearchButton.visible ? Style.space(36) : horizontalPadding
            onTextChanged: if (root.serviceReady) root.gorelo.setSearchQuery(text)
            onAccepted: root.acceptSearch()

            // Typing breaks a `text:` binding, so mirror the service's query by
            // hand: clearing (button, Escape, popup close) must empty the field.
            Connections {
              target: root.gorelo
              function onSearchQueryChanged() {
                if (root.gorelo && searchField.text !== root.gorelo.searchQuery) searchField.text = root.gorelo.searchQuery
              }
            }
          }

          PanelActionButton {
            id: clearSearchButton
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            visible: searchField.text !== ""
            iconText: "󰅖"                  // md-close
            tooltipText: "Clear search"
            foreground: root.dim
            fontFamily: root.family
            onClicked: root.gorelo.clearSearch()
          }
        }

        // ---------- not configured ----------
        Column {
          width: parent.width
          visible: !root.serviceReady || !root.gorelo.configured
          spacing: Style.spacing.xl

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: !root.serviceReady
              ? "The Gorelo service did not start."
              : "Add a Gorelo API key to see your ticket queue here."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            visible: root.serviceReady
            bordered: true
            text: "Open settings"
            foreground: root.fg
            fontFamily: root.family
            onClicked: root.openOverlay("settings")
          }
        }

        // ---------- configured, but not connected ----------
        Column {
          width: parent.width
          visible: root.serviceReady && root.gorelo.configured && !root.connected
          spacing: Style.spacing.xl

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: {
              if (root.phase === "connecting") return "Connecting to Gorelo…"
              var reason = root.gorelo.lastError || "Cannot reach Gorelo."
              return root.gorelo.lastErrorKind === "credential"
                ? reason + " Open settings to fix the API key."
                : reason
            }
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.spacing.lg

            Button {
              bordered: true
              text: "Settings"
              foreground: root.fg
              fontFamily: root.family
              onClicked: root.openOverlay("settings")
            }

            Button {
              visible: root.phase !== "connecting"
              bordered: true
              text: "Retry"
              foreground: root.fg
              fontFamily: root.family
              onClicked: root.gorelo.retryConnection()
            }
          }
        }

        // ---------- connected, but no technician picked ----------
        Column {
          width: parent.width
          visible: root.connected && root.gorelo.needsTechnician
          spacing: Style.spacing.xl

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Connected. Pick which technician you are so the queue shows your tickets."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            bordered: true
            text: "Choose technician"
            foreground: root.fg
            fontFamily: root.family
            onClicked: root.openOverlay("settings")
          }
        }

        // ---------- empty queue ----------
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && !root.gorelo.needsTechnician && root.gorelo.searching
          text: "Searching…"
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && root.gorelo.searchQuery.trim() !== ""
            && (root.gorelo.devicesLoading || root.gorelo.deviceSearching)
          text: root.gorelo.deviceSearching ? "Searching devices…" : "Loading devices…"
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && root.gorelo.searchQuery.trim() !== "" && root.gorelo.devicesError !== ""
          text: root.serviceReady ? root.gorelo.devicesError : ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && root.gorelo.searchQuery.trim() !== ""
            && root.gorelo.deviceSearchError !== ""
          text: root.serviceReady ? root.gorelo.deviceSearchError : ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && !root.gorelo.needsTechnician && root.gorelo.searchError !== ""
          text: root.serviceReady ? root.gorelo.searchError : ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        PanelSectionHeader {
          width: parent.width
          visible: root.connected && !root.gorelo.needsTechnician
            && root.gorelo.searchActive && !root.gorelo.searching && !root.gorelo.deviceSearching
            && root.gorelo.searchError === ""
          text: root.rowCount > 0 ? "SEARCH RESULTS · " + root.rowCount : "No tickets match"
          foreground: root.fg
          fontFamily: root.family
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && !root.gorelo.needsTechnician && root.rowCount === 0
            && root.deviceRowCount === 0 && !root.gorelo.devicesLoading
            && !root.gorelo.deviceSearching && !root.gorelo.searchActive && !root.gorelo.searching
          text: root.gorelo && root.gorelo.firstPollDone
            ? (root.gorelo.searchQuery.trim()
              ? "No tickets or devices match."
              : (root.tab === "mine" ? "Nothing assigned to you. Nice." : "No open tickets."))
            : "Loading tickets…"
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.serviceReady && root.gorelo.actionError !== ""
          text: root.serviceReady ? root.gorelo.actionError : ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.connected && !root.gorelo.searchActive && root.gorelo.truncated
          text: "Showing first 500 tickets. Narrow the status filter to see the rest."
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        // ---------- ticket list ----------
        ScrollView {
          id: listScroller
          visible: root.connected && root.totalRowCount > 0
          width: parent.width
          implicitHeight: Math.min(rowsColumn.implicitHeight, Style.space(480))
          clip: true
          ScrollBar.vertical.policy: ScrollBar.AsNeeded

          Column {
            id: rowsColumn
            width: listScroller.availableWidth
            spacing: Style.spacing.hairline

            Repeater {
              id: ticketRepeater
              model: root.serviceReady ? root.gorelo.rows : null
              delegate: TicketRow {
                // Required properties put the delegate in required-properties
                // mode, so `index` has to be asked for by name.
                required property int index

                width: rowsColumn.width
                gorelo: root.gorelo
                bar: root.bar
                fill: root.hoverFill
                currentFill: root.selectedFill
                showAssignee: root.tab === "all" || root.gorelo.searchActive
                hasCursor: root.cursorActive && root.cursorIndex === index
                expanded: root.expandedTicketId === ticketId
                onCursorRequested: {
                  root.cursorActive = true
                  root.selectCursorIndex(index)
                }
                onExpandToggled: {
                  root.expandedDeviceId = ""
                  root.expandedTicketId = root.expandedTicketId === ticketId ? "" : ticketId
                }
              }
            }


            PanelSectionHeader {
              width: parent.width
              visible: root.serviceReady && root.gorelo.searchQuery.trim() !== "" && root.deviceRowCount > 0
              text: "DEVICES · " + root.deviceRowCount
              foreground: root.fg
              fontFamily: root.family
            }

            Repeater {
              id: deviceRepeater
              model: root.serviceReady ? root.gorelo.deviceRows : null
              delegate: DeviceRow {
                required property int index

                width: rowsColumn.width
                gorelo: root.gorelo
                bar: root.bar
                fill: root.hoverFill
                currentFill: root.selectedFill
                hasCursor: root.cursorActive && root.cursorIndex === root.rowCount + index
                expanded: root.expandedDeviceId === deviceId
                onCursorRequested: {
                  root.cursorActive = true
                  root.selectCursorIndex(root.rowCount + index)
                }
                onExpandToggled: {
                  root.expandedTicketId = ""
                  root.expandedDeviceId = root.expandedDeviceId === deviceId ? "" : deviceId
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.serviceReady && root.gorelo.devicesTruncated && root.deviceRowCount > 0
              text: "Device cache is capped at 2,000; press Enter to search Gorelo directly."
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }

      }
    }
  }
}
