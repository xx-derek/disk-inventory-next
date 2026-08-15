# Disk Inventory X

> **This is a fork.** The original Disk Inventory X was created by **Tjark Derlien** and is hosted at
> [gitlab.com/tderlien/disk-inventory-x](https://gitlab.com/tderlien/disk-inventory-x)
> (project homepage: [derlien.com](http://www.derlien.com/)).
> All credit for the application belongs to the original author.

Disk Inventory X is a disk usage utility for macOS. It scans a volume or folder and shows
where your space went as a **treemap** — every file is a rectangle sized in proportion to
the space it occupies and colored by file type — alongside a sortable outline view and a
breakdown by file kind.

---

## About this fork

This repository is a fork of the upstream GitLab project, published on GitHub for easier
discovery, issue tracking, and future modifications.

**Current state:** this fork is at upstream commit
[`4da1371`](https://gitlab.com/tderlien/disk-inventory-x/-/commit/4da1371b14f1158e2d923c95f645523b7c05c0bf)
("macOS 12 compatibility, project ready for signing and notarization", 2022-03-16) and
**contains no changes to the original source yet** — apart from this README. Any
modifications made later will be listed below.

### Changes from upstream

_None yet._

<!--
When you make changes, list them here so downstream users can see what differs, e.g.:

- Apple Silicon (arm64) build support
- Fixed <some bug> in FSItem
-->

### Relationship to the original

Because upstream lives on GitLab, GitHub does not show a native "forked from" link. The
upstream history is preserved here in full: all 8 original commits and the `1.2`, `1.2b1`,
and `1.3` tags.

To pull in future upstream changes:

```sh
git remote add upstream https://gitlab.com/tderlien/disk-inventory-x.git
git fetch upstream
git merge upstream/master
```

## Features

- **Treemap visualization** — file size mapped to rectangle area, with color coding by file kind
- **Outline view** — a sortable, navigable file/folder tree with size columns
- **File kind statistics** — see at a glance which types of file dominate a volume
- **Finder integration** — open files, "Open with…", system services, and drag & drop to other apps
- **Move to Trash** directly from the app
- **Dark mode** support (macOS 10.14+)
- **Retina** rendering of the treemap at full resolution
- Localized in **English, German, French, and Spanish**

## Requirements

- **macOS 10.11 or later** (the Xcode project's deployment target; upstream release notes
  for 1.2 recommend 10.13+)
- **Xcode** with the macOS SDK, to build from source

The project version in the Xcode project is currently `1.4b2`. Upstream builds are
Intel (x86_64); Apple Silicon Macs can run them under Rosetta 2.

## Building from source

Clone the repository and build the Release configuration:

```sh
git clone https://github.com/xx-derek/disk-inventory-x.git
cd disk-inventory-x
./BuildRelease.sh
```

`BuildRelease.sh` is a thin wrapper around:

```sh
xcodebuild -project "Disk Inventory X.xcodeproj" -configuration Release
```

You can also just open `Disk Inventory X.xcodeproj` in Xcode and build the app target.

Note that the project is set up for code signing and notarization; for a local build you
may need to adjust the signing team in the target's **Signing & Capabilities** settings.

### macOS privacy protections

Modern macOS restricts access to certain folders (Desktop, Documents, Downloads, and
others). Disk Inventory X handles these specially and cannot report on directories the
system will not let it read. See `documentation/macOS privacy protected folders.txt` for
details. Granting the app **Full Disk Access** in *System Settings → Privacy & Security*
produces the most complete results.

## Documentation

Additional notes from the original author live in the [`documentation/`](documentation/)
directory:

| File | Contents |
| --- | --- |
| `release notes.txt` | Version history for upstream releases |
| `known bugs.txt` | Known issues |
| `feature suggestions.txt` | Ideas that were never implemented |
| `macOS privacy protected folders.txt` | How the app deals with protected directories |
| `memory usage using NSURL.txt` | Notes on memory behavior |

## License

Disk Inventory X is free software, licensed under the **GNU General Public License,
version 3 or later**. The full license text is in [`COPYING`](COPYING).

```
Copyright (C) Tjark Derlien.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 3
of the License, or any later version.
```

This program is distributed in the hope that it will be useful, but **without any
warranty**; without even the implied warranty of merchantability or fitness for a
particular purpose. See the GNU General Public License for more details.

## Credits

- **Tjark Derlien** — original author of Disk Inventory X
- **Anton Repponen** — application icon (introduced in 1.2)
- The app links against the **OmniGroup** frameworks (`OmniAppKit`, `OmniBase`,
  `OmniFoundation`) and includes **CocoaTech** sources under `CocoaTech-Depreciated/`.
- The treemap rendering lives in a separate `TreeMapView.framework`, split out by the
  original author so it can be reused in other applications.
