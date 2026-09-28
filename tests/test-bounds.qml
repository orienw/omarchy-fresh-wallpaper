import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string boundsCase: Quickshell.env("FRESH_WALLPAPER_TEST_BOUNDS")
  readonly property bool helperFails: boundsCase === "hang" || boundsCase === "noisy"
  readonly property bool statusFails: boundsCase.indexOf("status-") === 0
  readonly property bool expectRecovery: boundsCase === "status-empty" || boundsCase === "status-missing"
  readonly property string refreshTrigger: boundsCase === "status-manual" ? "manual"
    : boundsCase === "status-scheduled" ? "schedule" : ""
  property bool statusRetried: false
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
        intervalMinutes: root.boundsCase === "status-scheduled" ? 15 : 0,
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
      item.statusRetrySeconds = 1
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
      if (root.statusFails) {
        if (root.refreshTrigger !== "" && root.statusRetried) {
          if (service.running || service.statusError !== "") return
          root.finish(service.lastTrigger === root.refreshTrigger
            && (root.refreshTrigger === "manual" ? service.lastError !== "" : service.retryAfterMs > 0)
            ? "" : "status recovery repeated a failed refresh")
          return
        }
        if (!root.expectRecovery && (service.lastTrigger !== "" || service.running)) {
          root.finish("a failed status triggered a wallpaper change")
          return
        }
        if (!root.statusRetried) {
          if (service.statusPayload().lastError === "") {
            root.finish("a failed status was not reported to the user")
            return
          }
          root.statusRetried = true
          if (root.refreshTrigger !== "") service.startRefresh(root.refreshTrigger)
          return
        }
        if (service.statusError !== "" || service.running) return
        if (service.currentWallpaper.path !== Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE")) return
        if (service.statusFailures !== 0) {
          root.finish("status recovery did not reset the failures")
          return
        }
        if (root.expectRecovery && service.lastTrigger !== "first-run") {
          root.finish("first-run did not recover after a failed status")
          return
        }
        root.finish("")
        return
      }
      stop()
      if (root.boundsCase === "linked-dir") {
        root.finish(service.lastTrigger === "" && service.lastError !== ""
          ? "" : "an unsafe state directory was treated as first-run")
      } else if (root.boundsCase === "hang") {
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
