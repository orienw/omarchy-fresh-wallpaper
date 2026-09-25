import QtQuick
import Quickshell

ShellRoot {
  id: root

  property bool finished: false
  readonly property string untrustedMarkup: "<img src=\""
    + Quickshell.env("FRESH_WALLPAPER_TEST_UNTRUSTED_IMAGE") + "\">"

  function fail(message) {
    console.error("TEST FAILURE:", message)
    finished = true
    Qt.quit()
  }

  QtObject {
    id: fakeService

    property var currentWallpaper: ({})
    property bool running: false
    property string lastError: "curl: (3) invalid URL: " + root.untrustedMarkup
    property string provider: "bing"
    property string market: "en-US"
    property int intervalMinutes: 1440
    property bool runOnStart: false
    property var settings: ({})
    property string externalBackgroundPath: ""
    property string previewWallpaperPath: currentWallpaper.path || ""
    property double nextChangeAtMs: 0
    property double retryAfterMs: 0
    property bool previousAvailable: false
    property int previousCalls: 0
    property int statusRefreshes: 0

    function startRefresh(trigger) { return trigger }
    function refreshStatus() { statusRefreshes++ }
    function startPrevious() { previousCalls++; return "started" }
    function setProvider(value) { provider = value; return value }
    function setIntervalMinutes(value) { intervalMinutes = Number(value); return String(value) }
    function setMarket(value) { market = value; return value }
    function setRunOnStart(value) { runOnStart = value === "true"; return value }
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
      widget.settings = {intervalMinutes: 43200, market: "en-GB"}
      if (fakeService.settings.intervalMinutes !== 43200 || fakeService.settings.market !== "en-GB") {
        root.fail("bar settings did not reach the service")
        return
      }

      stop()
      fakeService.currentWallpaper = ({
        path: Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE"),
        title: root.untrustedMarkup,
        copyright: root.untrustedMarkup
      })
      updateTimer.start()
    }
  }

  Timer {
    id: updateTimer
    interval: 50
    repeat: true
    onTriggered: {
      var panel = panelLoader.item
      var expectedPath = Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE")
      if (panel.previewPath !== expectedPath) {
        root.fail("populated wallpaper state did not update the preview")
        return
      }
      if (panel.previewPlaceholderVisible) return
      stop()

      fakeService.intervalMinutes = 0
      if (panel.selectFrequency("custom") !== "60") {
        root.fail("selecting Custom did not persist a real interval")
        return
      }
      settingsTimer.start()
    }
  }

  Timer {
    id: settingsTimer
    interval: 50
    repeat: false
    onTriggered: {
      var panel = panelLoader.item
      if (fakeService.intervalMinutes !== 60
          || !panel.customIntervalVisible
          || panel.customIntervalDraft !== 60
          || panel.startupCursorIndex !== 7) {
        root.fail("Custom frequency state was not applied")
        return
      }

      if (panel.nextChangeLabel() !== "") {
        root.fail("an unscheduled service showed a next change time")
        return
      }
      panel.nowMs = Date.now()
      fakeService.nextChangeAtMs = panel.nowMs + 14 * 3600000
      if (panel.nextChangeLabel() !== "Next change in 14h") {
        root.fail("next change time is wrong: " + panel.nextChangeLabel())
        return
      }
      fakeService.nextChangeAtMs = panel.nowMs + 30 * 86400000
      fakeService.retryAfterMs = 1
      if (panel.nextChangeLabel() !== "Retrying in 30 days") {
        root.fail("retry time is wrong: " + panel.nextChangeLabel())
        return
      }
      fakeService.nextChangeAtMs = panel.nowMs + 20 * 60000
      fakeService.retryAfterMs = 0
      if (panel.nextChangeLabel() !== "Next change in 20 min") {
        root.fail("minute countdown is wrong: " + panel.nextChangeLabel())
        return
      }

      panel.cursorIndex = 0
      panel.moveCursor(1)
      if (panel.cursorIndex !== panel.sourceCursorIndex) {
        root.fail("the keyboard cursor stopped on an unavailable Previous button")
        return
      }
      if (panel.bingLink("/search?q=aspens") !== "https://www.bing.com/search?q=aspens"
          || panel.bingLink("https://www.bing.com/search?q=aspens") !== "https://www.bing.com/search?q=aspens"
          || panel.bingLink("https://www.bing.com.example.com/") !== ""
          || panel.bingLink("https://bing.com@example.com/") !== ""
          || panel.bingLink("//example.com/") !== ""
          || panel.bingLink("javascript:alert(1)") !== "") {
        root.fail("the Learn more link accepted a non-Bing address")
        return
      }
      fakeService.previousAvailable = true
      panel.cursorIndex = 0
      panel.moveCursor(1)
      panel.activateCursor()
      if (panel.cursorIndex !== panel.previousCursorIndex || fakeService.previousCalls !== 1) {
        root.fail("the Previous button did not restore the previous wallpaper")
        return
      }

      panel.cursorIndex = panel.startupCursorIndex
      if (panel.setCustomInterval("1440") !== "1440") {
        root.fail("panel settings did not reach the service")
        return
      }
      finishTimer.start()
    }
  }

  Timer {
    id: finishTimer
    interval: 50
    repeat: false
    onTriggered: {
      var panel = panelLoader.item
      if (panel.customIntervalVisible
          || panel.startupCursorIndex !== 6
          || panel.cursorIndex !== 6) {
        root.fail("cursor was not clamped when the Custom row closed")
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
