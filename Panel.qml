import QtQuick
import qs.Commons
import qs.Ui

// qmllint disable missing-property

Panel {
  id: root
  moduleName: "io.github.orienw.fresh-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int cursorIndex: 0
  property bool customIntervalRequested: false
  property int customIntervalDraft: 60
  property double nowMs: Date.now()

  readonly property var barIdentity: hostWidget || root
  readonly property var wallpaperService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property var currentWallpaper: wallpaperService
    ? wallpaperService.currentWallpaper
    : ({})
  readonly property string externalBackgroundPath: wallpaperService
    ? String(wallpaperService.externalBackgroundPath || "")
    : ""
  readonly property bool showingExternalBackground: externalBackgroundPath !== ""
  readonly property string previewPath: showingExternalBackground
    ? externalBackgroundPath
    : wallpaperService ? String(wallpaperService.previewWallpaperPath || "") : ""
  readonly property bool previewPlaceholderVisible: previewImage.status !== Image.Ready
  readonly property bool busy: wallpaperService ? wallpaperService.running : false
  readonly property string learnMoreUrl: showingExternalBackground
    ? ""
    : bingLink(currentWallpaper.copyrightLink)
  readonly property bool previousAvailable: wallpaperService
    ? wallpaperService.previousAvailable === true
    : false
  readonly property double nextChangeAtMs: wallpaperService ? Number(wallpaperService.nextChangeAtMs || 0) : 0
  readonly property bool retryPending: wallpaperService ? Number(wallpaperService.retryAfterMs || 0) > 0 : false
  readonly property string errorText: wallpaperService ? wallpaperService.lastError : ""
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int configuredInterval: wallpaperService
    ? wallpaperService.intervalMinutes
    : 1440
  readonly property bool intervalIsPreset: [0, 1440, 10080, 43200]
    .indexOf(configuredInterval) !== -1
  readonly property bool customIntervalVisible: customIntervalRequested || !intervalIsPreset
  readonly property int previousCursorIndex: 1
  readonly property int learnMoreCursorIndex: 2
  readonly property int sourceCursorIndex: 3
  readonly property int frequencyCursorIndex: sourceCursorIndex + 1
  readonly property int customCursorIndex: frequencyCursorIndex + 1
  readonly property int marketCursorIndex: customIntervalVisible ? customCursorIndex + 1 : customCursorIndex
  readonly property int startupCursorIndex: marketCursorIndex + 1
  readonly property var frequencyOptions: [
    { value: "0", label: "Manual only" },
    { value: "1440", label: "Daily" },
    { value: "10080", label: "Weekly" },
    { value: "43200", label: "Monthly (30 days)" },
    { value: "custom", label: "Custom minutes..." }
  ]
  readonly property var marketOptions: [
    { value: "en-US", label: "United States" },
    { value: "en-GB", label: "United Kingdom" },
    { value: "en-CA", label: "Canada" },
    { value: "en-AU", label: "Australia" },
    { value: "de-DE", label: "Germany" },
    { value: "fr-FR", label: "France" },
    { value: "ja-JP", label: "Japan" }
  ]

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function cursorEnabled(index) {
    if (index === previousCursorIndex) return previousAvailable
    if (index === learnMoreCursorIndex) return learnMoreUrl !== ""
    return true
  }

  function moveCursor(delta) {
    var next = cursorIndex + delta
    while (next > 0 && next < startupCursorIndex && !cursorEnabled(next)) next += delta
    cursorIndex = Math.max(0, Math.min(startupCursorIndex, next))
  }

  // Bing's attribution links point at a Bing search about the photo. Older
  // archive responses used site-relative links.
  function bingLink(value) {
    var link = String(value || "")
    if (/^\/[^\/]/.test(link)) link = "https://www.bing.com" + link
    return /^https:\/\/([a-z0-9-]+\.)*bing\.com\//i.test(link) ? link : ""
  }

  function openLearnMore() {
    if (learnMoreUrl === "") return
    Qt.openUrlExternally(learnMoreUrl)
    close()
  }

  function restorePrevious() {
    if (wallpaperService && previousAvailable && !busy) wallpaperService.startPrevious()
  }

  function selectFrequency(value) {
    if (!wallpaperService) return "error: plugin is not ready"

    if (value === "custom") {
      customIntervalDraft = intervalIsPreset ? 60 : configuredInterval
      var customResult = wallpaperService.setIntervalMinutes(customIntervalDraft)
      if (String(customResult).indexOf("error:") === 0) return customResult
      customIntervalRequested = true
      Qt.callLater(function() { customIntervalField.field.forceActiveFocus() })
      return customResult
    }

    var result = wallpaperService.setIntervalMinutes(value)
    if (String(result).indexOf("error:") !== 0) customIntervalRequested = false
    return result
  }

  function setCustomInterval(value) {
    if (!wallpaperService) return "error: plugin is not ready"
    var minutes = Math.floor(Number(value))
    customIntervalDraft = minutes
    var result = wallpaperService.setIntervalMinutes(value)
    if (String(result).indexOf("error:") !== 0)
      customIntervalRequested = [0, 1440, 10080, 43200].indexOf(minutes) === -1
    return result
  }

  function activateCursor() {
    if (cursorIndex === 0 && wallpaperService && !busy) wallpaperService.startRefresh("panel")
    else if (cursorIndex === previousCursorIndex) restorePrevious()
    else if (cursorIndex === learnMoreCursorIndex) openLearnMore()
    else if (cursorIndex === sourceCursorIndex) providerDropdown.toggle()
    else if (cursorIndex === frequencyCursorIndex) frequencyDropdown.toggle()
    else if (customIntervalVisible && cursorIndex === customCursorIndex)
      customIntervalField.field.forceActiveFocus()
    else if (cursorIndex === marketCursorIndex) marketDropdown.toggle()
    else if (cursorIndex === startupCursorIndex && wallpaperService)
      wallpaperService.setRunOnStart(wallpaperService.runOnStart ? "false" : "true")
  }

  function changedLabel(value) {
    if (!value) return "Waiting for the first wallpaper"
    var changed = new Date(String(value))
    if (isNaN(changed.getTime())) return "Wallpaper ready"
    return "Changed " + Qt.formatDateTime(changed, "MMM d, h:mm AP")
  }

  function nextChangeLabel() {
    if (nextChangeAtMs <= 0) return ""
    var minutes = Math.max(1, Math.round((nextChangeAtMs - nowMs) / 60000))
    var remaining = minutes < 60 ? minutes + " min"
      : minutes < 48 * 60 ? Math.round(minutes / 60) + "h"
      : Math.round(minutes / 1440) + " days"
    return (retryPending ? "Retrying in " : "Next change in ") + remaining
  }

  onOpenedChanged: if (opened && wallpaperService) wallpaperService.refreshStatus()
  onConfiguredIntervalChanged: {
    if (configuredInterval > 0) customIntervalDraft = configuredInterval
    if (intervalIsPreset) customIntervalRequested = false
  }
  onStartupCursorIndexChanged: cursorIndex = Math.min(cursorIndex, startupCursorIndex)

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: providerDropdown.popupOpen
        || frequencyDropdown.popupOpen
        || marketDropdown.popupOpen
        || (root.customIntervalVisible && customIntervalField.field.activeFocus)
      onMoveRequested: function(dx, dy) {
        var delta = dy !== 0 ? dy : dx
        if (delta !== 0) root.moveCursor(delta)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(12)

          BorderSurface {
            width: Style.space(112)
            height: Style.space(63)
            anchors.verticalCenter: parent.verticalCenter
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            clip: true

            Image {
              id: previewImage
              anchors.fill: parent
              source: Util.fileUrl(root.previewPath)
              sourceSize: Qt.size(width * 2, height * 2)
              asynchronous: true
              cache: false
              fillMode: Image.PreserveAspectCrop
              visible: !root.previewPlaceholderVisible
            }

            Text {
              anchors.centerIn: parent
              visible: root.previewPlaceholderVisible
              text: ""
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
          }

          Column {
            width: parent.width - Style.space(124)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: root.showingExternalBackground
                ? "Another background"
                : root.currentWallpaper.title || "Fresh Wallpaper"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.busy
                ? "Finding a fresh image..."
                : (root.showingExternalBackground
                  ? "Set outside Fresh Wallpaper"
                  : root.changedLabel(root.currentWallpaper.changedAt))
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: root.busy ? "" : root.nextChangeLabel()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: "BING DAILY  ·  " + (root.wallpaperService ? root.wallpaperService.market : "en-US")
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
              elide: Text.ElideRight
            }
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: root.showingExternalBackground ? "" : root.currentWallpaper.copyright || ""
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          visible: root.errorText !== ""
          width: parent.width
          text: root.errorText
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            id: changeButton
            width: parent.width - previousButton.width - learnMoreButton.width - parent.spacing * 2
            text: root.busy ? "Changing wallpaper..." : "Change now"
            iconText: "󰑐"
            iconSpinning: root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            focusable: true
            enabled: root.wallpaperService && !root.busy
            hasCursor: root.cursorIndex === 0
            onHovered: function(hovered) { if (hovered) root.cursorIndex = 0 }
            onClicked: if (root.wallpaperService) root.wallpaperService.startRefresh("panel")
          }

          PanelActionButton {
            id: previousButton
            size: changeButton.height
            iconText: "󰕌"
            tooltipText: "Previous wallpaper"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.previousAvailable && !root.busy
            hasCursor: root.cursorIndex === root.previousCursorIndex
            onHovered: function(hovered) { if (hovered) root.cursorIndex = root.previousCursorIndex }
            onClicked: root.restorePrevious()
          }

          PanelActionButton {
            id: learnMoreButton
            size: changeButton.height
            iconText: "󰋽"
            tooltipText: "Learn about this image"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.learnMoreUrl !== ""
            hasCursor: root.cursorIndex === root.learnMoreCursorIndex
            onHovered: function(hovered) { if (hovered) root.cursorIndex = root.learnMoreCursorIndex }
            onClicked: root.openLearnMore()
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        PanelSectionHeader {
          text: "SETTINGS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Dropdown {
          id: providerDropdown
          width: parent.width
          label: "Source"
          value: root.wallpaperService ? root.wallpaperService.provider : "bing"
          options: [
            { value: "bing", label: "Bing Daily (UHD)" }
          ]
          foreground: root.foreground
          fontFamily: root.fontFamily
          hasCursor: root.cursorIndex === root.sourceCursorIndex
          onHovered: function(hovered) { if (hovered) root.cursorIndex = root.sourceCursorIndex }
          onChanged: function(value) {
            if (root.wallpaperService) root.wallpaperService.setProvider(value)
          }
        }

        Dropdown {
          id: frequencyDropdown
          width: parent.width
          label: "Frequency"
          value: root.customIntervalVisible ? "custom" : String(root.configuredInterval)
          options: root.frequencyOptions
          foreground: root.foreground
          fontFamily: root.fontFamily
          hasCursor: root.cursorIndex === root.frequencyCursorIndex
          onHovered: function(hovered) { if (hovered) root.cursorIndex = root.frequencyCursorIndex }
          onChanged: function(value) { root.selectFrequency(value) }
        }

        NumberField {
          id: customIntervalField
          visible: root.customIntervalVisible
          width: parent.width
          label: "Custom interval (minutes)"
          from: 15
          to: 525600
          stepSize: 15
          value: root.customIntervalRequested && root.intervalIsPreset
            ? root.customIntervalDraft
            : root.configuredInterval
          foreground: root.foreground
          fontFamily: root.fontFamily
          hasCursor: root.customIntervalVisible && root.cursorIndex === root.customCursorIndex
          onHovered: function(hovered) { if (hovered) root.cursorIndex = root.customCursorIndex }
          onModified: function(value) {
            root.setCustomInterval(value)
          }
        }

        Dropdown {
          id: marketDropdown
          width: parent.width
          label: "Region"
          value: root.wallpaperService ? root.wallpaperService.market : "en-US"
          options: root.marketOptions
          foreground: root.foreground
          fontFamily: root.fontFamily
          hasCursor: root.cursorIndex === root.marketCursorIndex
          onHovered: function(hovered) { if (hovered) root.cursorIndex = root.marketCursorIndex }
          onChanged: function(value) {
            if (root.wallpaperService) root.wallpaperService.setMarket(value)
          }
        }

        Toggle {
          width: parent.width
          label: "Change on start"
          description: "Force a new image whenever the Omarchy shell loads."
          checked: root.wallpaperService ? root.wallpaperService.runOnStart : false
          foreground: root.foreground
          fontFamily: root.fontFamily
          hasCursor: root.cursorIndex === root.startupCursorIndex
          onHovered: function(hovered) { if (hovered) root.cursorIndex = root.startupCursorIndex }
          onClicked: {
            if (root.wallpaperService)
              root.wallpaperService.setRunOnStart(root.wallpaperService.runOnStart ? "false" : "true")
          }
        }
      }
    }
  }
}
// qmllint enable missing-property
