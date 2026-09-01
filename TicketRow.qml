pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api
import "Model.js" as Model

// One ticket in the queue.
ListRow {
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

  property bool showAssignee: false
  readonly property bool inputOpen: expansionItem !== null
    && (expansionItem.dropdownOpen || expansionItem.noteFocused)
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property color priorityColor: priorityId === 1 ? urgentColor
    : (priorityId === 2 ? Color.accent : dim)

  // Reference status for this ticket (colour + base status), once loaded.
  readonly property var status: {
    if (!gorelo || !gorelo.statuses) return null
    for (var i = 0; i < gorelo.statuses.length; i++)
      if (gorelo.statuses[i].Id === statusId) return gorelo.statuses[i]
    return null
  }
  subtitleIcon: status && statusName ? Api.statusIcon(status) : ""
  subtitleIconColor: Api.statusColor(status) || dim

  subtitle: {
    var parts = []
    if (statusName) parts.push(statusName)
    if (clientName) parts.push(clientName)
    if (showAssignee && assigneeName) parts.push(assigneeName)
    if (waiting) parts.push("waiting on client")
    return parts.join(" · ")
  }
  tooltipText: "Show " + displayNumber + " actions"
  chevronTooltip: "Actions"

  mainLine: Component {
    Item {
      implicitHeight: Math.max(titleText.implicitHeight, priorityText.implicitHeight)

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
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.age
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  expansionComponent: Component {
    // An Item wrapper: a Column must not contain an anchors.fill child (Qt
    // disables its layout), so the click blocker sits behind the Column.
    Item {
      implicitHeight: actionsColumn.implicitHeight
      readonly property bool dropdownOpen: statusDropdown.popupOpen
      readonly property bool noteFocused: noteField.activeFocus

      // Declared first so the controls above keep their own clicks and a
      // click on empty space does not fall through to "open ticket".
      MouseArea { anchors.fill: parent }

      Column {
      id: actionsColumn
      width: parent.width
      spacing: Style.spacing.lg
      topPadding: Style.spacing.sm

      Text {
        width: parent.width
        visible: row.lastSummary !== ""
        textFormat: Text.PlainText
        text: row.lastSummary
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }
      Row {
        spacing: Style.spacing.lg
        StatusDropdown {
          id: statusDropdown
          showLabel: false
          fontFamily: row.family
          foreground: row.fg
          width: Style.space(170)
          options: row.gorelo ? row.gorelo.statuses.map(function(status) {
            return {
              value: String(status.Id),
              label: String(status.Name),
              icon: Api.statusIcon(status),
              color: Api.statusColor(status)
            }
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
          text: "Open in Gorelo"
          foreground: row.fg
          fontFamily: row.family
          onClicked: if (row.gorelo) row.gorelo.openTicket(row.ticketId)
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
          font.family: row.family
          verticalPadding: Style.spacing.sm
          onAccepted: addNote.clicked()
          Keys.onEscapePressed: function(event) { noteField.focus = false; event.accepted = true }
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
}
