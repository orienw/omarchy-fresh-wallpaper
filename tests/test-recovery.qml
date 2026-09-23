import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property bool expectRecovery: Quickshell.env("FRESH_WALLPAPER_TEST_RECOVERY") === "missing"

  QtObject {
    id: fakeShell
    property var shellConfig: ({
      bar: {layout: {left: [], center: [], right: [{
        id: "io.github.orienw.fresh-wallpaper",
        intervalMinutes: 0,
        runOnStart: false
      }]}},
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
    repeat: true
    running: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || !service.initialized || service.running || service.pendingStartupTrigger !== "") return
      stop()
      if (root.expectRecovery
                 && (service.lastTrigger !== "first-run"
                     || service.currentWallpaper.path !== Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE"))) {
        console.error("TEST FAILURE: the missing cached wallpaper was not recovered")
        Qt.quit()
      } else if (!root.expectRecovery && service.lastTrigger !== "") {
        console.error("TEST FAILURE: recovery replaced an external background")
        Qt.quit()
      } else {
        service.externalBackgroundPath = "stale"
        service.checkBackground()
        backgroundTimer.start()
      }
    }
  }

  Timer {
    id: backgroundTimer
    interval: 50
    repeat: true
    onTriggered: {
      var external = serviceLoader.item.externalBackgroundPath
      if (external === "stale") return
      if (root.expectRecovery ? external !== "" : !/\/wallpaper\.jpg$/.test(external)) {
        console.error("TEST FAILURE: the panel background state is wrong:", external)
      } else {
        console.log("service recovery test passed")
      }
      Qt.quit()
    }
  }

  Timer {
    interval: 4000
    running: true
    onTriggered: {
      console.error("TEST FAILURE: recovery did not finish")
      Qt.quit()
    }
  }
}
