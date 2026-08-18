import QtQuick
import qs.Ui

// qmllint disable missing-property

BarWidget {
  id: root
  moduleName: "io.github.orienw.fresh-wallpaper"

  readonly property var wallpaperService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.wallpaperService && root.wallpaperService.running ? "󰑐" : ""
    active: root.wallpaperService && root.wallpaperService.lastError !== ""
    textRotation: root.wallpaperService && root.wallpaperService.running ? 45 : 0
    tooltipText: root.wallpaperService && root.wallpaperService.running
      ? "Changing wallpaper..."
      : (root.wallpaperService && root.wallpaperService.lastError !== ""
        ? "Fresh Wallpaper needs attention"
        : "Fresh Wallpaper")

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        if (root.wallpaperService) root.wallpaperService.startRefresh("bar")
      } else {
        root.togglePanel()
      }
    }
  }
}
// qmllint enable missing-property
