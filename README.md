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

## Download

**[Download the latest release](https://github.com/xx-derek/disk-inventory-next/releases/latest)**
— a universal build for macOS 11 or later. Unzip it and drag it to Applications.

Each release also carries a `.sha256` file beside the zip, so the download can be checked
rather than trusted:

```sh
shasum -a 256 -c DiskInventoryNext-v1.0.0-universal.zip.sha256
```

Then run this once, or macOS will refuse to open it:

```sh
xattr -dr com.apple.quarantine "/Applications/Disk Inventory Next.app"
```

Releases are **not signed with a Developer ID and not notarized**, because both require a
paid Apple Developer Program membership. The app is ad-hoc signed, which is what lets it
execute on Apple silicon, but Gatekeeper will not accept that for anything downloaded
through a browser — it is the quarantine attribute the command above removes, not the app,
that macOS objects to.

Without the Terminal: try to open it, let macOS refuse, then go to **System Settings →
Privacy & Security**, find the message about the blocked app near the bottom, and choose
**Open Anyway**.

**Or [build it yourself](#building-from-source)** — a locally built app is never
quarantined, so none of this applies, and this project builds from a clean checkout with
nothing to install first.

## Why the fork

The original was last released in March 2022 and had drifted far enough from current macOS
that it could no longer be built, let alone run natively: it targeted Intel Macs and
depended on prebuilt frameworks that were not included with the source. This fork exists to
fix that and to bring the interface up to date.

## What's changed

All of the work below happened between 15 and 16 August 2026.

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
- A file's size was initialised from a pointer instead of the number it points at, and a
  diagnostic scanned a hex value over the string pointer holding it.
- Own-app filtering used a hardcoded application name, so it stopped working on rename.

### Repository

Sources moved out of the repository root, where 78 `.h`/`.m` files sat beside `Info.plist`,
into `Source/` with one directory per Xcode group; images moved to `Resources/`. Every text file is UTF-8. Paths in commits before 15 August 2026 will not
match the current layout.

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

None — the app links only system frameworks. See
[No external dependencies](#no-external-dependencies) for what used to be required and
where it went.

### Releases

Two workflows under [`.github/workflows/`](.github/workflows):

- **Build** runs on every push and pull request. It builds Release with ad-hoc signing,
  **fails if the build produces any warning**, and checks the product is universal.
- **Release** runs on a `v*` tag, or on demand. It builds, signs, notarizes, staples and
  attaches a single universal `.zip` to a draft GitHub release.

```sh
git tag v1.0.0 && git push origin v1.0.0
```

The release is created as a **draft** so the artifact can be checked before it is public.
Work through [`.github/RELEASE_CHECKLIST.md`](.github/RELEASE_CHECKLIST.md) before
publishing it — most of this fork's interface was verified programmatically, which says
nothing about whether a click lands where it looks.

Releases are **one universal binary**, not one per architecture. The executable is under a
megabyte of a 3.3 MB bundle — the icon and the four localizations are most of it — so
thinning to a single architecture saves about 200 KB on a 2 MB download. That is not worth
asking people which Mac they have, and a thin build would break for anyone moving their
apps to a new machine with Migration Assistant.

#### Signing secrets

Without these the release workflow still runs, but produces an ad-hoc signed build that
Gatekeeper will refuse on anyone else's Mac. For a real release, set them in the
repository's Actions secrets:

| Secret | What |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | base64 of a "Developer ID Application" `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | the password it was exported with |
| `MACOS_TEAM_ID` | the 10-character team identifier |
| `NOTARY_KEY_P8` | base64 of an App Store Connect API key (`.p8`) |
| `NOTARY_KEY_ID` | that key's ID |
| `NOTARY_ISSUER_ID` | the issuer UUID from App Store Connect |

```sh
base64 -i DeveloperID.p12 | pbcopy      # and likewise for the .p8
```

An API key is used rather than an Apple ID and app-specific password because it does not
involve two-factor prompts. Signing and notarization have **not been exercised yet** — every
build so far has been ad-hoc — so expect the first tagged run to need a correction or two.

### macOS privacy protections

Modern macOS restricts access to Desktop, Documents, Downloads, and other locations. The
app detects these before scanning and explains the prompt you'll see. Granting **Full Disk
Access** in *System Settings → Privacy & Security* produces the most complete results.
Background: `documentation/macOS privacy protected folders.txt`.

## Documentation

Notes inherited from the original project live in [`documentation/`](documentation/).
`release notes.txt` is the version history of the **original** Disk Inventory X releases
and intentionally still refers to it by that name — it is a historical record.

## Supporting the project

Disk Inventory Next accepts donations to this address on any EVM-compatible chain:

```
0xe56f2b8e59c96e2bcb7b4d9f636cb3badfdd5abc
```

The app shows the same address, with a QR code, in **Help → Support Disk Inventory Next**.

The original **Disk Inventory X** by Tjark Derlien — most of the code this is built on —
takes donations separately at [derlien.com](http://www.derlien.com). Those go to him and
not to this fork.

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

- **Tjark Derlien** — original author of Disk Inventory X, and of most of the code this fork
  is built on: about 81% of the source still sits in files bearing his copyright
- **Anton Repponen** — application icon of the original Disk Inventory X, replaced in this fork
- **Chuck Pisula / Apple** — `ImageAndTextCell`, Apple sample code, used under its own
  licence with the notice retained
- Treemap rendering under `Source/TreeMapView/` was written for this fork and is GPL-3 like the
  rest of the project
