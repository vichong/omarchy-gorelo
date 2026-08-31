pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui
import qs.Commons

// One managed computer in search results.
ListRow {
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

  subtitle: [clientName, statusName, lastUser].filter(function(value) { return value !== "" }).join(" · ")
  tooltipText: "Show " + name + " details"
  chevronTooltip: "Details"

  readonly property string networkSummary: {
    var parts = []
    if (localIp) parts.push("Local " + localIp)
    if (publicIp) parts.push("Public " + publicIp)
    return parts.join(" · ")
  }

  mainLine: Component {
    Item {
      implicitHeight: Math.max(nameText.implicitHeight, statusDot.implicitHeight)

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
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.lastSeen
        color: row.faint
        font.family: row.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  expansionComponent: Component {
    Column {
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
