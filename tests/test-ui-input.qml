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
    property bool hasExternalBackground: false
    property string previewWallpaperPath: ""
    property double nextChangeAtMs: 0
    property double retryAfterMs: 0
    property bool previousAvailable: false
    property int refreshCalls: 0
    property int previousCalls: 0
    property bool rejectWrites: false

    function refreshStatus() {}
    function startRefresh(trigger) { refreshCalls++; running = true }
    function startPrevious() { previousCalls++ }
    function setProvider(value) {
      if (rejectWrites) return "error: setting could not be saved"
      provider = value
      return value
    }
    function setIntervalMinutes(value) {
      if (rejectWrites) return "error: setting could not be saved"
      intervalMinutes = Number(value)
      return String(value)
    }
    function setMarket(value) {
      if (rejectWrites) return "error: setting could not be saved"
      market = value
      return value
    }
    function setRunOnStart(value) { runOnStart = value === "true"; return value }
  }

  QtObject {
    id: fakeShell
    property bool available: true
    function serviceFor(id) { return available ? service : null }
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
        input.testNoTextEntry()
        input.testPointerThenKeyboard()
        input.testDropdownFocus()
        input.testDropdownValues()
        input.testRejectedDropdownValues()
        input.testEscape()
        input.testShortPanel()
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

    function testNoTextEntry() {
      root.check(root.find(loader.item, "readOnly", false) === null, "the panel contains an editable text field")
    }

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
        root.check(root.find(window.contentItem, "readOnly", false) === null,
          labels[i] + " opened an editable text field")
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
      for (var i = 0; i < 3; i++) keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.intervalMinutes === 60 && frequency.currentLabel() === "Hourly",
        "Frequency selection was not applied")
      service.intervalMinutes = 75
      root.check(frequency.value === "75" && frequency.currentLabel() === "Custom (75 min)",
        "Frequency did not list an interval set outside the panel")
      mouseClick(frequency, frequency.width / 2, frequency.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.intervalMinutes === 43200 && frequency.currentLabel() === "Monthly (30 days)",
        "a preset did not replace the Custom interval")
      root.check(frequency.options.length === panel.frequencyPresets.length,
        "Custom stayed listed after a preset replaced it")

      service.intervalMinutes = 75
      mouseClick(frequency, frequency.width / 2, frequency.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Up)
      service.intervalMinutes = 90
      wait(30)
      root.check(!frequency.popupOpen, "Frequency stayed open after the interval changed underneath it")
      panel.cursorIndex = panel.frequencyCursorIndex
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.intervalMinutes === 90 && frequency.popupOpen, "Enter saved a stale Frequency highlight")
      frequency.close()
      wait(30)
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

    function testRejectedDropdownValues() {
      var panel = loader.item
      var frequency = root.find(panel, "label", "Frequency")
      var region = root.find(panel, "label", "Region")
      service.intervalMinutes = 1440
      service.market = "en-US"
      service.rejectWrites = true

      mouseClick(frequency, frequency.width / 2, frequency.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.intervalMinutes === 1440 && frequency.currentLabel() === "Daily",
        "a rejected preset remained selected")

      service.intervalMinutes = 75
      mouseClick(frequency, frequency.width / 2, frequency.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.intervalMinutes === 75 && frequency.currentLabel() === "Custom (75 min)",
        "a rejected preset replaced the Custom interval")

      mouseClick(region, region.width / 2, region.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(30)
      root.check(service.market === "en-US" && region.currentLabel() === "United States",
        "a rejected region remained selected")
      service.rejectWrites = false

      service.intervalMinutes = 1440
      service.market = "en-US"
      fakeShell.available = false
      mouseClick(frequency, frequency.width / 2, frequency.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(30)
      mouseClick(region, region.width / 2, region.height - Style.spacing.controlHeight / 2)
      wait(30)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(30)
      fakeShell.available = true
      root.check(service.intervalMinutes === 1440 && frequency.currentLabel() === "Daily",
        "Frequency kept a choice made while the service was unavailable")
      root.check(service.market === "en-US" && region.currentLabel() === "United States",
        "Region kept a choice made while the service was unavailable")
      service.intervalMinutes = 10080
      service.market = "en-CA"
      root.check(frequency.currentLabel() === "Weekly" && region.currentLabel() === "Canada",
        "dropdown bindings stopped following service changes after a rejected save")
    }

    function testEscape() {
      parkPointer()
      keyClick(Qt.Key_Escape)
      root.check(!loader.item.opened, "Escape did not close the panel")
    }

    function testShortPanel() {
      var panel = loader.item
      window.height = Style.space(300)
      service.lastError = "A download error with enough detail to wrap onto a second line."
      service.currentWallpaper = ({copyright: "An image attribution naming the photographer and location."})
      service.intervalMinutes = 60
      panel.cursorIndex = 0
      panel.open()
      wait(50)
      var flick = root.find(panel, "flickableDirection", Flickable.VerticalFlick)
      root.check(flick !== null, "a short panel did not provide scrolling")
      for (var i = 0; i < panel.startupCursorIndex; i++) {
        keyClick(Qt.Key_Down)
        wait(10)
      }
      var startup = root.find(panel, "label", "Change on start")
      var position = startup.mapToItem(flick, 0, 0)
      root.check(flick.contentY > 0 && position.y >= -1
        && position.y + startup.height <= flick.height + 1,
        "keyboard navigation left the startup toggle outside the viewport")
      keyClick(Qt.Key_Return)
      root.check(service.runOnStart, "the visible startup toggle could not be activated")
      mouseWheel(flick, flick.width / 2, flick.height / 2, 0, 1200)
      waitForScroll(flick)
      var change = root.find(panel, "text", "Change now")
      position = change.mapToItem(flick, 0, 0)
      root.check(position.y >= 0 && position.y + change.height <= flick.height,
        "the mouse wheel could not return to the wallpaper actions")
      mouseWheel(flick, flick.width / 2, flick.height / 2, 0, -1200)
      waitForScroll(flick)
      position = startup.mapToItem(flick, 0, 0)
      root.check(position.y >= -1 && position.y + startup.height <= flick.height + 1,
        "the mouse wheel could not reach the startup toggle")
      mouseClick(startup, startup.width / 2, startup.height / 2)
      root.check(!service.runOnStart, "the scrolled startup toggle did not respond to a click")
    }

    function parkPointer() {
      // Keep deferred hover updates from moving the keyboard cursor.
      mouseMove(window.contentItem, window.width - 1, window.height - 1)
      wait(0)
    }

    function waitForScroll(flick) {
      for (var i = 0; flick.moving && i < 50; i++) wait(20)
      root.check(!flick.moving, "mouse-wheel scrolling did not settle")
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
