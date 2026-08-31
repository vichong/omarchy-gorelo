import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api
import "Model.js" as Model

// One ticket in the queue. Click or Enter opens it in the browser; the
// chevron unfolds status, assignment and a private-note field.
CursorSurface {
  id: row

  required property string ticketId
  required property string displayNumber
  required property string title
  required property string clientName
  required property int priorityId
  required property string priorityName
  required property int statusId
  required property string statusName
  required property bool isUnread
  required property bool waiting
  required property bool mine
  required property int assigneeId
  required property string assigneeName
  required property string age
  required property string lastSummary
  required property string url

  property var gorelo: null
  property QtObject bar: null
  property bool showAssignee: false
  property bool expanded: false

  signal expandToggled()
  signal cursorRequested()

  readonly property bool inputOpen: expansion.item !== null
    && (expansion.item.dropdownOpen || expansion.item.noteFocused)

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color faint: Qt.darker(fg, 1.8)
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent

  readonly property color priorityColor: {
    if (row.priorityId === 1) return row.urgentColor
    if (row.priorityId === 2) return Color.accent
    return row.dim
  }

  foreground: fg
  current: expanded
  implicitHeight: layout.implicitHeight + Style.spacing.rowPaddingX

  function activate() {
    if (gorelo) gorelo.openTicket(ticketId)
  }

  readonly property string subtitle: {
    var parts = []
    if (row.clientName) parts.push(row.clientName)
    if (row.statusName) parts.push(row.statusName)
    if (row.showAssignee && row.assigneeName) parts.push(row.assigneeName)
    if (row.waiting) parts.push("waiting on client")
    return parts.join(" · ")
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onContainsMouseChanged: if (containsMouse) row.cursorRequested()
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) row.expandToggled()
      else row.activate()
    }
  }

  PanelToolTip {
    visible: rowMouse.containsMouse && !row.expanded
    text: "Open " + row.displayNumber + " in browser · right-click for actions"
    fontFamily: row.family
  }

  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
    spacing: Style.spacing.xs

    // ---------- main line ----------
    Item {
      width: parent.width
      implicitHeight: Math.max(titleText.implicitHeight, priorityText.implicitHeight)
      height: implicitHeight

      Text {
        id: priorityText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        textFormat: Text.PlainText
        text: Model.priorityGlyph(row.priorityId)
        color: row.priorityColor
        font.family: row.family
        font.pixelSize: Style.font.caption
      }

      Text {
        id: numberText
        anchors.left: priorityText.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.displayNumber
        color: row.isUnread ? Color.accent : row.dim
        font.family: row.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: titleText
        anchors.left: numberText.right
        anchors.right: ageText.left
        anchors.leftMargin: Style.spacing.md
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.title
        elide: Text.ElideRight
        color: row.fg
        font.family: row.family
        font.pixelSize: Style.font.body
        font.weight: row.isUnread ? Font.DemiBold : Font.Normal
      }

      Text {
        id: ageText
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: chevron.visible ? Style.spacing.sm : 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.age
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: rowMouse.containsMouse || row.hasCursor || row.expanded
        iconText: row.expanded ? "󰅃" : "󰅀"   // md-chevron-up / down
        tooltipText: row.expanded ? "Collapse" : "Actions"
        foreground: row.dim
        fontFamily: row.family
        fontSize: Style.font.iconSmall
        onClicked: row.expandToggled()
      }
    }

    // ---------- detail line ----------
    Text {
      width: parent.width
      visible: row.subtitle !== ""
      textFormat: Text.PlainText
      text: row.subtitle
      elide: Text.ElideRight
      color: row.dim
      font.family: row.family
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      visible: row.expanded && row.lastSummary !== ""
      textFormat: Text.PlainText
      text: row.lastSummary
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
      color: row.faint
      font.family: row.family
      font.pixelSize: Style.font.caption
    }

    // ---------- actions ----------
    Loader {
      id: expansion
      width: parent.width
      active: row.expanded
      visible: active
      sourceComponent: actions
    }
  }

  Component {
    id: actions

    Column {
      id: actionsColumn
      spacing: Style.spacing.lg
      topPadding: Style.spacing.sm

      readonly property bool dropdownOpen: statusDropdown.popupOpen
      readonly property bool noteFocused: noteField.activeFocus

      // Declared first so the controls above keep their own clicks.
      MouseArea { anchors.fill: parent }

      Row {
        spacing: Style.spacing.lg

        Dropdown {
          id: statusDropdown
          showLabel: false
          fontFamily: row.family
          foreground: row.fg
          width: Style.space(170)
          options: row.gorelo ? row.gorelo.statuses.map(function(s) {
            return { value: String(s.Id), label: String(s.Name) }
          }) : []
          value: String(row.statusId)
          onChanged: function(value) {
            if (row.gorelo && value !== String(row.statusId)) row.gorelo.setStatus(row.ticketId, value)
          }
        }

        Button {
          visible: row.gorelo && !row.mine && row.gorelo.effectiveTechnicianId > 0
          bordered: true
          text: "Assign to me"
          foreground: row.fg
          fontFamily: row.family
          onClicked: if (row.gorelo) row.gorelo.assignToMe(row.ticketId)
        }

        Button {
          bordered: true
          text: "Open"
          foreground: row.fg
          fontFamily: row.family
          onClicked: row.activate()
        }
      }

      Row {
        spacing: Style.spacing.lg
        width: actionsColumn.width

        TextField {
          id: noteField
          width: parent.width - addNote.width - parent.spacing
          placeholderText: "Private note…"
          foreground: row.fg
          verticalPadding: Style.spacing.sm
          onAccepted: addNote.clicked()
          Keys.onEscapePressed: function(event) {
            noteField.focus = false
            event.accepted = true
          }
        }

        Button {
          id: addNote
          bordered: true
          text: "Add note"
          foreground: row.fg
          fontFamily: row.family
          opacity: noteField.text.trim().length > 0 ? 1.0 : 0.45
          onClicked: {
            if (!row.gorelo || !noteField.text.trim()) return
            var field = noteField
            row.gorelo.addPrivateNote(row.ticketId, noteField.text, function(ok) {
              if (ok && field) field.text = ""
            })
          }
        }
      }
    }
  }
}
