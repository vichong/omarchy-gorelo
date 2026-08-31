import QtQuick
import qs.Ui
import qs.Commons

// One managed computer in search results. Keep activation routed through
// Service.openDevice so the eventual remote-connect action has one home.
CursorSurface {
  id: row

  required property string deviceId
  required property string name
  required property string hostName
  required property string clientName
  required property string statusName
  required property bool online
  required property string lastUser
  required property string os
  required property string lastSeen
  required property string localIp
  required property string publicIp
  required property string url

  property var gorelo: null
  property QtObject bar: null
  property bool expanded: false

  signal expandToggled()
  signal cursorRequested()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color faint: Qt.darker(fg, 1.8)

  foreground: fg
  current: expanded
  implicitHeight: layout.implicitHeight + Style.spacing.rowPaddingX

  function activate() {
    if (gorelo) gorelo.openDevice(deviceId)
  }

  readonly property string subtitle: {
    var parts = []
    if (row.clientName) parts.push(row.clientName)
    if (row.statusName) parts.push(row.statusName)
    if (row.lastUser) parts.push(row.lastUser)
    return parts.join(" · ")
  }

  readonly property string networkSummary: {
    var parts = []
    if (row.localIp) parts.push("Local " + row.localIp)
    if (row.publicIp) parts.push("Public " + row.publicIp)
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
    text: "Open " + row.name + " in Gorelo · right-click for details"
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

    Item {
      width: parent.width
      implicitHeight: Math.max(nameText.implicitHeight, statusDot.implicitHeight)
      height: implicitHeight

      Text {
        id: statusDot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        textFormat: Text.PlainText
        text: "●"
        color: row.online ? Color.accent : row.dim
        font.family: row.family
        font.pixelSize: Style.font.caption
      }

      Text {
        id: nameText
        anchors.left: statusDot.right
        anchors.right: lastSeenText.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.name || row.hostName || "(unnamed device)"
        elide: Text.ElideRight
        color: row.fg
        font.family: row.family
        font.pixelSize: Style.font.body
      }

      Text {
        id: lastSeenText
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: chevron.visible ? Style.spacing.sm : 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.lastSeen
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: rowMouse.containsMouse || row.hasCursor || row.expanded
        iconText: row.expanded ? "󰅃" : "󰅀"
        tooltipText: row.expanded ? "Collapse" : "Details"
        foreground: row.dim
        fontFamily: row.family
        fontSize: Style.font.iconSmall
        onClicked: row.expandToggled()
      }
    }

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

    Column {
      width: parent.width
      visible: row.expanded
      spacing: Style.spacing.sm
      topPadding: Style.spacing.sm

      Text {
        width: parent.width
        visible: row.os !== "" || row.hostName !== ""
        textFormat: Text.PlainText
        text: [row.os, row.hostName].filter(function(value) { return value !== "" }).join(" · ")
        elide: Text.ElideRight
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: row.networkSummary !== ""
        textFormat: Text.PlainText
        text: row.networkSummary
        elide: Text.ElideRight
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }

      Button {
        bordered: true
        text: "Open in Gorelo"
        foreground: row.fg
        fontFamily: row.family
        onClicked: row.activate()
      }
    }
  }
}
