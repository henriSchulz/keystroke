import QtQuick
import qs.Commons
import qs.Ui
import "../henri-ui/Motion.js" as Motion
import "../henri-ui" as HUi

// Keystroke's confirmation: the shell's ConfirmDialog (same look, same keys)
// with an optional note in the muted colour under the question. Turning an
// extension on uses it to say what was checked and that the code runs at the
// user's own risk. No link: opening anything from here would move focus away
// from the palette, and the palette cannot survive that.
Item {
  id: root

  property bool opened: false
  property string message: ""
  property string detail: ""
  property string cancelText: "Cancel"
  property string confirmText: "Confirm"
  property int selectedIndex: 1
  property color background: Color.background
  property color foreground: Color.foreground
  property color muted: Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.space(Motion.radiusPopover)

  signal canceled()
  signal confirmed()

  function handleKey(event) {
    if (!root.opened) return false
    if (event.key === Qt.Key_Escape) { root.canceled(); return true }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.selectedIndex === 0) root.canceled()
      else root.confirmed()
      return true
    }
    return false
  }

  // Fades (and scales, popover-style) in and out instead of snapping; the
  // texts hold their last values while it fades out, and it takes no input
  // once it starts closing.
  visible: opened || opacity > 0
  enabled: opened
  opacity: opened ? 1 : 0
  Behavior on opacity {
    NumberAnimation {
      duration: root.opened ? Motion.slow : Motion.exit(Motion.slow)
      easing.type: Easing.BezierSpline
      easing.bezierCurve: root.opened ? Motion.easeOut : Motion.easeExit
    }
  }
  onOpenedChanged: if (opened && opacity < 0.01) cardScale.snap(Motion.popoverFromScale)
  HUi.SpringValue { id: cardScale; preset: Motion.gentle; to: root.opened ? 1 : Motion.exitToScale }
  property string shownMessage: ""
  property string shownDetail: ""
  property string shownConfirmText: ""
  Binding { target: root; property: "shownMessage"; value: root.message; when: root.opened; restoreMode: Binding.RestoreNone }
  Binding { target: root; property: "shownDetail"; value: root.detail; when: root.opened; restoreMode: Binding.RestoreNone }
  Binding { target: root; property: "shownConfirmText"; value: root.confirmText; when: root.opened; restoreMode: Binding.RestoreNone }

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(400))
      height: card.contentTopInset + card.contentBottomInset + column.implicitHeight + Style.space(20) + Style.space(34)
      anchors.centerIn: parent
      scale: cardScale.value
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(18)
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Column {
          id: column
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(8)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.shownMessage
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WordWrap
          }
          Text {
            width: parent.width
            visible: root.shownDetail.length > 0
            textFormat: Text.PlainText
            text: root.shownDetail
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(10)

          Repeater {
            model: [root.cancelText, root.shownConfirmText]

            BorderSurface {
              required property int index
              required property string modelData

              readonly property bool selected: root.selectedIndex === index
              readonly property bool destructive: index === 1

              width: Style.space(88)
              height: Style.space(34)
              color: selected
                ? (destructive ? Util.alpha(Color.urgent, 0.22) : root.selectedBackground)
                : Util.alpha(destructive ? Color.urgent : root.selectedBackground, 0)
              borderSpec: Border.flat(destructive
                ? (selected ? Color.urgent : Util.alpha(Color.urgent, 0.56))
                : (selected ? root.selectedText : Util.alpha(root.foreground, 0.38)), Style.normalBorderWidth)
              radius: Style.space(Motion.radiusControl)
              // Hover/keyboard selection: in instant, out fast.
              Behavior on color {
                ColorAnimation {
                  duration: selected ? Motion.instant : Motion.fast
                  easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: modelData
                color: destructive ? (selected ? Color.urgent : root.foreground) : (selected ? root.selectedText : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: {
                  if (index === 0) root.canceled()
                  else root.confirmed()
                }
              }
            }
          }
        }
      }
    }
  }
}
