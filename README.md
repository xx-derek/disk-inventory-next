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

- Support for current macOS versions
- Interface updates

## Changes from the original

| Date | Change |
| --- | --- |
| 2026-08-15 | Renamed from "Disk Inventory X" to "Disk Inventory Next"; bundle identifier changed from `com.derlien.DiskInventoryX` to `io.github.xxderek.DiskInventoryNext` |
| 2026-08-15 | Own-app filter in `AppsForItem` now derives the app name from the running bundle instead of a hardcoded string, so it survives renames |

_Functional changes to the application itself are still in progress; see "Why the fork" above._

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

- **macOS 10.11 or later** (current deployment target; being revised as part of the
  modernization work)
- **Xcode** with the macOS SDK, to build from source

## Building from source

> **Note:** the build currently requires two external frameworks that are not included in
> this repository. See [Dependencies](#dependencies) below — a fresh clone will not build
> without them.

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

### Dependencies

The project links against two frameworks that are neither vendored here nor fetched by any
script. They resolve through the `FRAMEWORK_SEARCH_PATHS_OMNI` and
`FRAMEWORK_SEARCH_PATHS_TREEMAP` build settings, which point outside the repository:

| Dependency | Used for |
| --- | --- |
| OmniGroup frameworks (`OmniAppKit`, `OmniBase`, `OmniFoundation`) | Application and Foundation utilities |
| `TreeMapView.framework` | The treemap rendering view |

Both paths must be supplied and repointed before the project will link. Removing this
external dependency is a goal of the modernization work.

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
- Links against the **OmniGroup** frameworks; includes **CocoaTech** sources under `CocoaTech-Depreciated/`
- Treemap rendering lives in a separate `TreeMapView.framework`, split out by the original author
