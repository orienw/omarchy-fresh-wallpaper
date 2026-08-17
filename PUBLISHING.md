# Publishing Fresh Wallpaper

Use this checklist when version 0.1.0 is ready for its first public release and omarchyplugins.com listing.

## Repository checks

1. Re-run all validation from the README on the exact release commit.
2. Install that commit through `omarchy plugin add`, then test the bar icon, panel controls, keyboard close, scheduled refresh, manual refresh, shell restart, disable, re-enable, and removal.
3. Confirm `manifest.json`, `README.md`, and `LICENSE` are at the public repository root.
4. Confirm the plugin ID `io.github.orienw.fresh-wallpaper` is still absent from the marketplace. Marketplace IDs are permanent.
5. Push the exact tested commit to `https://github.com/orienw/omarchy-fresh-wallpaper` and create the `v0.1.0` release.

Do not submit a preview unless it is an original screenshot or another asset you have permission to publish. A preview is optional, but a clean screenshot of the native settings panel would make the listing clearer.

## Suggested listing

- Title: `[Plugin]: Fresh Wallpaper`
- Category: `Appearance`
- Tags: `quickshell, system`
- Suggested missing tag: `wallpaper`
- Repository: `https://github.com/orienw/omarchy-fresh-wallpaper`

Maintainer notes:

> Omarchy service and bar panel that download JPEG wallpapers from Bing's homepage archive over HTTPS, cache them under XDG_CACHE_HOME, store rotation metadata under XDG_STATE_HOME, and apply them with `omarchy theme bg set`. Runtime dependencies are curl, jq, file, and GNU core utilities. No sudo or pkexec is required.

## Submission body

Before creating the issue, confirm every ownership and checklist statement is true. The marketplace requires explicit owner approval of the final issue body.

```markdown
### Repository URL

https://github.com/orienw/omarchy-fresh-wallpaper

### Category

Appearance

### Tags

quickshell, system

### Suggest a missing tag

wallpaper

### Maintainer notes

Omarchy service and bar panel that download JPEG wallpapers from Bing's homepage archive over HTTPS, cache them under XDG_CACHE_HOME, store rotation metadata under XDG_STATE_HOME, and apply them with `omarchy theme bg set`. Runtime dependencies are curl, jq, file, and GNU core utilities. No sudo or pkexec is required.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
```

After approval of that exact body, create the issue:

```sh
gh issue create \
  --repo HANCORE-linux/omarchy-plugin-marketplace \
  --title "[Plugin]: Fresh Wallpaper" \
  --body-file /tmp/omarchy-plugin-submission.md
```

Automated validation and the marketplace security baseline bind their result to the submitted commit. Do not move the release branch until those checks complete.
