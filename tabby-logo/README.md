# Tabby — Logo Assets

Three SVG files ready to drop into your Xcode project.

## Files

### `tabby-logo.svg` (512×512)
The main brand mark. Full color, with cream circular background.
**Use for:** Website, landing page, About screen, marketing.

### `tabby-menubar.svg` (22×22)
Minimal monochrome silhouette designed for the macOS menu bar.
Uses `currentColor`, so it automatically adapts to light/dark mode.
**Use for:** The `NSStatusItem` icon in your status bar.

### `tabby-app-icon.svg` (1024×1024)
Rounded-square app icon following Apple's icon dimensions.
**Use for:** Generating the `.icns` file for your Applications folder icon.

## Generating the .icns file (for Xcode)

1. Open `tabby-app-icon.svg` in any editor (Figma, Sketch, or even Preview)
2. Export PNGs at these sizes: 16, 32, 64, 128, 256, 512, 1024
3. Use the `iconutil` command or a tool like Image2Icon to bundle them into `.icns`

Or use this Terminal one-liner once you have the PNGs in a folder called `tabby.iconset/`:
```bash
iconutil -c icns tabby.iconset
```

## Color palette

- **Cream background:** `#F4EBE0`
- **Tabby orange:** `#D97757`
- **Deep brown (outlines/text):** `#2a1810`

Keep these consistent across the app for a cohesive look.
