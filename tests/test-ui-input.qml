import QtQuick
import QtTest
import Quickshell
import qs.Commons

ShellRoot {
  id: root

  QtObject {
    id: service
    property var currentWallpaper: ({})
    property bool running: false
    property string lastError: ""
    property string provider: "bing"
    property string market: "en-US"
    property int intervalMinutes: 1440
    property bool runOnStart: false
    property string externalBackgroundPath: ""
    property string previewWallpaperPath: ""
    property double nextChangeAtMs: 0
    property double retryAfterMs: 0
    property bool previousAvailable: false
    property int refreshCalls: 0

    function refreshStatus() {}
    function startRefresh(trigger) { refreshCalls++; running = true }
    function startPrevious() {}
    function setProvider(value) { provider = value; return value }
    function setIntervalMinutes(value) { intervalMinutes = Number(value); return String(value) }
    function setMarket(value) { market = value; return value }
    function setRunOnStart(value) { runOnStart = value === "true"; return value }
  }

  QtObject {
    id: fakeShell
    function serviceFor(id) { return service }
  }

  QtObject {
    id: bar
    property var shell: fakeShell
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color urgent: "#ff6666"
    property string fontFamily: "sans-serif"
    function switchPanelFrom(owner, direction) { return false }
  }

  Window {
    id: window
    visible: true
    width: Style.space(640)
    height: Style.space(1000)

    Item {
      id: anchor
      width: 30
      height: 30
    }

    Loader {
      id: loader
      anchors.fill: parent
      source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/Panel.qml"
      onLoaded: {
        item.bar = bar
        item.anchorItem = anchor
        item.width = Qt.binding(function() { return window.width })
        item.height = Qt.binding(function() { return window.height })
        item.open()
        runTimer.start()
      }
    }
  }

  function find(item, property, value) {
    if (item[property] === value) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], property, value)
      if (found) return found
    }
    return null
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Timer {
    id: runTimer
    interval: 100
    onTriggered: {
      try {
        input.testPointerThenKeyboard()
        input.testDropdownFocus()
        input.testDropdownValues()
        console.log("UI input tests passed")
      } catch (error) {
        console.error("TEST FAILURE:", error.message)
      }
      Qt.quit()
    }
  }

  TestCase {
    id: input
    name: "PanelInput"
    when: false

    function testPointerThenKeyboard() {
      var panel = loader.item
      var change = root.find(panel, "text", "Change now")
      root.check(change !== null, "Change now control was not found")
      mouseClick(change, change.width / 2, change.height / 2)
      root.check(service.refreshCalls === 1, "pointer action did not start a refresh")
      wait(30)
      service.running = false
      wait(30)
      keyClick(Qt.Key_Down)
      root.check(panel.cursorIndex === panel.sourceCursorIndex, "Down did not select Source")
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.refreshCalls === 1, "Enter activated the previously clicked button")
      var source = root.find(panel, "label", "Source")
      root.check(source.popupOpen, "Enter did not open the highlighted Source dropdown")
      source.close()
      wait(30)
    }

    function testDropdownFocus() {
      var panel = loader.item
      var labels = ["Source", "Frequency", "Region"]
      var nextIndices = [panel.frequencyCursorIndex, panel.marketCursorIndex, panel.startupCursorIndex]
      for (var i = 0; i < labels.length; i++) {
        var dropdown = root.find(panel, "label", labels[i])
        mouseClick(dropdown, dropdown.width / 2, dropdown.height - Style.spacing.controlHeight / 2)
        wait(30)
        root.check(dropdown.popupOpen, labels[i] + " did not open on click")
        keyClick(Qt.Key_Return)
        wait(30)
        root.check(!dropdown.popupOpen, labels[i] + " did not close after selection")
        keyClick(Qt.Key_Down)
        root.check(panel.cursorIndex === nextIndices[i], "Down did not leave " + labels[i])
        root.check(!dropdown.popupOpen, "Down reopened " + labels[i])
      }
    }

    function testDropdownValues() {
      var panel = loader.item
      var frequency = root.find(panel, "label", "Frequency")
      mouseClick(frequency, frequency.width / 2, frequency.height - Style.spacing.controlHeight / 2)
      wait(30)
      for (var i = 0; i < 3; i++) keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(30)
      var custom = root.find(panel, "label", "Custom interval (minutes)")
      root.check(custom.visible && custom.field.activeFocus, "Custom selection did not focus the interval")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_1)
      keyClick(Qt.Key_4)
      keyClick(Qt.Key_4)
      keyClick(Qt.Key_0)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.intervalMinutes === 1440 && !custom.visible, "typed preset interval was not applied")
      root.check(frequency.value === "1440" && frequency.currentLabel() === "Daily", "Frequency retained Custom after entering a preset")
      service.intervalMinutes = 0
      root.check(frequency.currentLabel() === "Manual only", "Frequency ignored a service interval change")
      service.intervalMinutes = 1440

      var region = root.find(panel, "label", "Region")
      mouseClick(region, region.width / 2, region.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.market === "en-GB", "Region selection was not applied")
      service.market = "en-CA"
      root.check(region.currentLabel() === "Canada", "Region ignored a service market change")
    }
  }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.error("TEST FAILURE: UI input test timed out")
      Qt.quit()
    }
  }
}
