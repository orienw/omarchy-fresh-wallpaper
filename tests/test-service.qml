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
      if (service.currentWallpaper.path !== "/tmp/existing-wallpaper.jpg") {
        root.fail("existing wallpaper state was not loaded before startup resolved")
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
      if (service.networkWaitSeconds("first-run") !== 60
          || service.networkWaitSeconds("schedule") !== 60
          || service.networkWaitSeconds("retry") !== 5
          || service.networkWaitSeconds("panel") !== 10) {
        root.fail("network wait is not trigger-specific")
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
      service.failureNotified = false
      service.lastError = ""
      service.lastTrigger = "schedule"
      service.processDeferred()
      var deferRemaining = service.scheduledAtMs() - Date.now()
      if (service.lastError !== "" || service.failureNotified
          || deferRemaining < 5000 - 2000 || deferRemaining > 5000) {
        root.fail("an offline automatic update was treated as a visible failure: " + deferRemaining)
        return
      }
      service.pendingStartupTrigger = "first-run"
      service.cancelQueuedFirstRun()
      service.startupResolved = false
      service.currentWallpaper = ({})
      service.resolveStartup(false)
      if (service.pendingStartupTrigger !== "first-run") {
        root.fail("a missing wallpaper did not queue first-run")
        return
      }
      service.loadState('{"path":"/tmp/existing-wallpaper.jpg","changedAt":"2026-08-19T08:22:47Z"}')
      if (service.pendingStartupTrigger !== "") {
        root.fail("a late wallpaper load did not cancel first-run")
        return
      }
      service.pendingStartupTrigger = "first-run"
      if (service.consumePendingStartupTrigger() !== "") {
        root.fail("first-run still fired after a wallpaper was present")
        return
      }
      service.currentWallpaper = ({})
      service.pendingStartupTrigger = "first-run"
      if (service.consumePendingStartupTrigger() !== "first-run") {
        root.fail("true first-run was cancelled")
        return
      }
      service.retryAfterMs = 0
      service.deferCount = 0
      service.lastError = ""
      service.lastTrigger = ""
      service.loadState('{"path":"/tmp/existing-wallpaper.jpg","changedAt":"'
        + new Date().toISOString() + '"}')

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
      if (service.setIntervalMinutes("0") !== "0" || service.intervalMinutes !== 0) {
        root.fail("manual interval was not persisted")
        return
      }
      service.lastTrigger = "first-run"
      service.retryAfterMs = 0
      service.deferCount = 0
      service.processDeferred()
      var manualRetryRemaining = service.scheduledAtMs() - Date.now()
      if (manualRetryRemaining < 5000 - 2000 || manualRetryRemaining > 5000
          || service.statusPayload().nextRunAt === null) {
        root.fail("manual mode dropped an automatic offline retry: " + manualRetryRemaining)
        return
      }
      service.retryAfterMs = 0
      service.lastTrigger = ""
      service.armSchedule()

      confirmTimer.start()
    }
  }

  Timer {
    id: confirmTimer
    interval: 1300
    repeat: false
    onTriggered: {
      var service = serviceLoader.item
      if (service.lastTrigger !== "" || service.running) {
        root.fail("existing wallpaper triggered an automatic refresh: trigger="
          + service.lastTrigger)
        return
      }

      console.log("service schedule tests passed")
      root.finished = true
      Qt.quit()
    }
  }

  Timer {
    interval: 4000
    running: true
    repeat: false
    onTriggered: if (!root.finished) root.fail("test timed out")
  }
}
