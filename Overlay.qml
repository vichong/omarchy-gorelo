import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Api.js" as Api
import "Model.js" as Model
import "ConfigStore.js" as ConfigStore

// Quick ticket form and settings. Summoned by the shell, not by IPC — the bar
// widget owns the "gorelo" target:
//   omarchy-shell shell summon io.github.vichong.gorelo '{"tab":"new"}'
//   omarchy-shell shell summon io.github.vichong.gorelo '{"tab":"settings"}'
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string tab: "new"

  // Local until Connect, so a half-typed key never reaches the keyring.
  property string regionDraft: "usw"
  property string keyDraft: ""

  readonly property string family: Style.font.menuFamily
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color muted: Color.muted
  readonly property var borderSpec: Border.surfaceSpec(
    "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  readonly property bool connected: service && service.phase === "connected"

  function open(payloadJson) {
    root.opened = true
    root.resetDrafts()
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {}
      if (payload.tab === "new" || payload.tab === "settings") root.tab = payload.tab
    } catch (e) {
      // Not worth refusing to open over.
    }
    // A key is the first thing a fresh install needs.
    if (service && !service.configured) root.tab = "settings"
    if (service) service.refreshBrowsers()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.vichong.gorelo")
    }
  }

  function resetDrafts() {
    if (!service) return
    root.regionDraft = service.region
    // The stored key never comes back to screen; blank means "keep it".
    root.keyDraft = ""
  }

  function applyConnection() {
    if (!service) return
    if (service.applyConnection(root.regionDraft, root.keyDraft)) root.keyDraft = ""
  }

  Connections {
    target: root.service
    function onCreated(id, warning) {
      if (!warning) root.dismiss()
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "gorelo-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      readonly property int preferredWidth: Style.space(640)
      readonly property int preferredHeight: root.tab === "settings" ? Style.space(680) : Style.space(600)
      width: Math.min(card.preferredWidth, window.width - Style.gapsOut * 2)
      height: Math.min(card.preferredHeight, window.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        blocked: (newTabLoader.item && newTabLoader.item.popupOpen)
          || (settingsTabLoader.item && settingsTabLoader.item.popupOpen)
        onCloseRequested: root.dismiss()

        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          implicitHeight: Math.max(headingRow.implicitHeight, tabRow.implicitHeight)
          height: implicitHeight

          Row {
            id: headingRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            GoreloIcon {
              anchors.verticalCenter: parent.verticalCenter
              iconSize: Style.font.heading
              color: root.foreground
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.tab === "settings" ? "Gorelo settings" : "New Gorelo ticket"
              color: root.foreground
              font.family: root.family
              font.pixelSize: Style.font.title
              font.weight: Font.Medium
            }
          }

          ButtonGroup {
            id: tabRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            options: [{ value: "new", label: "New ticket" },
                      { value: "settings", label: "Settings" }]
            value: root.tab
            onChanged: function(value) { root.tab = value }
          }
        }

        PanelSeparator {
          id: rule
          anchors { top: header.bottom; left: parent.left; right: parent.right }
          anchors.topMargin: Style.space(12)
        }

        Item {
          id: body
          anchors {
            top: rule.bottom; bottom: parent.bottom
            left: parent.left; right: parent.right
          }
          anchors.topMargin: Style.space(14)

          Loader {
            id: newTabLoader
            anchors.fill: parent
            active: root.tab === "new"
            visible: active
            sourceComponent: newTicketTab
          }

          Loader {
            id: settingsTabLoader
            anchors.fill: parent
            active: root.tab === "settings"
            visible: active
            sourceComponent: settingsTab
          }
        }
      }
    }
  }

  // Shared bits ------------------------------------------------------------

  component FieldLabel: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.font.bodySmall
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component SectionTitle: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.Medium
  }

  // ------------------------------------------------------------ new ticket

  Component {
    id: newTicketTab

    Item {
      id: newPane

      readonly property var draft: root.service ? root.service.draft : Model.emptyDraft()
      readonly property bool popupOpen: clientPicker.popupOpen || priorityPicker.popupOpen
      readonly property string defaultsProblem: root.service
        ? Model.validateDraft({ title: "x", clientId: 1 }, root.service.createDefaults) : ""
      readonly property bool canCreate: root.service && root.connected && !root.service.creating
        && Model.validateDraft(newPane.draft, root.service.createDefaults) === ""

      readonly property string defaultsSummary: {
        if (!root.service || !root.connected) return ""
        var s = root.service
        var status = s.statusNames[String(s.effectiveDefaultStatusId)] || ""
        var group = s.groupNames[String(s.effectiveDefaultGroupId)] || ""
        var type = s.typeNames[String(s.effectiveDefaultTypeId)] || ""
        var parts = []
        if (group) parts.push("to " + group)
        if (status) parts.push("as " + status)
        if (type) parts.push("type " + type)
        if (s.effectiveTechnicianName) parts.push("assigned to " + s.effectiveTechnicianName)
        return parts.length ? "Goes " + parts.join(", ") + "." : ""
      }

      Flickable {
        id: newFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: newColumn.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: newColumn
          width: newFlick.width
          spacing: Style.spacing.xxl

          Caption {
            width: newColumn.width
            visible: !root.connected
            text: root.service && root.service.configured
              ? "Not connected to Gorelo yet — the ticket can be filled in, but not sent."
              : "Add an API key in Settings first."
          }

          Column {
            width: newColumn.width
            spacing: Style.spacing.sm

            FieldLabel { text: "Client" }

            SearchableDropdown {
              id: clientPicker
              popupMinHeight: Style.space(400)
              width: newColumn.width
              showLabel: false
              fontFamily: root.family
              foreground: root.foreground
              placeholderText: "Search clients…"
              emptyText: root.connected ? "No matching client" : "Clients load once connected"
              triggerLabel: "Pick a client"
              options: root.service ? root.service.clients.map(function(c) {
                return { value: String(c.Id), label: String(c.Name || c.Id) }
              }) : []
              value: newPane.draft.clientId ? String(newPane.draft.clientId) : ""
              onChanged: function(value) {
                if (root.service) root.service.updateDraft({ clientId: parseInt(value, 10) || 0 })
              }
            }
          }

          Column {
            width: newColumn.width
            spacing: Style.spacing.sm

            FieldLabel { text: "Title" }

            TextField {
              id: titleField
              width: newColumn.width
              text: newPane.draft.title
              placeholderText: "What's wrong?"
              foreground: root.foreground
              onTextChanged: if (root.service && text !== root.service.draft.title) root.service.updateDraft({ title: text })
            }
          }

          Row {
            width: newColumn.width
            spacing: Style.spacing.xl

            Column {
              spacing: Style.spacing.sm

              FieldLabel { text: "Priority" }

              Dropdown {
                id: priorityPicker
                width: Style.space(180)
                showLabel: false
                fontFamily: root.family
                foreground: root.foreground
                options: Api.PRIORITIES.map(function(p) { return { value: String(p.id), label: p.name } })
                value: String(newPane.draft.priorityId)
                onChanged: function(value) {
                  if (root.service) root.service.updateDraft({ priorityId: parseInt(value, 10) || 0 })
                }
              }
            }

            Column {
              spacing: Style.spacing.sm

              FieldLabel { text: "Screenshot" }

              Row {
                spacing: Style.spacing.lg

                Button {
                  visible: !newPane.draft.attachmentPath
                  bordered: true
                  text: "Add screenshot…"
                  foreground: root.foreground
                  fontFamily: root.family
                  // The overlay hides first so it is not in the shot; the
                  // service re-summons it with the path in the draft.
                  onClicked: {
                    if (!root.service) return
                    // Stay open if a previous capture is still winding down,
                    // otherwise nothing would bring the overlay back.
                    if (root.service.captureScreenshot()) root.dismiss()
                  }
                }

                Text {
                  visible: newPane.draft.attachmentPath !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Model.attachmentFileName(newPane.draft.attachmentPath)
                  elide: Text.ElideMiddle
                  width: Math.min(implicitWidth, Style.space(220))
                  color: root.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                }

                Button {
                  visible: newPane.draft.attachmentPath !== ""
                  bordered: true
                  text: "Remove"
                  foreground: root.foreground
                  fontFamily: root.family
                  onClicked: if (root.service) root.service.updateDraft({ attachmentPath: "" })
                }
              }
            }
          }

          Column {
            width: newColumn.width
            spacing: Style.spacing.sm

            FieldLabel { text: "Description" }

            // Ui has no multi-line field; this mirrors Ui/TextField's chrome.
            BorderSurface {
              id: descriptionSurface
              width: newColumn.width
              height: Style.space(140)
              radius: Style.cornerRadius
              readonly property bool hot: descriptionArea.hovered
              color: Style.controlFill(descriptionArea.activeFocus, hot, root.foreground, Color.accent)
              borderSpec: Border.controlSpec(descriptionArea.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
                                             root.foreground, Color.accent)

              ScrollView {
                anchors.fill: parent
                anchors.margins: Style.spacing.xs
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                  id: descriptionArea
                  text: newPane.draft.description
                  placeholderText: "Steps, error text, what was expected…"
                  wrapMode: TextEdit.Wrap
                  color: root.foreground
                  placeholderTextColor: Qt.darker(root.foreground, 1.6)
                  selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                  selectedTextColor: root.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  leftPadding: Style.spacing.controlPaddingX
                  rightPadding: Style.spacing.controlPaddingX
                  topPadding: Style.spacing.inputPaddingY
                  bottomPadding: Style.spacing.inputPaddingY
                  background: null
                  onTextChanged: if (root.service && text !== root.service.draft.description) root.service.updateDraft({ description: text })
                }
              }
            }
          }

          Caption {
            width: newColumn.width
            visible: newPane.defaultsSummary !== ""
            text: newPane.defaultsSummary
          }

          Row {
            visible: root.connected && newPane.defaultsProblem !== ""
            spacing: Style.spacing.lg

            Caption {
              anchors.verticalCenter: parent.verticalCenter
              text: newPane.defaultsProblem
              color: Color.urgent
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              bordered: true
              text: "Set defaults"
              foreground: root.foreground
              fontFamily: root.family
              onClicked: root.tab = "settings"
            }
          }

          Caption {
            width: newColumn.width
            visible: root.service && root.service.createError !== ""
            text: root.service ? root.service.createError : ""
            color: Color.urgent
          }

          Row {
            spacing: Style.spacing.xl

            Button {
              bordered: true
              text: root.service && root.service.creating ? "Creating…" : "Create ticket"
              opacity: newPane.canCreate ? 1.0 : 0.45
              foreground: root.foreground
              fontFamily: root.family
              onClicked: if (newPane.canCreate) root.service.createTicket()
            }

            Button {
              bordered: true
              text: "Discard"
              foreground: root.foreground
              fontFamily: root.family
              onClicked: {
                if (root.service) root.service.clearDraft()
                root.dismiss()
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ settings

  Component {
    id: settingsTab

    Item {
      id: settingsPane

      readonly property bool popupOpen: technicianPicker.popupOpen || statusPicker.popupOpen
        || groupPicker.popupOpen || typePicker.popupOpen || shownStatuses.popupOpen
        || notifyLevel.popupOpen || browserPicker.popupOpen
      readonly property bool keyringBusy: root.service && root.service.credentialBusy
      readonly property bool regionChanged: root.service && root.regionDraft !== root.service.region
      readonly property bool needsKey: !root.service || !root.service.hasKey || settingsPane.regionChanged
      readonly property bool canConnect: !settingsPane.keyringBusy
        && root.service && !root.service.demoMode
        && (root.keyDraft.trim().length > 0 || (!settingsPane.needsKey && !root.connected))

      readonly property string connectionStatus: {
        if (!root.service) return "Service unavailable"
        if (root.service.demoMode) {
          return root.service.phase === "connected" ? "Demo connected" : "Starting demo…"
        }
        switch (root.service.phase) {
        case "connected": return "Connected to " + Api.regionLabel(root.service.region)
          + (root.service.lastError ? " · " + root.service.lastError : "")
        case "connecting": return "Connecting…"
        case "error": return root.service.lastError || "Error"
        default: return root.service.hasKey ? "Idle" : "No API key stored for " + Api.regionLabel(root.regionDraft)
        }
      }

      function saveInt(key, value) {
        if (!root.service) return
        if (root.service.demoMode
            && (key === "defaultStatusId" || key === "defaultGroupId" || key === "defaultTypeId")) return
        var patch = {}
        patch[key] = parseInt(value, 10) || 0
        root.service.saveConfig(patch)
      }

      Flickable {
        id: settingsFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: settingsColumn.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: settingsColumn
          width: settingsFlick.width
          spacing: Style.spacing.xxxl

          // ---- connection
          Column {
            width: settingsColumn.width
            spacing: Style.spacing.lg

            SectionTitle { text: "Connection" }

            Column {
              spacing: Style.spacing.sm

              FieldLabel { text: "Region" }

              ButtonGroup {
                foreground: root.foreground
                fontFamily: root.family
                fontSize: Style.font.bodySmall
                options: Api.REGIONS.map(function(r) { return { value: r.id, label: r.label } })
                value: root.regionDraft
                onChanged: function(value) { root.regionDraft = value }
              }

              Caption {
                width: settingsColumn.width
                text: "The region you picked when your Gorelo tenancy was created. Keys are stored per region."
              }
            }

            Column {
              width: settingsColumn.width
              spacing: Style.spacing.sm

              FieldLabel {
                text: settingsPane.needsKey ? "API key" : "API key · leave blank to keep the stored one"
              }

              TextField {
                width: settingsColumn.width
                text: root.keyDraft
                password: true
                placeholderText: "Paste from Gorelo → Settings → Integrations → API keys"
                foreground: root.foreground
                onTextChanged: root.keyDraft = text
                onAccepted: if (settingsPane.canConnect) root.applyConnection()
              }

              Caption {
                width: settingsColumn.width
                text: "Give the key read/write on tickets and read on clients, organization and assets. It is kept in the system keyring, never in a config file."
              }
            }

            Row {
              spacing: Style.spacing.xl

              Button {
                bordered: true
                text: "Connect"
                opacity: settingsPane.canConnect ? 1.0 : 0.45
                foreground: root.foreground
                fontFamily: root.family
                onClicked: if (settingsPane.canConnect) root.applyConnection()
              }

              Button {
                visible: root.service && root.service.hasKey && !root.service.demoMode
                  && !settingsPane.regionChanged
                bordered: true
                text: "Remove key"
                opacity: settingsPane.keyringBusy ? 0.45 : 1.0
                foreground: root.foreground
                fontFamily: root.family
                onClicked: {
                  if (!root.service || settingsPane.keyringBusy) return
                  root.service.removeConnection()
                  root.resetDrafts()
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: settingsPane.connectionStatus
                color: root.service && root.service.phase === "error" ? Color.urgent : root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }

            Toggle {
              width: settingsColumn.width
              label: "Demo mode"
              description: "A fake MSP, so you can try the widget without a Gorelo tenancy."
              checked: root.service ? root.service.demoMode : false
              foreground: root.foreground
              fontFamily: root.family
              onClicked: if (root.service) root.service.setDemoMode(!root.service.demoMode)
            }
          }

          PanelSeparator { width: settingsColumn.width }

          // ---- who am I
          Column {
            width: settingsColumn.width
            spacing: Style.spacing.lg

            SectionTitle { text: "You" }

            Column {
              width: settingsColumn.width
              spacing: Style.spacing.sm

              FieldLabel { text: "Technician" }

              SearchableDropdown {
                id: technicianPicker
                popupMinHeight: Style.space(400)
                width: settingsColumn.width
                showLabel: false
                fontFamily: root.family
                foreground: root.foreground
                placeholderText: "Search technicians…"
                emptyText: root.connected ? "No matching technician" : "Connect first"
                triggerLabel: "Pick yourself"
                options: root.service ? root.service.users.map(function(u) {
                  return { value: String(u.Id), label: Api.userDisplayName(u), description: String(u.Email || "") }
                }) : []
                value: root.service && root.service.effectiveTechnicianId
                  ? String(root.service.effectiveTechnicianId) : ""
                onChanged: function(value) {
                  if (!root.service || root.service.demoMode) return
                  var id = parseInt(value, 10) || 0
                  root.service.saveConfig({ technicianId: id, technicianName: root.service.userNames[String(id)] || "" })
                }
              }

              Caption {
                width: settingsColumn.width
                text: "The API key is organisation-wide, so the queue needs to know whose tickets to show. Notes and status changes are recorded as API updates with your name."
              }
            }
          }

          PanelSeparator { width: settingsColumn.width }

          // ---- defaults for quick tickets
          Column {
            width: settingsColumn.width
            spacing: Style.spacing.lg

            SectionTitle { text: "New ticket defaults" }

            Caption {
              width: settingsColumn.width
              text: "Gorelo requires a status, group and type on every ticket. Quick tickets use these."
            }

            Row {
              spacing: Style.spacing.xl

              Dropdown {
                id: statusPicker
                label: "Status"
                width: Style.space(180)
                fontFamily: root.family
                foreground: root.foreground
                options: root.service ? root.service.statuses.map(function(s) { return { value: String(s.Id), label: String(s.Name) } }) : []
                value: root.service && root.service.effectiveDefaultStatusId
                  ? String(root.service.effectiveDefaultStatusId) : ""
                onChanged: function(value) { settingsPane.saveInt("defaultStatusId", value) }
              }

              Dropdown {
                id: groupPicker
                label: "Group"
                width: Style.space(180)
                fontFamily: root.family
                foreground: root.foreground
                options: root.service ? root.service.groups.map(function(g) { return { value: String(g.Id), label: String(g.Name) } }) : []
                value: root.service && root.service.effectiveDefaultGroupId
                  ? String(root.service.effectiveDefaultGroupId) : ""
                onChanged: function(value) { settingsPane.saveInt("defaultGroupId", value) }
              }

              Dropdown {
                id: typePicker
                label: "Type"
                width: Style.space(180)
                fontFamily: root.family
                foreground: root.foreground
                options: root.service ? root.service.types.map(function(t) { return { value: String(t.Id), label: String(t.Name) } }) : []
                value: root.service && root.service.effectiveDefaultTypeId
                  ? String(root.service.effectiveDefaultTypeId) : ""
                onChanged: function(value) { settingsPane.saveInt("defaultTypeId", value) }
              }
            }

            Toggle {
              width: settingsColumn.width
              label: "Open the ticket after creating it"
              description: "Launches the browser on the new ticket."
              checked: root.service ? root.service.openAfterCreate : true
              foreground: root.foreground
              fontFamily: root.family
              onClicked: if (root.service) root.service.saveConfig({ openAfterCreate: !root.service.openAfterCreate })
            }
          }

          PanelSeparator { width: settingsColumn.width }

          // ---- queue
          Column {
            width: settingsColumn.width
            spacing: Style.spacing.lg

            SectionTitle { text: "Queue" }

            MultiSelect {
              id: shownStatuses
              label: "Statuses shown"
              width: settingsColumn.width
              fontFamily: root.family
              foreground: root.foreground
              options: root.service ? root.service.statuses.map(function(s) { return { value: String(s.Id), label: String(s.Name) } }) : []
              values: root.service ? root.service.effectiveStatusIds.map(String) : []
              onChanged: function(values) {
                if (!root.service || root.service.demoMode) return
                var ids = []
                for (var i = 0; i < values.length; i++) {
                  var n = parseInt(values[i], 10)
                  if (!isNaN(n)) ids.push(n)
                }
                root.service.saveConfig({ statusIds: ids })
              }
            }

            Caption {
              width: settingsColumn.width
              text: "Defaults to every status that doesn't look closed, resolved or cancelled."
            }

            NumberField {
              label: "Poll every (seconds)"
              from: ConfigStore.POLL_MIN
              to: ConfigStore.POLL_MAX
              stepSize: 30
              value: root.service ? root.service.pollSeconds : ConfigStore.POLL_DEFAULT
              foreground: root.foreground
              fontFamily: root.family
              onModified: function(value) { if (root.service) root.service.saveConfig({ pollSeconds: value }) }
            }
          }

          PanelSeparator { width: settingsColumn.width }

          // ---- notifications
          Column {
            width: settingsColumn.width
            spacing: Style.spacing.lg

            SectionTitle { text: "Notifications" }

            Toggle {
              width: settingsColumn.width
              label: "Desktop notifications"
              description: "When a ticket is assigned to you or one of yours gets an unread update. Click a notification to open the ticket."
              checked: root.service ? root.service.notify : true
              foreground: root.foreground
              fontFamily: root.family
              onClicked: if (root.service) root.service.saveConfig({ notify: !root.service.notify })
            }

            Dropdown {
              id: notifyLevel
              label: "Notify for"
              width: Style.space(260)
              fontFamily: root.family
              foreground: root.foreground
              options: [
                { value: "1", label: "Urgent only" },
                { value: "2", label: "Urgent and High" },
                { value: "3", label: "Normal and above" },
                { value: "4", label: "Low and above" },
                { value: "5", label: "Everything" }
              ]
              value: root.service ? String(root.service.notifyMinPriority) : "3"
              onChanged: function(value) { settingsPane.saveInt("notifyMinPriority", value) }
            }
          }

          PanelSeparator { width: settingsColumn.width }

          // ---- links
          Column {
            width: settingsColumn.width
            spacing: Style.spacing.lg

            SectionTitle { text: "Links" }

            Dropdown {
              id: browserPicker
              label: "Open Gorelo links with"
              width: Style.space(320)
              fontFamily: root.family
              foreground: root.foreground
              options: [{ value: "", label: "System default browser" }].concat(
                root.service ? root.service.browsers.map(function(b) { return { value: b.path, label: b.name } }) : [])
              value: root.service ? root.service.browserDesktop : ""
              onChanged: function(value) { if (root.service) root.service.saveConfig({ browserDesktop: value }) }
            }

            Caption {
              width: settingsColumn.width
              text: "Browsers found in the applications menu. Also used for device links, notification clicks and newly created tickets."
            }

            Caption {
              width: settingsColumn.width
              visible: root.service && root.service.browserWarning !== ""
              text: root.service ? root.service.browserWarning : ""
              color: Color.urgent
            }

            Column {
              width: settingsColumn.width
              spacing: Style.spacing.sm

              FieldLabel { text: "Ticket URL" }

              TextField {
                id: urlField
                width: settingsColumn.width
                text: root.service ? root.service.ticketUrlTemplate : ""
                foreground: root.foreground
                onEditingFinished: if (root.service && text.trim() !== root.service.ticketUrlTemplate) root.service.saveConfig({ ticketUrlTemplate: text.trim() })
              }

              Caption {
                width: settingsColumn.width
                text: "{id}, {number} and {displayNumber} are filled in. Change this if your Gorelo web app uses a different ticket path."
              }
            }

            Column {
              width: settingsColumn.width
              spacing: Style.spacing.sm

              FieldLabel { text: "Device URL" }

              TextField {
                id: deviceUrlField
                width: settingsColumn.width
                text: root.service ? root.service.deviceUrlTemplate : ""
                foreground: root.foreground
                onEditingFinished: if (root.service && text.trim() !== root.service.deviceUrlTemplate) root.service.saveConfig({ deviceUrlTemplate: text.trim() })
              }

              Caption {
                width: settingsColumn.width
                text: "{id} and {name} are filled in; {name} is the URL-encoded computer name."
              }
            }
          }
        }
      }
    }
  }
}
