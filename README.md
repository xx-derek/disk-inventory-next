# Disk Inventory Next

A macOS disk usage visualizer. It scans a volume or folder and shows where your space went
as a **treemap** — every file is a rectangle sized in proportion to the space it occupies
and colored by file type — alongside a sortable outline view and a breakdown by file kind.

---

> ### Modification notice
>
> **Disk Inventory Next is a modified version of [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x),
> originally created by Tjark Derlien.** This project was renamed and modified starting
> **15 August 2026**. It is an independent community fork and is **not affiliated with,
> endorsed by, or supported by** the original author. Please direct issues with this
> version here, not to the original project.
>
> Original project homepage: [derlien.com](http://www.derlien.com/) ·
> Upstream source: [gitlab.com/tderlien/disk-inventory-x](https://gitlab.com/tderlien/disk-inventory-x)

## Why the fork

The original was last updated in March 2022 and targets Intel Macs on older macOS
releases. This fork exists to modernize it:

- **Runs natively on Apple silicon.** The original depended on Intel-only prebuilt
  frameworks, so it could only run under Rosetta. Those are gone.
- **Builds from a clean checkout** on a current Xcode, with no external frameworks to
  supply first.
- Interface updates

## Changes from the original

| Date | Change |
| --- | --- |
| 2026-08-15 | Renamed from "Disk Inventory X" to "Disk Inventory Next"; bundle identifier changed from `com.derlien.DiskInventoryX` to `io.github.xxderek.DiskInventoryNext` |
| 2026-08-15 | Own-app filter in `AppsForItem` now derives the app name from the running bundle instead of a hardcoded string, so it survives renames |
| 2026-08-15 | Replaced `TreeMapView.framework` with an independent GPL-3 treemap implementation in [`Source/TreeMapView/`](Source/TreeMapView) |
| 2026-08-15 | Removed the OmniGroup frameworks entirely; the toolbar and preferences code they provided now lives in the app's own classes, and `OASplitView` gave way to a plain `NSSplitView` |
| 2026-08-15 | Builds as a universal arm64 + x86_64 binary; deployment target raised from 10.11 to 10.13 |
| 2026-08-15 | Fixed a preferences bug where "Restore Defaults" compared a 64-bit sheet response against a 32-bit constant and never matched |
| 2026-08-15 | Fixed a crash opening the "Open With" menu, caused by a sort method that no longer existed |
| 2026-08-15 | Fixed treemap clicks selecting nothing: the layout was converted into a bottom-up backing space, putting every cell outside the view, which also broke tooltips and the hover readout |
| 2026-08-15 | Fixed a file's size being initialised from a pointer instead of the number it points at (masked, because sizes are recalculated before display) |
| 2026-08-15 | Migrated the codebase from manual retain/release to ARC |
| 2026-08-15 | Fixed a diagnostic that scanned a hex value over the string pointer holding it, then logged the result as an object |
| 2026-08-15 | Moved the sources out of the repository root into `Source/`, and the loose images into `Resources/`; the directories now mirror the Xcode groups |
| 2026-08-15 | Dropped the vendored CocoaTech pasteboard classes; `FSItem` promises its own data, so the Services menu now offers `public.file-url` like dragging does, and HTML and PDF are offered instead of being silently refused |
| 2026-08-15 | Rebuilt the Info panel on `NSGridView`, removing the last vendored CocoaTech code; values are now selectable text, long paths wrap, and the panel follows dark mode |
| 2026-08-15 | Replaced all 14 toolbar and preference icons with SF Symbols and deleted the bitmaps; deployment target raised from 10.13 to 11.0, which SF Symbols require |
| 2026-08-15 | Replaced the "Show File Kind Statistics" toolbar button with the standard macOS sidebar toggle, and made the pane slide rather than jump |
| 2026-08-15 | Filled the missing 16×16 app icon sizes, so the menu bar and Finder list no longer show a downscaled 32px icon |
| 2026-08-15 | Fixed the Services menu registering only the legacy filenames type, so no service wanting a file URL ever offered itself |
| 2026-08-15 | Fixed the Info panel showing setuid and setgid in all three permission positions — `/usr/bin/sudo` read `-r-s--s--s` where `ls` says `-r-s--x--x` |

## Features

- **Treemap visualization** — file size mapped to rectangle area, colored by file kind
- **Outline view** — sortable, navigable file/folder tree with size columns
- **File kind statistics** — see which types of file dominate a volume
- **Finder integration** — open files, "Open with…", system services, drag & drop
- **Move to Trash** directly from the app
- **Dark mode** support
- **Retina** treemap rendering at full resolution
- Localized in **English, German, French, and Spanish**

## Requirements

- **macOS 11.0 (Big Sur) or later**
- **Xcode** with the macOS SDK, to build from source

Builds as a **universal binary**, running natively on both Apple silicon and Intel Macs.

## Building from source

A fresh clone builds with no setup — there are no external dependencies and nothing to
fetch.

```sh
git clone https://github.com/xx-derek/disk-inventory-next.git
cd disk-inventory-next
./BuildRelease.sh
```

`BuildRelease.sh` wraps:

```sh
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Release
```

You can also open `Disk Inventory Next.xcodeproj` in Xcode and build the app target.

The project is set up to sign with this fork's developer team. To build on a machine
without that certificate, sign ad-hoc instead:

```sh
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Release \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER=""
```

Use ad-hoc rather than disabling signing altogether: an unsigned binary will not run on
Apple silicon.

### Dependencies

None. The app links only system frameworks.

It previously required two sets of prebuilt frameworks — the OmniGroup frameworks
(`OmniAppKit`, `OmniBase`, `OmniFoundation`) and `TreeMapView.framework` — which were not
included here and were resolved through build settings pointing outside the repository.
Both were Intel-only binaries without headers, so they made a native Apple silicon build
impossible. They have been replaced by source in this repository:

| Replaced | By |
| --- | --- |
| `TreeMapView.framework` | [`Source/TreeMapView/`](Source/TreeMapView) — an independent treemap implementation written for this fork |
| OmniGroup frameworks | Nothing — the parts the app used were folded into its own classes, or replaced by the AppKit equivalents that have since appeared |

### macOS privacy protections

Modern macOS restricts access to Desktop, Documents, Downloads, and other locations. The
app detects these before scanning and explains the prompt you'll see. Granting **Full Disk
Access** in *System Settings → Privacy & Security* produces the most complete results.
Background: `documentation/macOS privacy protected folders.txt`.

## Documentation

Notes inherited from the original project live in [`documentation/`](documentation/).
`release notes.txt` is the version history of the **original** Disk Inventory X releases
and intentionally still refers to it by that name — it is a historical record.

## License

Free software under the **GNU General Public License, version 3 or later**. Full text in
[`COPYING`](COPYING).

```
Copyright (C) 2003-2022 Tjark Derlien.
Copyright (C) 2026 Disk Inventory Next contributors.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 3
of the License, or any later version.
```

Distributed in the hope that it will be useful, but **without any warranty**; without even
the implied warranty of merchantability or fitness for a particular purpose. See the GNU
General Public License for more details.

The name "Disk Inventory X" belongs to the original project. This fork uses a different
name to avoid any implication of endorsement; the GPL grants copyright permissions only and
conveys no trademark rights.

## Credits

- **Tjark Derlien** — original author of Disk Inventory X, and of essentially all the code here
- **Anton Repponen** — application icon
- Treemap rendering under `Source/TreeMapView/` was written for this fork and is GPL-3 like the
  rest of the project
