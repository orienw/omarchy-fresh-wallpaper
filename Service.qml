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
  readonly property string sourceDir: decodeURIComponent(String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string home: Quickshell.env("HOME")
  readonly property string helperPath: sourceDir + "/scripts/fetch-wallpaper"
  // Past the helper's lock, network, and download limits even if all of them max
  // out, about 20 minutes.
  property int fetchTimeoutSeconds: 1500
  property int statusTimeoutSeconds: 10
  // A status holds current.json, which the helper keeps under 256 KiB, and three paths.
  readonly property int statusMaxBytes: 278528
  property string currentBackgroundLink: home + "/.local/state/omarchy/current/background"
  // Both come from the helper's status, which only names files it can preview.
  property string externalBackgroundPath: ""
  property string previewWallpaperPath: ""

  property var settings: findSettings()

  function findSettings() {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var barConfig = shell && shell.barConfig ? shell.barConfig : (config ? config.bar : null)
    var layout = barConfig ? barConfig.layout : null
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
  property bool initializing: false
  property var currentWallpaper: ({})
  property string lastError: ""
  property string lastTrigger: ""
  property int consecutiveFailures: 0
  property bool failureNotified: false
  property double scheduleOriginMs: 0
  property double retryAfterMs: 0
  property string retryOrigin: ""
  property bool startupResolved: false
  property string pendingStartupTrigger: ""
  property int deferCount: 0
  property bool awaitingInitialState: false
  property double lastSuccessMs: 0
  property string fetchError: ""
  // recent.json is the record the helper's Previous trusts, so availability
  // follows it rather than current.json.
  property int recentCount: 0
  readonly property bool previousAvailable: recentCount > 1
  // A run counts until its status lands, so the panel never flashes the old wallpaper.
  property bool fetchSettling: false
  readonly property bool running: fetchProcess.running || fetchSettling
  readonly property double nextChangeAtMs: scheduledAtMs()
  readonly property double scheduleChunkMs: 60000

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
    if (initialized || initializing || !shell || sourceDir === "") return
    initializing = true
    awaitingInitialState = true
    scheduleOriginMs = Date.now()
    refreshStatus()
  }

  // Asks the helper for everything the service shows, so the shell never reads a
  // state file or a path one names. head caps what the shell collects. A request
  // while one runs queues a fresh one, so a result that predates a change is
  // never applied.
  function refreshStatus() {
    if (sourceDir === "") return
    statusProcess.command = [
      "timeout", String(statusTimeoutSeconds), "bash", "-c",
      'set -o pipefail; bash "$1" --status --background "$2" | head -c "$3"',
      "fresh-wallpaper", helperPath, currentBackgroundLink, String(statusMaxBytes + 1)
    ]
    if (statusProcess.running) statusProcess.queued = true
    else statusProcess.running = true
  }

  // An unreadable status counts as no saved wallpaper.
  function statusRead(raw) {
    var status = ({})
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") status = parsed
    } catch (error) {
      console.warn("fresh-wallpaper: could not read the wallpaper status")
    }
    var current = status.current && typeof status.current === "object" ? status.current : null
    if (current) currentWallpaper = current
    recentCount = Math.max(0, Math.floor(Number(status.recentCount)) || 0)
    previewWallpaperPath = String(status.wallpaper || "")
    externalBackgroundPath = String(status.external || "")
    fetchSettling = false

    if (!awaitingInitialState) {
      resolveStartup(hasCurrentWallpaper())
      return
    }
    // A saved wallpaper whose file is gone still counts while the desktop has a
    // background, which may have been chosen outside the plugin.
    awaitingInitialState = false
    finishInitialization(current !== null
      && (runOnStart || previewWallpaperPath !== "" || status.hasBackground === true))
  }

  function finishInitialization(hasWallpaper) {
    if (!hasWallpaper) currentWallpaper = ({})
    initialized = true
    initializing = false
    resolveStartup(hasWallpaper)
  }

  function initialRefreshTrigger(hasWallpaper, changeOnStart) {
    if (changeOnStart) return "startup"
    return hasWallpaper ? "" : "first-run"
  }

  function hasCurrentWallpaper() {
    return String((currentWallpaper && currentWallpaper.path) || "").trim() !== ""
  }

  function cancelPendingStartupTrigger() {
    startupTimer.stop()
    pendingStartupTrigger = ""
  }

  function cancelQueuedFirstRun() {
    if (pendingStartupTrigger !== "first-run") return
    cancelPendingStartupTrigger()
  }

  function consumePendingStartupTrigger() {
    var trigger = pendingStartupTrigger
    pendingStartupTrigger = ""
    if (trigger === "first-run" && hasCurrentWallpaper()) return ""
    return trigger
  }

  function isUserTrigger(trigger) {
    return trigger === "manual" || trigger === "panel" || trigger === "bar"
  }

  function networkWaitSeconds(trigger) {
    if (trigger === "retry") return 5
    if (isUserTrigger(trigger)) return 10
    return 60
  }

  function resolveStartup(hasWallpaper) {
    if (!initialized) return
    if (startupResolved) {
      if (hasWallpaper) cancelQueuedFirstRun()
      if (pendingStartupTrigger === "") armSchedule()
      return
    }
    startupResolved = true

    pendingStartupTrigger = initialRefreshTrigger(hasWallpaper, runOnStart)
    if (pendingStartupTrigger !== "") {
      startupTimer.start()
      return
    }
    armSchedule()
  }

  // A success counts as a change even before current.json is read back, so the
  // schedule never fires again on the previous wallpaper's time.
  function lastChangeMs() {
    var changed = currentWallpaper ? Date.parse(String(currentWallpaper.changedAt || "")) : NaN
    return Math.max(isFinite(changed) ? changed : scheduleOriginMs, lastSuccessMs)
  }

  function scheduledAtMs() {
    if (retryAfterMs > 0) return retryAfterMs
    if (intervalMinutes <= 0) return 0
    return lastChangeMs() + intervalMinutes * 60000
  }

  function armSchedule() {
    scheduleTimer.stop()
    if (!initialized || pendingStartupTrigger !== "") return

    var scheduled = scheduledAtMs()
    if (scheduled <= 0) return
    var remaining = scheduled - Date.now()
    scheduleTimer.interval = Math.max(1, Math.min(scheduleChunkMs, Math.ceil(remaining)))
    scheduleTimer.start()
  }

  function checkSchedule() {
    if (!initialized) return
    var scheduled = scheduledAtMs()
    if (scheduled <= 0) return
    if (fetchProcess.running) {
      scheduleTimer.interval = 60000
      scheduleTimer.start()
      return
    }
    if (Date.now() >= scheduled) startRefresh(retryAfterMs > 0 ? "retry" : "schedule")
    else armSchedule()
  }

  function startRefresh(trigger) {
    if (!initialized || sourceDir === "") return "not ready"
    if (fetchProcess.running) return "already running"

    cancelPendingStartupTrigger()
    return runHelper(trigger, [
      "--provider", provider,
      "--market", market,
      "--cache-limit", String(cacheLimit),
      "--network-wait-seconds", String(networkWaitSeconds(trigger))
    ])
  }

  function startPrevious() {
    if (!initialized || sourceDir === "") return "not ready"
    if (fetchProcess.running) return "already running"
    if (!previousAvailable) return "error: no previous wallpaper is available"
    return runHelper("previous", ["--previous"])
  }

  function runHelper(trigger, args) {
    lastTrigger = trigger
    lastError = ""
    fetchError = ""
    fetchProcess.command = [
      "timeout", "--kill-after=10", String(fetchTimeoutSeconds), "bash", helperPath
    ].concat(args)
    fetchProcess.running = true
    return "started"
  }

  function processSucceeded() {
    lastSuccessMs = Date.now()
    lastError = ""
    consecutiveFailures = 0
    failureNotified = false
    deferCount = 0
    retryAfterMs = 0
    retryOrigin = ""
    armSchedule()
  }

  function shouldNotifyFailure() {
    var quietInitialFailure = consecutiveFailures === 1
      && (lastTrigger === "first-run" || lastTrigger === "startup")
    return !quietInitialFailure && !failureNotified
  }

  function processDeferred() {
    deferCount++
    queueRetry(Math.min(15 * 60000, 5000 * Math.pow(2, deferCount - 1)))
    if (deferCount === 1) console.warn("fresh-wallpaper: waiting for network")
  }

  function queueRetry(delayMs) {
    if (lastTrigger !== "retry") retryOrigin = lastTrigger
    var allowed = intervalMinutes > 0
      || (retryOrigin !== "schedule" && !isUserTrigger(retryOrigin))
    retryAfterMs = allowed ? Date.now() + delayMs : 0
    armSchedule()
  }

  function processExited(exitCode) {
    if (exitCode === 124) fetchError = "Wallpaper update timed out"
    if (exitCode === 0) processSucceeded()
    else if (lastTrigger === "previous") lastError = errorDetail(fetchError)
    else if (exitCode === 75 && !isUserTrigger(lastTrigger)) processDeferred()
    else processFailed(fetchError || "Wallpaper update failed with exit code " + exitCode)
    // Even a failed run may have saved state before it stopped.
    fetchSettling = true
    refreshStatus()
  }

  // Keeps only the start of the helper's stderr, which is all errorDetail shows.
  function appendFetchError(data) {
    if (fetchError.length < 4096) fetchError += String(data).substring(0, 4096 - fetchError.length)
  }

  function errorDetail(message) {
    var detail = String(message || "Fresh Wallpaper could not update the background.")
      .replace(/\s+/g, " ").trim()
    return detail.length > 240 ? detail.substring(0, 237) + "..." : detail
  }

  function processFailed(message) {
    var detail = errorDetail(message)
    lastError = detail
    consecutiveFailures++
    queueRetry(15 * 60000)
    console.warn("fresh-wallpaper:", detail)

    if (shouldNotifyFailure() && !notificationProcess.running) {
      notificationProcess.command = [
        "timeout", "10", "omarchy-notification-send",
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
    var scheduled = scheduledAtMs()
    var nextRunAt = scheduled > 0 ? new Date(scheduled).toISOString() : null
    return {
      provider: provider,
      market: market,
      intervalMinutes: intervalMinutes,
      runOnStart: runOnStart,
      cacheLimit: cacheLimit,
      running: running,
      nextRunAt: nextRunAt,
      lastTrigger: lastTrigger,
      lastError: lastError,
      current: currentWallpaper
    }
  }

  onManifestChanged: Qt.callLater(initialize)
  onShellChanged: Qt.callLater(initialize)
  onIntervalMinutesChanged: {
    if (intervalMinutes === 0 && retryOrigin === "schedule") {
      retryAfterMs = 0
      deferCount = 0
    }
    Qt.callLater(armSchedule)
  }
  Component.onCompleted: Qt.callLater(initialize)

  Timer {
    id: startupTimer
    interval: 1
    repeat: false
    onTriggered: {
      var trigger = root.consumePendingStartupTrigger()
      if (trigger !== "") root.startRefresh(trigger)
    }
  }

  Timer {
    id: scheduleTimer
    repeat: false
    onTriggered: root.checkSchedule()
  }

  Process {
    id: statusProcess
    property bool queued: false

    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }

    // qmllint disable signal-handler-parameters
    onExited: function(exitCode) {
      if (queued) {
        queued = false
        running = true
        return
      }
      root.statusRead(exitCode === 0 && statusStdout.data.byteLength <= root.statusMaxBytes
        ? statusStdout.text : "")
    }
    // qmllint enable signal-handler-parameters
  }

  // The helper saves its result to current.json, which its status reports back,
  // so its stdout is discarded.
  Process {
    id: fetchProcess

    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.appendFetchError(data) }
    }

    // qmllint disable signal-handler-parameters
    onExited: function(exitCode, exitStatus) {
      root.processExited(exitCode)
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

    function previous(): string {
      return root.startPrevious()
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
