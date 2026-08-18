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
    source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/Service.qml"
    onLoaded: {
      item.shell = fakeShell
      item.manifest = {
        id: "io.github.orienw.fresh-wallpaper",
        __sourceDir: Quickshell.env("FRESH_WALLPAPER_TEST_PLUGIN_DIR")
      }
    }
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || service.lastTrigger !== "first-run" || service.running) return
      if (service.currentWallpaper.path !== "/tmp/first-wallpaper.jpg") {
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
    interval: 3000
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
