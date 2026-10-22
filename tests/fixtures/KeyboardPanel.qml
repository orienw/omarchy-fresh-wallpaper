import QtQuick
import qs.Commons

// Offscreen host: the panel and its controls still use Omarchy's real UI kit.
Item {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property Item focusTarget: null
  property bool open: false
  property int padding: Style.spacing.popupPadding
  property int contentWidth: 400
  property int contentHeight: 600
  property int viewportWidth: parent ? parent.width : 900
  property int viewportHeight: parent ? parent.height : 900
  readonly property int verticalContentInset: padding * 2 + 4
  default property alias contentItem: holder.children

  width: contentWidth
  height: contentHeight
  clip: true

  function fittedContentWidth(width) {
    return Math.min(width, viewportWidth)
  }
  function fittedContentHeight(height) {
    return Math.min(height + verticalContentInset, viewportHeight)
  }

  onOpenChanged: if (open) Qt.callLater(function() {
    if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
  })

  Item {
    id: holder
    anchors.fill: parent
    anchors.margins: root.padding + 2
  }
}
