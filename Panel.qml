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

  readonly property var barIdentity: hostWidget || root
  readonly property var wallpaperService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property var currentWallpaper: wallpaperService
    ? wallpaperService.currentWallpaper
    : ({})
  readonly property string previewPath: String(currentWallpaper.path || "")
  readonly property bool previewPlaceholderVisible: previewPath === ""
  readonly property bool busy: wallpaperService ? wallpaperService.running : false
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
  readonly property int marketCursorIndex: customIntervalVisible ? 4 : 3
  readonly property int startupCursorIndex: customIntervalVisible ? 5 : 4
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

  function moveCursor(delta) {
    cursorIndex = Math.max(0, Math.min(startupCursorIndex, cursorIndex + delta))
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
    else if (cursorIndex === 1) providerDropdown.toggle()
    else if (cursorIndex === 2) frequencyDropdown.toggle()
    else if (customIntervalVisible && cursorIndex === 3) customIntervalField.field.forceActiveFocus()
    else if (cursorIndex === marketCursorIndex) marketDropdown.toggle()
    else if (cursorIndex === startupCursorIndex && wallpaperService)
      wallpaperService.setRunOnStart(wallpaperService.runOnStart ? "false" : "true")
  }

  function previewSource(path) {
    var value = String(path || "")
    return value === "" ? "" : "file://" + encodeURI(value)
  }

  function changedLabel(value) {
    if (!value) return "Waiting for the first wallpaper"
    var changed = new Date(String(value))
    if (isNaN(changed.getTime())) return "Wallpaper ready"
    return "Changed " + Qt.formatDateTime(changed, "MMM d, h:mm AP")
  }

  onConfiguredIntervalChanged: {
    if (configuredInterval > 0) customIntervalDraft = configuredInterval
    if (intervalIsPreset) customIntervalRequested = false
  }
  onStartupCursorIndexChanged: cursorIndex = Math.min(cursorIndex, startupCursorIndex)

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
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            clip: true

            Image {
              id: previewImage
              anchors.fill: parent
              source: root.previewSource(root.previewPath)
              asynchronous: true
              cache: false
              fillMode: Image.PreserveAspectCrop
              visible: !root.previewPlaceholderVisible
            }

            Text {
              anchors.centerIn: parent
              visible: root.previewPlaceholderVisible
              text: "󰸉"
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
              text: root.currentWallpaper.title || "Fresh Wallpaper"
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
                : root.changedLabel(root.currentWallpaper.changedAt)
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
          text: root.currentWallpaper.copyright || ""
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
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Button {
          width: parent.width
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
          hasCursor: root.cursorIndex === 1
          onHovered: function(hovered) { if (hovered) root.cursorIndex = 1 }
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
          hasCursor: root.cursorIndex === 2
          onHovered: function(hovered) { if (hovered) root.cursorIndex = 2 }
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
          hasCursor: root.customIntervalVisible && root.cursorIndex === 3
          onHovered: function(hovered) { if (hovered) root.cursorIndex = 3 }
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
