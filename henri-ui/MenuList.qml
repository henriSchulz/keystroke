import QtQuick
import qs.Commons
import "Motion.js" as Motion

// macOS menu body: instant highlight (like NSMenu, no glide), pointer +
// keyboard (↑ ↓ Home End ⏎), separators, shortcuts, disabled/destructive
// entries, and the NSMenu blink on activation before `activated` fires.
// Put it in HUi.Surface inside HUi.Reveal and close the Reveal in onActivated;
// Esc is not handled here — it bubbles up to HUi.Reveal (dismissRequested).
//
//   HUi.MenuList {
//     model: [ { text: "Neu", icon: "󰐕", shortcut: "⌘N" }, { separator: true },
//              { text: "Löschen", danger: true } ]
//     // `checked` on any entry adds NSMenu's state column: ✓ in front of the
//     // checked ones, the other labels stay aligned.
//     onActivated: (index, entry) => { menu.open = false; run(entry) }
//   }
//
// Submenus: an entry with `submenu: [ … ]` shows › on the right and never
// activates; hovering it (after Motion.instant), → or ⏎ emit
// submenuRequested(index, entry, row). The host places a second MenuList
// beside `row`, sets `lockedIndex = index` while it is open (the parent row
// stays highlighted, the pointer may leave), and clears it on close. A new
// currentIndex on the parent means the pointer moved on — close the child.
FocusScope {
  id: root

  property var model: []
  property int currentIndex: -1
  property int minWidth: Style.space(180)
  property string fontFamily: Style.font.menuFamily || Style.font.family
  // Colours default to the theme's menu palette; an Apple-look surface
  // (apple-ui banner, Notification Center) hands in its own.
  property color textColor: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color hairline: Util.alpha(Color.foreground, Motion.hairlineAlpha)
  // Corner radius of the selected row. macOS draws a small one (5 pt);
  // the default keeps henri-ui's row radius for existing callers.
  property real itemRadius: Style.space(Motion.radiusRow)
  property bool flashing: false
  // Row whose submenu is open: stays highlighted while the pointer is elsewhere.
  property int lockedIndex: -1

  signal activated(int index, var entry)
  signal submenuRequested(int index, var entry, Item row)
  readonly property int highlightIndex: currentIndex >= 0 ? currentIndex : lockedIndex

  function hasSubmenu(i) { var e = entry(i); return e !== null && !!e.submenu }
  function requestSubmenu(i) {
    if (!selectable(i) || !hasSubmenu(i)) return
    currentIndex = i
    submenuRequested(i, entry(i), rep.itemAt(i))
  }

  readonly property bool hasCheckColumn: {
    for (var i = 0; i < model.length; i++) if (model[i] && model[i].checked !== undefined) return true
    return false
  }

  implicitWidth: Math.max(minWidth, col.rowsWidth)
  implicitHeight: col.implicitHeight

  function entry(i) { return i >= 0 && i < model.length ? model[i] : null }
  function selectable(i) {
    var e = entry(i)
    return e !== null && !e.separator && e.enabled !== false
  }
  function move(step) {
    var n = model.length
    if (n === 0) return
    var i = currentIndex
    for (var k = 0; k < n; k++) {
      i = (i + step + n) % n
      if (selectable(i)) { currentIndex = i; return }
    }
  }
  function activate(i) {
    if (flashing || !selectable(i)) return
    if (hasSubmenu(i)) { requestSubmenu(i); return }
    currentIndex = i
    flashing = true
    flash.restart()
  }

  // NSMenu blink: highlight off → on → fire.
  SequentialAnimation {
    id: flash
    ScriptAction { script: hl.suppressed = true }
    PauseAnimation { duration: Motion.flashDuration }
    ScriptAction { script: hl.suppressed = false }
    PauseAnimation { duration: Motion.flashDuration }
    ScriptAction {
      script: {
        root.flashing = false
        root.activated(root.currentIndex, root.entry(root.currentIndex))
      }
    }
  }

  Keys.onUpPressed: move(-1)
  Keys.onDownPressed: move(1)
  Keys.onPressed: function(e) {
    if (e.key === Qt.Key_Home) { currentIndex = -1; move(1); e.accepted = true }
    else if (e.key === Qt.Key_End) { currentIndex = 0; move(-1); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { activate(currentIndex); e.accepted = true }
    else if (e.key === Qt.Key_Right && hasSubmenu(currentIndex)) { requestSubmenu(currentIndex); e.accepted = true }
  }

  Timer {
    id: submenuHover
    interval: Motion.instant
    onTriggered: if (root.currentIndex >= 0 && root.hasSubmenu(root.currentIndex) && root.lockedIndex !== root.currentIndex) root.requestSubmenu(root.currentIndex)
  }

  HoverHandler {
    id: listHover
    onHoveredChanged: if (!hovered && !root.flashing && root.lockedIndex < 0) root.currentIndex = -1
  }

  Highlight {
    id: hl
    glide: false
    radius: root.itemRadius
    color: root.selectedBackground           // theme-authored (cupertino: blue)
    target: root.highlightIndex >= 0 ? rep.itemAt(root.highlightIndex) : null
  }

  Column {
    id: col
    width: root.width
    // Widest row, so shortcuts never collide with labels.
    readonly property real rowsWidth: {
      var w = 0
      for (var i = 0; i < rep.count; i++) { var it = rep.itemAt(i); if (it) w = Math.max(w, it.implicitWidth) }
      return w
    }

    Repeater {
      id: rep
      model: root.model

      delegate: Item {
        id: row
        required property int index
        required property var modelData
        readonly property bool isSeparator: modelData.separator === true
        readonly property bool isCurrent: root.highlightIndex === index && !hl.suppressed
        readonly property bool hasSubmenu: !!modelData.submenu
        readonly property color textColor: isCurrent ? root.selectedText
          : modelData.danger ? Color.urgent : root.textColor

        width: col.width
        height: isSeparator ? Style.space(9) : Style.space(Motion.menuItemHeight)
        opacity: modelData.enabled === false ? Motion.disabledOpacity : 1
        implicitWidth: isSeparator ? 0 : content.implicitWidth + Style.spacing.xl * 2
          + (shortcutLabel.visible ? shortcutLabel.implicitWidth + Style.space(24) : 0)

        Rectangle {
          visible: row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: Style.spacing.lg
          width: parent.width - Style.spacing.lg * 2
          height: 1
          color: root.hairline
        }

        Row {
          id: content
          visible: !row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: Style.spacing.xl
          spacing: Style.spacing.lg

          Text {
            visible: root.hasCheckColumn
            width: Style.space(10)
            horizontalAlignment: Text.AlignHCenter
            text: row.modelData.checked === true ? "✓" : ""
            color: row.textColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            visible: !!row.modelData.icon
            text: row.modelData.icon || ""
            color: row.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: row.modelData.text || ""
            color: row.textColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          id: shortcutLabel
          visible: !row.isSeparator && (!!row.modelData.shortcut || row.hasSubmenu)
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.xl
          anchors.verticalCenter: parent.verticalCenter
          text: row.hasSubmenu ? "\u203a" : (row.modelData.shortcut || "")
          color: row.isCurrent ? root.selectedText : Util.alpha(root.textColor, Motion.secondaryTextAlpha)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        HoverHandler {
          enabled: !row.isSeparator && !root.flashing
          onHoveredChanged: if (hovered && root.selectable(row.index)) {
            root.currentIndex = row.index
            if (row.hasSubmenu) submenuHover.restart()
          }
        }
        TapHandler {
          enabled: !row.isSeparator
          onTapped: root.activate(row.index)
        }
      }
    }
  }
}
