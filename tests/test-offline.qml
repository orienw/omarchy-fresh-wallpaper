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
            intervalMinutes: 0,
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
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || service.lastTrigger !== "first-run" || service.running) return

      var retryRemaining = service.scheduledAtMs() - Date.now()
      if (service.lastError !== "" || service.failureNotified
          || retryRemaining < 5000 - 1000 || retryRemaining > 5000
          || service.statusPayload().nextRunAt === null) {
        root.fail("offline first-run was not deferred in manual mode: " + retryRemaining)
        return
      }

      console.log("service offline deferral test passed")
      root.finished = true
      stop()
      Qt.quit()
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: if (!root.finished) root.fail("offline deferral test timed out")
  }
}
