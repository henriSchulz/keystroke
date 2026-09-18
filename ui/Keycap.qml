import QtQuick
import qs.Commons
import "../henri-ui/Motion.js" as Motion

Rectangle {
  id: root
  property string label: ""
  property bool bright: false
  property color foreground: Color.menu.text
  implicitWidth: key.implicitWidth + Style.space(12)
  implicitHeight: Style.space(22)
  radius: Style.space(Motion.radiusChip)
  color: Util.alpha(root.foreground, root.bright ? 0.14 : 0.07)
  border.width: 1
  border.color: Util.alpha(root.foreground, root.bright ? 0.28 : 0.14)
  Text {
    id: key
    anchors.centerIn: parent
    text: root.label
    textFormat: Text.PlainText
    color: Util.alpha(root.foreground, root.bright ? 0.95 : Motion.secondaryTextAlpha)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}
