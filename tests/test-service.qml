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

    property var savedSettings: null
    property bool acceptWrites: true
    property int updateCalls: 0
    property var shellConfig: ({
      bar: {
        layout: {
          left: [],
          center: [],
          right: [{
            id: "io.github.orienw.fresh-wallpaper",
            intervalMinutes: 43200,
            runOnStart: false
          }]
        }
      },
      plugins: []
    })

    function updateEntryInline(pluginId, settings) {
      updateCalls++
      if (!acceptWrites) return false
      savedSettings = settings
      var copy = JSON.parse(JSON.stringify(shellConfig))
      var entry = { id: pluginId }
      for (var key in settings) if (key !== "id") entry[key] = settings[key]
      copy.bar.layout.right[0] = entry
      shellConfig = copy
      return true
    }
  }

  Loader {
    id: serviceLoader
    source: "file://" + Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR") + "/Service.qml"
    onLoaded: {
      item.shell = fakeShell
      item.manifest = {
        id: "io.github.orienw.fresh-wallpaper",
        __sourceDir: Quickshell.env("FRESH_WALLPAPER_PROJECT_DIR")
      }
      checkTimer.start()
    }
  }

  Timer {
    id: checkTimer
    interval: 250
    repeat: false
    onTriggered: {
      var service = serviceLoader.item
      if (!service || !service.initialized) {
        root.fail("service did not initialize")
        return
      }
      if (service.intervalMinutes !== 43200) {
        root.fail("monthly preset was not loaded")
        return
      }
      if (service.runOnStart || service.lastTrigger !== "") {
        root.fail("change on start was not off by default")
        return
      }
      if (service.initialRefreshTrigger(false, false) !== "first-run"
          || service.initialRefreshTrigger(true, false) !== ""
          || service.initialRefreshTrigger(true, true) !== "startup") {
        root.fail("initial refresh behavior is incorrect")
        return
      }
      if (service.scheduleChunkMs !== 60 * 60 * 1000) {
        root.fail("schedule wake interval is not suspend-safe")
        return
      }

      var remaining = service.scheduledAtMs() - Date.now()
      var monthlyMs = 30 * 24 * 60 * 60000
      if (remaining < monthlyMs - 2000 || remaining > monthlyMs) {
        root.fail("monthly schedule has the wrong duration: " + remaining)
        return
      }

      service.lastTrigger = "first-run"
      service.processFailed("synthetic network failure")
      var retryRemaining = service.scheduledAtMs() - Date.now()
      if (retryRemaining < 15 * 60000 - 2000 || retryRemaining > 15 * 60000
          || service.failureNotified || service.shouldNotifyFailure()) {
        root.fail("first-run retry behavior is incorrect: " + retryRemaining)
        return
      }
      service.lastTrigger = "retry"
      if (!service.shouldNotifyFailure()) {
        root.fail("a repeated startup failure would stay silent")
        return
      }
      service.retryAfterMs = 0
      service.consecutiveFailures = 0
      service.lastError = ""
      service.lastTrigger = ""
      service.armSchedule()

      if (service.normalizedInterval(525601) !== 525600) {
        root.fail("custom interval maximum was not enforced")
        return
      }
      if (service.setIntervalMinutes("43200") !== "43200"
          || service.setRunOnStart("false") !== "false"
          || fakeShell.updateCalls !== 0) {
        root.fail("idempotent settings were treated as failed writes")
        return
      }

      fakeShell.acceptWrites = false
      if (service.setIntervalMinutes("525600").indexOf("error:") !== 0
          || fakeShell.updateCalls !== 1) {
        root.fail("a rejected setting write was reported as successful")
        return
      }
      fakeShell.acceptWrites = true
      if (service.setIntervalMinutes("525600") !== "525600"
          || !fakeShell.savedSettings
          || fakeShell.savedSettings.intervalMinutes !== 525600) {
        root.fail("custom interval was not persisted")
        return
      }
      if (service.setIntervalMinutes("525601").indexOf("error:") !== 0) {
        root.fail("out-of-range interval was accepted")
        return
      }
      if (service.setCacheLimit("8") !== "8"
          || fakeShell.savedSettings.cacheLimit !== 8
          || service.setCacheLimit("7").indexOf("error:") !== 0) {
        root.fail("cache limit validation or persistence is incorrect")
        return
      }

      console.log("service schedule tests passed")
      root.finished = true
      Qt.quit()
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: false
    onTriggered: if (!root.finished) root.fail("test timed out")
  }
}
