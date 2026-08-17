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
    id: fakeShell

    property var savedSettings: null
    property var shellConfig: ({
      bar: {
        layout: {
          left: [],
          center: [],
          right: [{
            id: "io.github.orienw.fresh-wallpaper",
            intervalMinutes: 43200,
            runOnStart: false
          }]
        }
      },
      plugins: []
    })

    function updateEntryInline(pluginId, settings) {
      savedSettings = settings
      return true
    }
  }

  Loader {
    id: serviceLoader
    source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/Service.qml"
    onLoaded: {
      item.shell = fakeShell
      item.manifest = {
        id: "io.github.orienw.fresh-wallpaper",
        __sourceDir: Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR")
      }
      checkTimer.start()
    }
  }

  Timer {
    id: checkTimer
    interval: 250
    repeat: false
    onTriggered: {
      var service = serviceLoader.item
      if (!service || !service.initialized) {
        root.fail("service did not initialize")
        return
      }
      if (service.intervalMinutes !== 43200) {
        root.fail("monthly preset was not loaded")
        return
      }

      var remaining = service.scheduledAtMs() - Date.now()
      var monthlyMs = 30 * 24 * 60 * 60000
      if (remaining < monthlyMs - 2000 || remaining > monthlyMs) {
        root.fail("monthly schedule has the wrong duration: " + remaining)
        return
      }
      if (service.normalizedInterval(525601) !== 525600) {
        root.fail("custom interval maximum was not enforced")
        return
      }
      if (service.setIntervalMinutes("525600") !== "525600"
          || !fakeShell.savedSettings
          || fakeShell.savedSettings.intervalMinutes !== 525600) {
        root.fail("custom interval was not persisted")
        return
      }
      if (service.setIntervalMinutes("525601").indexOf("error:") !== 0) {
        root.fail("out-of-range interval was accepted")
        return
      }

      console.log("service schedule tests passed")
      root.finished = true
      Qt.quit()
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: false
    onTriggered: if (!root.finished) root.fail("test timed out")
  }
}
