import QtQuick
import qs.Ui
import qs.Commons

// Shared interaction and chrome for ticket and device rows.
CursorSurface {
  id: row

  property var gorelo: null
  property QtObject bar: null
  property bool expanded: false
  property string subtitle: ""
  property string tooltipText: ""
  property string chevronTooltip: "Details"
  property Component mainLine: null
  property Component expansionComponent: null
  readonly property var expansionItem: expansion.item

  signal expandToggled()
  signal cursorRequested()
  signal activated()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color faint: Qt.darker(fg, 1.8)

  foreground: fg
  current: expanded
  implicitHeight: layout.implicitHeight + Style.spacing.rowPaddingX

  function activate() { row.activated() }

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
    text: row.tooltipText
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
      implicitHeight: Math.max(lineLoader.implicitHeight, chevron.implicitHeight)
      height: implicitHeight

      Loader {
        id: lineLoader
        anchors.left: parent.left
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: chevron.visible ? Style.spacing.sm : 0
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: row.mainLine
      }

      PanelActionButton {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: rowMouse.containsMouse || row.hasCursor || row.expanded
        iconText: row.expanded ? "󰅃" : "󰅀"
        tooltipText: row.expanded ? "Collapse" : row.chevronTooltip
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

    Loader {
      id: expansion
      width: parent.width
      active: row.expanded
      visible: active
      sourceComponent: row.expansionComponent
    }
  }
}
