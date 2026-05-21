## Learned User Preferences

- When implementing an attached plan: do not edit the plan file; use existing todos (do not recreate them); mark todos in_progress and complete all before stopping.

## Learned Workspace Facts

- Tabby is a macOS Swift/SwiftUI menu-bar app; main UI is the status-bar popover (~380×560), not a document window.
- Distributed outside the Mac App Store via signed/notarized DMG; app sandbox is disabled; browser import requires user-granted Full Disk Access.
- Bookmark import (file and browser) flows through ImportCoordinator into ParsedImport, then the existing commit/rollback/backup pipeline.
- Direct browser scan supports Chrome, Arc, Brave, Edge, and Comet; Arc uses StorableSidebar.json with a separate parser (not Chromium Bookmarks JSON).
- First-run import onboarding uses a standalone FirstRunWindow; Settings and re-import use the popover import sheet.
