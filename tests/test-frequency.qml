import QtQuick
import Quickshell

ShellRoot {
  id: root

  property bool finished: false
  property double chosenAt: 0
  property double nextRun: 0
  property double changedAt: 0

  function fail(message) {
    console.error("TEST FAILURE:", message)
    finished = true
    Qt.quit()
  }

  QtObject {
    id: fakeShell

    property var barConfig: ({layout: {right: [{
      id: "io.github.orienw.fresh-wallpaper",
      intervalMinutes: 1440,
      runOnStart: false
    }]}})

    function updateEntryInline(pluginId, settings) {
      var entry = {id: pluginId}
      for (var key in settings) entry[key] = settings[key]
      barConfig = {layout: {right: [entry]}}
      return true
    }
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
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      if (!service || !service.initialized) return
      stop()
      root.changedAt = service.lastChangeMs()
      root.chosenAt = Date.now()
      service.setIntervalMinutes("60")
      root.nextRun = service.nextChangeAtMs
      confirmTimer.start()
    }
  }

  Timer {
    id: confirmTimer
    interval: 200
    onTriggered: {
      var service = serviceLoader.item
      if (service.lastTrigger !== "" || service.running) {
        root.fail("choosing a shorter frequency started a fetch")
        return
      }
      if (root.nextRun < root.chosenAt + 60 * 60000
          || root.nextRun > Date.now() + 60 * 60000) {
        root.fail("an overdue chosen interval did not count from the choice")
        return
      }
      service.setIntervalMinutes("60")
      if (service.nextChangeAtMs !== root.nextRun) {
        root.fail("choosing the same frequency moved the schedule")
        return
      }
      var savedConfig = fakeShell.barConfig
      fakeShell.barConfig = ({})
      fakeShell.barConfig = savedConfig
      if (service.nextChangeAtMs !== root.nextRun) {
        root.fail("reloading settings moved the chosen interval's schedule")
        return
      }
      service.setIntervalMinutes("1440")
      if (service.nextChangeAtMs !== root.changedAt + 1440 * 60000) {
        root.fail("Daily after Custom did not count from the real last change")
        return
      }
      service.setIntervalMinutes("60")
      service.processSucceeded()
      if (service.nextChangeAtMs !== service.lastSuccessMs + 60 * 60000) {
        root.fail("a successful change did not supersede the chosen interval's origin")
        return
      }

      // Both Manual and Weekly can become Daily with an already old wallpaper.
      service.lastSuccessMs = 0
      service.currentWallpaper = {
        path: Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE"),
        changedAt: new Date(Date.now() - 3 * 86400000).toISOString()
      }
      var previousIntervals = ["0", "10080"]
      for (var i = 0; i < previousIntervals.length; i++) {
        service.setIntervalMinutes(previousIntervals[i])
        var now = Date.now()
        service.setIntervalMinutes("1440")
        if (service.nextChangeAtMs < now + 86400000
            || service.nextChangeAtMs > Date.now() + 86400000) {
          root.fail("switching from " + previousIntervals[i] + " to overdue Daily was due immediately")
          return
        }
      }

      // Simulate time passing during sleep without an explicit interval change.
      service.setIntervalMinutes("10080")
      service.currentWallpaper = {
        path: Quickshell.env("FRESH_WALLPAPER_TEST_IMAGE"),
        changedAt: new Date(Date.now() - 8 * 86400000).toISOString()
      }
      var due = service.nextChangeAtMs
      service.setIntervalMinutes("10080")
      if (service.nextChangeAtMs !== due || due > Date.now()) {
        root.fail("reselecting a due frequency deferred its change")
        return
      }
      service.checkSchedule()
      if (service.lastTrigger !== "schedule") {
        root.fail("a change due during sleep did not start")
        return
      }
      settleTimer.start()
    }
  }

  Timer {
    id: settleTimer
    interval: 25
    repeat: true
    onTriggered: {
      var service = serviceLoader.item
      if (service.running) return
      stop()
      console.log("service frequency tests passed")
      root.finished = true
      Qt.quit()
    }
  }

  Timer {
    interval: 4000
    running: true
    onTriggered: if (!root.finished) root.fail("frequency test timed out")
  }
}
