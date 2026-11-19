import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string recoveryCase: Quickshell.env("FRESH_WALLPAPER_TEST_RECOVERY")
  readonly property bool expectRecovery: recoveryCase === "missing"
  readonly property bool expectExternal: recoveryCase === "replaced" || recoveryCase === "missing-cache"

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
        console.error("TEST FAILURE: an update started with nothing missing:", service.lastTrigger)
        Qt.quit()
      } else {
        service.recentCount = -1
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
      if (service.recentCount === -1) return
      stop()
      var external = service.hasExternalBackground
      if (external !== root.expectExternal) {
        console.error("TEST FAILURE: the panel background state is wrong:", external)
        Qt.quit()
        return
      }
      if (root.recoveryCase === "companion"
          && (service.previewWallpaperPath !== "" || !service.hasCurrentWallpaper())) {
        console.error("TEST FAILURE: a wallpaper with a high-DPI companion was previewed or dropped")
        Qt.quit()
        return
      }
      // Only the status that follows an update may change what the panel previews.
      var preview = service.previewWallpaperPath
      service.processSucceeded()
      if (service.hasExternalBackground !== external || service.previewWallpaperPath !== preview) {
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
