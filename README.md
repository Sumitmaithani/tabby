# Tabby

A minimalist macOS menu bar app for saving and accessing bookmarks, with local-only storage and multi-format export.

## Features

- **Menu bar icon** — lives quietly in the status bar; click to open
- **Quick-add** — paste a URL, auto-fetches page title and favicon
- **Instant search** — filter by title, URL, tag, or notes in real time
- **Tags with color labels** — create custom tags, filter by them
- **Sort options** — by date, alphabetical, most visited, or by tag
- **Global hotkey** — `⌘⇧L` summons or dismisses the panel from anywhere
- **Click tracking** — see how often you visit each bookmark
- **iCloud Drive sync** — optional, moves the data file into iCloud
- **Auto-backup** — keeps the last 5 backups, restorable from Settings
- **Multi-format export** — CSV, JSON, PDF, HTML (Netscape), Markdown
- **One-click browser import** — Chrome, Arc, Brave, Edge, Comet (requires Full Disk Access; DMG distribution, not Mac App Store)
- **File import** — CSV, JSON, or HTML bookmark exports (fallback)
- **Light/dark/system theme** — follows system or overridden in Settings
- **Compact/expanded view** — toggle in Settings
- **No internet required, no accounts, no telemetry**

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later

## Setup & Build

### 1. Open in Xcode

```
open Tabby.xcodeproj
```

Or double-click `Tabby.xcodeproj` in Finder.

### 2. Configure signing

Tabby is distributed **outside the Mac App Store** (signed + notarized DMG). App Sandbox is disabled so the app can read Chromium bookmark files after the user grants **Full Disk Access** in System Settings.

In Xcode:
1. Select the **Tabby** target in the Project Navigator
2. Open the **Signing & Capabilities** tab
3. Choose your **Team** (requires an Apple Developer account, or use "Sign to Run Locally" for testing without a Developer ID)
4. The Bundle Identifier is pre-set to `com.tabby.app` — change if needed

### 3. Build and run

Press `⌘R` or choose **Product → Run**. The app will appear in your menu bar with the Tabby cat icon.

### 4. Build a DMG for others to install

From the `Tabby/` directory (where `Tabby.xcodeproj` lives):

```bash
./scripts/build-dmg.sh
# or: make dmg
```

Output: `dist/Tabby-1.0.dmg` (version comes from the Xcode project).

Send that `.dmg` file to anyone on macOS 13+. They should:

1. Double-click the DMG to mount it
2. Drag **Tabby** into **Applications**
3. **First launch only:** right-click Tabby in Applications → **Open** → confirm (unsigned app)
4. If macOS still blocks it, run in Terminal:
   `xattr -dr com.apple.quarantine /Applications/Tabby.app`

Full instructions are in `INSTALL.txt` inside the DMG.

### 5. Optional: Code-sign for distribution

```bash
# Sign with your Developer ID
codesign --deep --force --verify --verbose \
         --sign "Developer ID Application: Your Name (TEAMID)" \
         build/Build/Products/Release/Tabby.app

# Notarize (requires Xcode + Apple Developer account)
xcrun notarytool submit Tabby.zip \
      --apple-id your@email.com \
      --team-id TEAMID \
      --password "@keychain:AC_PASSWORD" \
      --wait
```

## Data Storage

| Setting | Location |
|---------|----------|
| Local (default) | `~/Library/Application Support/Tabby/bookmarks.json` |
| iCloud enabled | `~/Library/Mobile Documents/com~apple~CloudDocs/Tabby/bookmarks.json` |
| Backups | `~/Library/Application Support/Tabby/backups/` |
| Settings | `~/Library/Application Support/Tabby/settings.json` |

To test with sample data, copy `bookmarks.sample.json` to:
```
~/Library/Application Support/Tabby/bookmarks.json
```

## Global Hotkey

Default: **⌘⇧L** (Cmd+Shift+L)

The hotkey is registered using Carbon's `RegisterEventHotKey` API — no accessibility permissions required. To change it, edit the `hotKeyCode` and `hotKeyModifiers` values in `SettingsStore.swift`, or expose them in the Settings UI.

## Project Structure

```
Tabby/
├── TabbyApp.swift              — @main entry point
├── AppDelegate.swift           — NSStatusItem + NSPopover + hotkey
├── Models/
│   ├── Bookmark.swift          — Bookmark data model (Codable)
│   ├── Tag.swift               — Tag model with color
│   ├── AppSettings.swift       — Persisted user settings
│   ├── ImportTypes.swift       — Import formats, folder tree, results
│   └── BrowserSource.swift     — Browser paths + scan result types
├── ViewModels/
│   ├── BookmarkStore.swift     — Main state: CRUD, search, sort, filter
│   └── SettingsStore.swift     — Settings state + launch-at-login
├── Views/
│   ├── MenuBarView.swift       — Root popover view (search bar + list + footer)
│   ├── BookmarkListView.swift  — Filtered list with delete confirmation
│   ├── AddBookmarkView.swift   — Add/edit form with auto-fetch
│   ├── BookmarkRowView.swift   — Individual row with hover actions
│   ├── TagChipsView.swift      — Horizontal tag filter strip + tag pills
│   ├── SettingsView.swift      — Settings panel (General / Sync / Backup)
│   ├── EmptyStateView.swift    — Empty state illustration
│   ├── ExportImportView.swift  — Export and import controls
│   └── Import/
│       ├── ImportFlowView.swift    — Popover import sheet (file + browser)
│       ├── BrowserImportView.swift — FDA + browser detection list
│       └── FirstRunWindow.swift    — First-launch welcome window
├── Services/
│   ├── DataService.swift       — JSON read/write + iCloud path switching
│   ├── ExportService.swift     — CSV / JSON / PDF / HTML / Markdown export
│   ├── ImportService.swift     — CSV / JSON / HTML import
│   ├── ImportCoordinator.swift — Import state machine + rollback
│   ├── BrowserBookmarkScanner.swift — Direct browser bookmark scan
│   ├── FullDiskAccessChecker.swift  — Full Disk Access probe + settings link
│   ├── FaviconService.swift    — Page title + favicon fetching
│   └── BackupService.swift     — Auto-backup creation and restore
└── Utils/
    ├── HotKeyManager.swift     — Carbon RegisterEventHotKey wrapper
    ├── Extensions.swift        — Color hex, Date formatting, View modifiers
    └── Constants.swift         — App-wide constants and file paths
```

## Export Formats

| Format | Notes |
|--------|-------|
| CSV | Title, URL, Tags (semicolon-separated), Notes, Date Added, Click Count |
| JSON | Full export including tags. Re-importable. |
| PDF | Multi-page, clickable links, grouped by tag |
| HTML | Netscape Bookmark format — import directly into Chrome, Firefox, Safari |
| Markdown | `- [Title](URL)` grouped by tag, with notes as inline text |

## License

MIT
