# Fresh Wallpaper

Fresh Wallpaper is a wallpaper rotation plugin for Omarchy Quattro. It downloads a random unseen image from Bing's recent daily wallpaper collection and applies it through Omarchy's native background command.

Its small bar control opens a native configuration panel. The scheduler remains a headless service inside the Omarchy shell, with no standalone app or separate background process.

## Default behavior

- Adds a wallpaper control to the right side of the Omarchy bar.
- Downloads a UHD Bing wallpaper as soon as the plugin is enabled.
- Changes the wallpaper daily.
- Chooses an image not used yet from Bing's current eight-day archive.
- Starts a new random pass after all available images have been used, without immediately repeating the current image.
- Keeps the 30 newest downloads and preserves the current wallpaper when a request fails.
- Shows one failure notification per outage, then stays quiet until a successful update resets the failure state.

## Why Bing first

Bing is the best first provider for this small plugin: it needs no API key, publishes a curated landscape image every day, supplies attribution metadata, and currently serves a 3840x2160 UHD image. Its homepage archive is not a versioned public API, so a future Bing change may require a plugin update.

Other providers can be added behind the existing `provider` setting without changing the scheduler or Omarchy integration.

## Requirements

- Omarchy 4.0 or newer
- `curl`
- `jq`
- `file`
- GNU core utilities

These commands are included in a normal Omarchy installation. No sudo or pkexec is required.

## Install

```sh
omarchy plugin add https://github.com/orienw/omarchy-fresh-wallpaper.git --enable
```

Enabling adds the bar control and changes the wallpaper immediately using the defaults above.

## Use

Click the wallpaper icon to open the panel. The panel shows the current image and attribution, and lets you choose the source, frequency, region, and whether to change the wallpaper when Omarchy starts. Frequency defaults to Daily, with simple Manual, Weekly, and Monthly choices alongside it. Monthly means every 30 days.

Press **Change now** in the panel or middle-click the bar icon to apply another wallpaper immediately.

The shell commands remain available for shortcuts and automation:

```sh
omarchy-shell fresh-wallpaper refresh
```

Inspect the schedule, last result, image path, and Bing attribution:

```sh
omarchy-shell fresh-wallpaper status | jq
```

## Configure

Use the bar panel for normal configuration. Its primary frequency choices are Manual, Daily, Weekly, and Monthly. Select **Custom minutes...** to reveal the advanced interval field. Every change is saved to Omarchy's native shell configuration.

Use the commands below for scripting or values not offered as presets.

Set the interval in minutes. Use `0` for manual-only rotation or a value from 15 through 525,600:

```sh
omarchy-shell fresh-wallpaper setIntervalMinutes 360
```

Choose the Bing market used for the image collection and metadata:

```sh
omarchy-shell fresh-wallpaper setMarket en-GB
```

Control whether loading the plugin applies a wallpaper immediately:

```sh
omarchy-shell fresh-wallpaper setRunOnStart false
```

The provider setting is ready for future sources. Version 0.1 supports Bing:

```sh
omarchy-shell fresh-wallpaper setProvider bing
```

These commands persist settings in the plugin's existing entry in `~/.config/omarchy/shell.json`. The equivalent entry is:

```json
{
  "id": "io.github.orienw.fresh-wallpaper",
  "provider": "bing",
  "market": "en-US",
  "intervalMinutes": 1440,
  "runOnStart": true,
  "cacheLimit": 30
}
```

## Storage and network behavior

Fresh Wallpaper makes HTTPS requests to `www.bing.com`. It stores downloaded images under `${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/fresh-wallpaper/` and rotation metadata under `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/fresh-wallpaper/`.

The helper validates each response as a non-empty JPEG before changing the desktop. A failed request leaves the current Omarchy background untouched.

Bing images remain copyrighted by their respective owners. Use them as personal desktop wallpapers and inspect the preserved attribution with the status command.

## Remove

```sh
omarchy plugin remove io.github.orienw.fresh-wallpaper
```

Removal stops rotation and removes the plugin checkout. Downloaded wallpapers and metadata remain so an active background never becomes a broken path. To delete them too, first select another Omarchy background, then remove these two plugin-owned directories:

```sh
rm -r -- "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/fresh-wallpaper"
rm -r -- "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/fresh-wallpaper"
```

## Develop

Validate the plugin contract and QML entry points:

```sh
omarchy plugin validate .
tests/lint-qml
```

Run the downloader and scheduler tests without network access or desktop changes:

```sh
tests/test-fetch-wallpaper
tests/test-service
```

Probe the live Bing source without changing the wallpaper:

```sh
scripts/fetch-wallpaper --provider bing --market en-US --no-apply | jq
```

## License

Fresh Wallpaper is released under the MIT License. See [LICENSE](LICENSE).
