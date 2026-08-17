import QtQuick
import Quickshell

ShellRoot {
  id: root

  property bool finished: false

  function fail(message) {
    console.error("TEST FAILURE:", message)
    finished = true
    Qt.quit()
  }

  QtObject {
    id: fakeService

    property var currentWallpaper: ({})
    property bool running: false
    property string lastError: ""
    property string provider: "bing"
    property string market: "en-US"
    property int intervalMinutes: 1440
    property bool runOnStart: false

    function startRefresh(trigger) { return trigger }
    function setProvider(value) { provider = value }
    function setIntervalMinutes(value) { intervalMinutes = Number(value) }
    function setMarket(value) { market = value }
    function setRunOnStart(value) { runOnStart = value === "true" }
  }

  QtObject {
    id: fakeShell
    function serviceFor(pluginId) {
      return pluginId === "io.github.orienw.fresh-wallpaper" ? fakeService : null
    }
  }

  QtObject {
    id: fakeBar

    property var shell: fakeShell
    property color foreground: "#f0f0f0"
    property color barForeground: foreground
    property color urgent: "#ff6666"
    property color background: "#111111"
    property string fontFamily: "sans-serif"
    property string position: "top"
    property int barSize: 30
    property int sizeHorizontal: 30
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: []

    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(owner, direction) { return false }
    function targetBelongsToWindow(target, window) { return true }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function registerClickTarget(item) {}
    function unregisterClickTarget(item) {}
    function moduleWidgets(moduleName) { return [] }
  }

  Item {
    id: anchor
    width: 30
    height: 30
  }

  Loader {
    id: panelLoader
    source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/Panel.qml"
    onLoaded: {
      item.bar = fakeBar
      item.anchorItem = anchor
    }
  }

  Loader {
    id: widgetLoader
    source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/BarWidget.qml"
    onLoaded: item.bar = fakeBar
  }

  Timer {
    id: loadTimer
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (panelLoader.status === Loader.Error || widgetLoader.status === Loader.Error) {
        root.fail("a UI entry point failed to load")
        return
      }
      if (panelLoader.status !== Loader.Ready || widgetLoader.status !== Loader.Ready) return

      var panel = panelLoader.item
      var widget = widgetLoader.item
      if (!panel.previewPlaceholderVisible || panel.previewPath !== "") {
        root.fail("empty wallpaper state did not show the preview placeholder")
        return
      }
      if (widget.wallpaperService !== fakeService) {
        root.fail("bar widget did not resolve the wallpaper service")
        return
      }

      stop()
      fakeService.currentWallpaper = ({ path: Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE") })
      updateTimer.start()
    }
  }

  Timer {
    id: updateTimer
    interval: 50
    repeat: false
    onTriggered: {
      var panel = panelLoader.item
      var expectedPath = Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE")
      if (panel.previewPlaceholderVisible
          || panel.previewPath !== expectedPath
          || panel.previewSource(panel.previewPath) !== "file://" + encodeURI(expectedPath)) {
        root.fail("populated wallpaper state did not update the preview")
        return
      }

      console.log("UI smoke tests passed")
      root.finished = true
      Qt.quit()
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: false
    onTriggered: if (!root.finished) root.fail("UI smoke test timed out")
  }
}
