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

    property var shellConfig: ({
      bar: {
        layout: {
          left: [],
          center: [],
          right: [{
            id: "io.github.orienw.fresh-wallpaper",
            intervalMinutes: 15,
            runOnStart: true
          }]
        }
      },
      plugins: []
    })
  }

  Loader {
    id: serviceLoader
    source: Quickshell.env("FRESH_WALLPAPER_TEST_SERVICE_URL")
    onLoaded: {
      item.currentBackgroundLink = Quickshell.env("FRESH_WALLPAPER_TEST_BACKGROUND")
      item.shell = fakeShell
      item.manifest = {id: "io.github.orienw.fresh-wallpaper"}
    }
  }

  Timer {
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || service.lastTrigger !== "startup" || service.running) return
      if (service.currentWallpaper.path !== Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE")) {
        root.fail("startup wallpaper was not loaded")
        return
      }
      stop()
      settleTimer.start()
    }
  }

  Timer {
    id: settleTimer
    interval: 1300
    repeat: false
    onTriggered: {
      var service = serviceLoader.item
      if (service.running) {
        root.fail("startup launched a second refresh")
        return
      }
      console.log("service overdue startup test passed")
      root.finished = true
      Qt.quit()
    }
  }

  Timer {
    interval: 4000
    running: true
    repeat: false
    onTriggered: if (!root.finished) root.fail("overdue startup test timed out")
  }
}
