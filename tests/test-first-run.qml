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
            intervalMinutes: 1440,
            runOnStart: false
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
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || service.lastTrigger !== "first-run" || service.running) return
      if (service.currentWallpaper.path !== Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE")) {
        root.fail("first-run wallpaper was not loaded")
        return
      }

      console.log("service first-run test passed")
      root.finished = true
      stop()
      Qt.quit()
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: false
    onTriggered: {
      if (root.finished) return
      var service = serviceLoader.item
      root.fail("first-run test timed out: initialized=" + Boolean(service && service.initialized)
        + ", startupResolved=" + Boolean(service && service.startupResolved)
        + ", lastTrigger=" + String(service ? service.lastTrigger : "")
        + ", running=" + Boolean(service && service.running)
        + ", path=" + String(service && service.currentWallpaper
          ? service.currentWallpaper.path || "" : "")
        + ", error=" + String(service ? service.lastError : ""))
    }
  }
}
