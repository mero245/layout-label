# mero.layout-label

A bar widget that shows the active xkb keyboard layout as a short, customizable label and cycles layouts on click.

## Install

```bash
omarchy plugin add <your-repo-url> --enable
```

Or add it directly into the bar:

```bash
omarchy bar add mero.layout-label
```

## Settings

All settings are optional and come with the defaults below. Change them in the bar widget settings panel or as inline keys on the bar entry.

| Key          | Type   | Default        | Description |
| ------------ | ------ | -------------- | ----------- |
| `labels`     | object | `{}`           | Per-layout display label overrides. Keys are full xkb layout descriptions (`"English (US)"`, `"English (Colemak)"`), values are the strings shown on the bar. |

Example inline settings on the bar entry:

```json
{
  "id": "mero.layout-label",
  "labels": {
    "English (Colemak)": "Colemak"
  }
}
```

Right-clicking the label opens a card with a **Layout** picker and a **Label** field. The picker lists every layout the keyboard is set to, so a layout can be named without switching to it. The card keeps editing the layout it opened on even if the keyboard layout changes while it is up. **Clear** removes the selected layout's override; **Reset labels** forgets every override.

## Behavior

- **Left-click** the label: cycles to the next xkb layout on the current keyboard.
- **Right-click** the label: opens the settings card to name a layout.
- Automatically discovers the keyboard being typed on; does not switch layouts for the mouse/trackpoint.

## Compatibility & limits

- Requires Hyprland (`switchxkblayout` is a hyprctl command).
- If only one xkb layout is installed, the widget stays hidden by default.

## Development

- `omarchy plugin validate ./mero.layout-label` — manifest schema check.
- Files under `~/.config/omarchy/plugins/` hot-reload on save.
