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
    source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/Service.qml"
    onLoaded: {
      item.currentBackgroundLink = Quickshell.env("FRESH_WALLPAPER_TEST_BACKGROUND")
      item.shell = fakeShell
      item.manifest = {
        id: "io.github.orienw.fresh-wallpaper",
        __sourceDir: Quickshell.env("FRESH_WALLPAPER_TEST_PLUGIN_DIR")
      }
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || !service.initialized || service.running || service.pendingStartupTrigger !== "") return
      if (root.expectRecovery
                 && (service.lastTrigger !== "first-run"
                     || service.currentWallpaper.path !== Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE"))) {
        console.error("TEST FAILURE: the missing cached wallpaper was not recovered")
      } else if (!root.expectRecovery && service.lastTrigger !== "") {
        console.error("TEST FAILURE: recovery replaced an external background")
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
