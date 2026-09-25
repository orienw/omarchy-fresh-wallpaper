import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string boundsCase: Quickshell.env("FRESH_WALLPAPER_TEST_BOUNDS")
  readonly property bool helperFails: boundsCase === "hang" || boundsCase === "noisy"
  // Set when the stderr cap fills while the helper still runs, so it streamed.
  property bool streamed: false

  function finish(failure) {
    if (failure !== "") console.error("TEST FAILURE:", boundsCase + ":", failure)
    else console.log("service bounds test passed")
    Qt.quit()
  }

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
      item.fetchTimeoutSeconds = 1
      item.statusTimeoutSeconds = 1
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
      if (!service || !service.initialized || service.pendingStartupTrigger !== "") return
      if (root.boundsCase === "noisy" && service.running && service.fetchError.length === 4096)
        root.streamed = true
      if (root.helperFails && (service.running || service.lastError === "")) return
      stop()
      if (root.boundsCase === "hang") {
        root.finish(service.lastError === "Wallpaper update timed out"
          ? "" : "a hung helper was not stopped: " + service.lastError)
      } else if (root.boundsCase === "noisy") {
        root.finish(root.streamed && service.fetchError.length === 4096 && service.lastError.length <= 240
          ? "" : "helper stderr was not streamed into a bounded buffer: " + service.fetchError.length)
      } else {
        root.finish(service.lastTrigger === "first-run"
          ? "" : "untrusted state was loaded: " + JSON.stringify(service.currentWallpaper))
      }
    }
  }

  Timer {
    interval: 8000
    running: true
    onTriggered: root.finish("did not finish")
  }
}
