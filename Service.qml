import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "io.github.orienw.fresh-wallpaper"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : ""
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string statePath: stateHome + "/omarchy/fresh-wallpaper/current.json"

  readonly property var settings: findSettings()

  function findSettings() {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var layout = config && config.bar && config.bar.layout ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var widgets = layout && Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var w = 0; w < widgets.length; w++) {
        if (widgets[w] && String(widgets[w].id || "") === pluginId) return widgets[w]
      }
    }

    var entries = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && String(entries[i].id || "") === pluginId) return entries[i]
    }
    return ({})
  }

  readonly property string provider: String(setting("provider", "bing")).trim().toLowerCase()
  readonly property string market: String(setting("market", "en-US")).trim()
  readonly property int intervalMinutes: normalizedInterval(setting("intervalMinutes", 1440))
  readonly property bool runOnStart: boolSetting("runOnStart", false)
  readonly property int cacheLimit: intSetting("cacheLimit", 30, 8, 100)

  property bool initialized: false
  property var currentWallpaper: ({})
  property string lastError: ""
  property string lastTrigger: ""
  property int consecutiveFailures: 0
  property bool failureNotified: false
  property double scheduleOriginMs: 0
  property double retryAfterMs: 0
  property bool startupResolved: false
  property string pendingStartupTrigger: ""
  readonly property bool running: fetchProcess.running
  readonly property double scheduleChunkMs: 3600000

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = Math.floor(Number(setting(name, fallback)))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    var normalized = String(value).trim().toLowerCase()
    if (["true", "1", "on", "yes"].indexOf(normalized) !== -1) return true
    if (["false", "0", "off", "no"].indexOf(normalized) !== -1) return false
    return fallback
  }

  function normalizedInterval(value) {
    var minutes = Math.floor(Number(value))
    if (!isFinite(minutes)) return 1440
    if (minutes === 0) return 0
    return Math.max(15, Math.min(525600, minutes))
  }

  function initialize() {
    if (initialized || !shell || sourceDir === "") return
    initialized = true
    scheduleOriginMs = Date.now()
    stateFile.reload()
  }

  function initialRefreshTrigger(hasWallpaper, changeOnStart) {
    if (changeOnStart) return "startup"
    return hasWallpaper ? "" : "first-run"
  }

  function resolveStartup(hasWallpaper) {
    if (!initialized || startupResolved) return
    startupResolved = true
    armSchedule()

    pendingStartupTrigger = initialRefreshTrigger(hasWallpaper, runOnStart)
    if (pendingStartupTrigger !== "") startupTimer.start()
  }

  function lastChangeMs() {
    var changed = currentWallpaper ? Date.parse(String(currentWallpaper.changedAt || "")) : NaN
    return isFinite(changed) ? changed : scheduleOriginMs
  }

  function scheduledAtMs() {
    if (intervalMinutes <= 0) return 0
    if (retryAfterMs > 0) return retryAfterMs
    return lastChangeMs() + intervalMinutes * 60000
  }

  function armSchedule() {
    scheduleTimer.stop()
    if (!initialized || intervalMinutes <= 0) return

    var remaining = scheduledAtMs() - Date.now()
    scheduleTimer.interval = Math.max(1, Math.min(scheduleChunkMs, Math.ceil(remaining)))
    scheduleTimer.start()
  }

  function checkSchedule() {
    if (!initialized || intervalMinutes <= 0) return
    if (fetchProcess.running) {
      scheduleTimer.interval = 60000
      scheduleTimer.start()
      return
    }
    if (Date.now() >= scheduledAtMs()) startRefresh(retryAfterMs > 0 ? "retry" : "schedule")
    else armSchedule()
  }

  function startRefresh(trigger) {
    if (!initialized || sourceDir === "") return "not ready"
    if (fetchProcess.running) return "already running"

    lastTrigger = trigger
    lastError = ""
    fetchProcess.command = [
      "bash",
      sourceDir + "/scripts/fetch-wallpaper",
      "--provider", provider,
      "--market", market,
      "--cache-limit", String(cacheLimit)
    ]
    fetchProcess.running = true
    return "started"
  }

  function loadState(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      resolveStartup(false)
      armSchedule()
      return
    }

    var hasWallpaper = false
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") {
        currentWallpaper = parsed
        hasWallpaper = String(parsed.path || "").trim() !== ""
      }
    } catch (error) {
      console.warn("fresh-wallpaper: could not parse state:", error)
    }
    resolveStartup(hasWallpaper)
    armSchedule()
  }

  function processSucceeded(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim())
      currentWallpaper = parsed
      lastError = ""
      consecutiveFailures = 0
      failureNotified = false
      retryAfterMs = 0
      stateFile.reload()
      armSchedule()
    } catch (error) {
      processFailed("fetch helper returned invalid JSON")
    }
  }

  function shouldNotifyFailure() {
    var quietInitialFailure = consecutiveFailures === 1
      && (lastTrigger === "first-run" || lastTrigger === "startup")
    return !quietInitialFailure && !failureNotified
  }

  function processFailed(message) {
    var detail = String(message || "Fresh Wallpaper could not update the background.")
      .replace(/\s+/g, " ").trim()
    if (detail.length > 240) detail = detail.substring(0, 237) + "..."
    lastError = detail
    consecutiveFailures++
    retryAfterMs = Date.now() + 15 * 60000
    armSchedule()
    console.warn("fresh-wallpaper:", detail)

    if (shouldNotifyFailure() && !notificationProcess.running) {
      notificationProcess.command = [
        "omarchy-notification-send",
        "Fresh Wallpaper",
        detail
      ]
      failureNotified = true
      notificationProcess.running = true
    }
  }

  function persistSetting(name, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    if (settings && settings[name] !== undefined
        && JSON.stringify(settings[name]) === JSON.stringify(value)) return true
    var next = ({})
    for (var key in settings) if (key !== "id") next[key] = settings[key]
    next[name] = value
    return shell.updateEntryInline(pluginId, next) === true
  }

  function setProvider(value) {
    var normalized = String(value || "").trim().toLowerCase()
    if (normalized !== "bing") return "error: supported providers: bing"
    if (!persistSetting("provider", normalized)) return "error: setting could not be saved"
    return normalized
  }

  function setIntervalMinutes(value) {
    var minutes = Math.floor(Number(value))
    if (!isFinite(minutes) || minutes < 0 || (minutes > 0 && minutes < 15) || minutes > 525600)
      return "error: interval must be 0 or 15-525600 minutes"
    if (!persistSetting("intervalMinutes", minutes)) return "error: setting could not be saved"
    return String(minutes)
  }

  function setMarket(value) {
    var normalized = normalizeMarket(value)
    if (normalized === "") return "error: market must look like en-US"
    if (!persistSetting("market", normalized)) return "error: setting could not be saved"
    return normalized
  }

  function setRunOnStart(value) {
    var normalized = String(value || "").trim().toLowerCase()
    var enabled
    if (["true", "1", "on", "yes"].indexOf(normalized) !== -1) enabled = true
    else if (["false", "0", "off", "no"].indexOf(normalized) !== -1) enabled = false
    else return "error: run-on-start must be true or false"
    if (!persistSetting("runOnStart", enabled)) return "error: setting could not be saved"
    return enabled ? "true" : "false"
  }

  function setCacheLimit(value) {
    var limit = Math.floor(Number(value))
    if (!isFinite(limit) || limit < 8 || limit > 100)
      return "error: cache limit must be 8-100 wallpapers"
    if (!persistSetting("cacheLimit", limit)) return "error: setting could not be saved"
    return String(limit)
  }

  function normalizeMarket(value) {
    var parts = String(value || "").trim().split("-")
    if (parts.length !== 2) return ""
    if (!/^[A-Za-z]{2,3}$/.test(parts[0]) || !/^[A-Za-z]{2}$/.test(parts[1])) return ""
    return parts[0].toLowerCase() + "-" + parts[1].toUpperCase()
  }

  function statusPayload() {
    var nextRunAt = intervalMinutes > 0 ? new Date(scheduledAtMs()).toISOString() : null
    return {
      provider: provider,
      market: market,
      intervalMinutes: intervalMinutes,
      runOnStart: runOnStart,
      cacheLimit: cacheLimit,
      running: fetchProcess.running,
      nextRunAt: nextRunAt,
      lastTrigger: lastTrigger,
      lastError: lastError,
      current: currentWallpaper
    }
  }

  onManifestChanged: Qt.callLater(initialize)
  onShellChanged: Qt.callLater(initialize)
  onIntervalMinutesChanged: Qt.callLater(armSchedule)
  Component.onCompleted: Qt.callLater(initialize)

  Timer {
    id: startupTimer
    interval: 250
    repeat: false
    onTriggered: root.startRefresh(root.pendingStartupTrigger)
  }

  Timer {
    id: scheduleTimer
    repeat: false
    onTriggered: root.checkSchedule()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.resolveStartup(false)
    onFileChanged: reload()
  }

  Process {
    id: fetchProcess

    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
    }

    // qmllint disable signal-handler-parameters
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0) root.processSucceeded(fetchStdout.text)
      else root.processFailed(fetchStderr.text || "Wallpaper update failed with exit code " + exitCode)
    }
    // qmllint enable signal-handler-parameters
  }

  Process { id: notificationProcess }

  IpcHandler {
    target: "fresh-wallpaper"

    function status(): string {
      return JSON.stringify(root.statusPayload())
    }

    function refresh(): string {
      return root.startRefresh("manual")
    }

    function setProvider(value: string): string {
      return root.setProvider(value)
    }

    function setIntervalMinutes(value: string): string {
      return root.setIntervalMinutes(value)
    }

    function setMarket(value: string): string {
      return root.setMarket(value)
    }

    function setRunOnStart(value: string): string {
      return root.setRunOnStart(value)
    }

    function setCacheLimit(value: string): string {
      return root.setCacheLimit(value)
    }
  }
}
