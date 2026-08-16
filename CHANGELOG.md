# Changelog

Everything this fork has changed since [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x).
Tjark Derlien's own release history for the original is kept separately, unaltered, in
[`documentation/release notes.txt`](documentation/release%20notes.txt).

## 1.0.0 — 15 August 2026

The first release of the fork. Everything below separates it from the original.

### Runs on current macOS

- **Native on Apple silicon**, as a universal arm64 + x86_64 binary. The original depended
  on Intel-only prebuilt frameworks and could only run under Rosetta.
- **Deployment target raised from 10.11 to 11.0**, which is what SF Symbols require.
- **Migrated from manual retain/release to ARC**, and the remaining deprecated API swept
  up behind it. The build is clean.
- Renamed to "Disk Inventory Next"; bundle identifier `com.derlien.DiskInventoryX` became
  `io.github.xxderek.DiskInventoryNext`.

### No external dependencies

A fresh clone builds with nothing to fetch. Four prebuilt frameworks used to be resolved
through build settings pointing outside the repository, and none of them was included with
the source — they were Intel-only binaries without headers, which is what made a native
build impossible:

| Was | Now |
| --- | --- |
| `TreeMapView.framework` | an independent GPL-3 implementation in [`Source/TreeMapView/`](Source/TreeMapView), written from the published algorithms |
| `OmniAppKit`, `OmniBase`, `OmniFoundation` | folded into the app's own classes, or replaced by the AppKit equivalents that have appeared since |

A set of CocoaTech `NT*` classes was vendored into the source rather than linked. Those are
gone too: the pasteboard handling and the Info panel are the app's own now, which also
settled the awkwardness of shipping "all rights reserved" files in a GPL project.

### Interface

- **Drawers replaced by collapsible split-view panes.** `NSDrawer` has been deprecated for
  years and never looked right in dark mode. The file-kind statistics pane is now toggled
  by the standard macOS sidebar button, and slides rather than jumping.
- **Toolbar and preference icons are SF Symbols**, so they are vector, tint correctly and
  follow dark mode; fourteen bitmap files were deleted.
- **New application icon**, supplied in all ten sizes including the 1024px one that was
  missing, with its source artwork kept in the repository.
- **Treemap palette reworked** — twelve hues spaced around the colour circle, light enough
  to read and saturated enough not to look grey, with no cell falling to near-black at its
  edges.
- **Info panel rebuilt** on `NSGridView`: values are selectable text, long paths wrap, and
  it follows dark mode. Three vendored classes went with it.
- **Settings window redesigned** and laid out in code rather than in twelve localized nibs,
  with consistent alignment, secondary-styled help text, a Restore Defaults button that is
  actually reachable, and the title "Settings" on macOS 13 and later. The German, Spanish
  and French translations moved into `Preferences.strings`.
- **Scanning no longer freezes the app.** The directory walk runs on a background queue
  instead of taking turns with the interface on the main thread, and the progress panel
  shows an estimated percentage.

### Fixes

- **Drag and drop did nothing, and there was no Copy at all.** macOS stopped mapping
  `NSFilenamesPboardType` to `public.file-url`, so the file never reached the receiver.
  Dragging out of the outline also offered to make an alias rather than a copy.
- **No service wanting a file URL ever appeared** in the Services menu, which registered
  only that same dead type. HTML and PDF were compared against pasteboard type *names*
  rather than UTIs, so they were never offered either.
- **Clicking the treemap selected nothing.** The layout was converted into a bottom-up
  backing space, putting every cell outside the view; tooltips and the hover readout had
  gone with it.
- **"Restore Defaults" did nothing** — it compared a 64-bit sheet response against a
  32-bit constant.
- **Opening the "Open With" menu crashed**, on a sort method that no longer existed.
- **The Info panel misreported permissions**, showing setuid and setgid in all three
  positions: `/usr/bin/sudo` read `-r-s--s--s` where `ls` says `-r-s--x--x`.
- **The thirteenth file kind was drawn black**, and the next few nearly so.
- Own-app filtering used a hardcoded application name, so it stopped working on rename.

### Repository

Sources moved out of the repository root, where 78 `.h`/`.m` files sat beside `Info.plist`,
into `Source/` with one directory per Xcode group; images moved to `Resources/`. Every text file is UTF-8. Paths in commits before 15 August 2026 will not
match the current layout.
