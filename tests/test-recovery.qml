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
        service.refreshStatus()
        backgroundTimer.start()
      }
    }
  }

  Timer {
    id: backgroundTimer
    interval: 50
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      var external = service.externalBackgroundPath
      if (external === "stale") return
      stop()
      if (root.expectRecovery ? external !== "" : !/\/wallpaper\.jpg$/.test(external)) {
        console.error("TEST FAILURE: the panel background state is wrong:", external)
        Qt.quit()
        return
      }
      // Only the status that follows an update may change what the panel previews.
      service.processSucceeded()
      if (service.externalBackgroundPath !== external) {
        console.error("TEST FAILURE: a finished update changed the preview before its status arrived")
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
