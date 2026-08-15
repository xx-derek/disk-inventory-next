# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Disk Inventory Next — a macOS disk usage visualizer (treemap + outline view), written in
Objective-C/Cocoa. This is a renamed fork of Tjark Derlien's **Disk Inventory X** at
`gitlab.com/tderlien/disk-inventory-x`; `origin` points at that GitLab upstream and
`github` at this fork. The rename landed 2026-08-15; goals are current-macOS support and
UI modernization. See README.md for the fork relationship and how to sync upstream.

Anything still named "Disk Inventory X" is either upstream history or a deliberate
historical record — see [Naming](#naming) below before "fixing" it.

## Building

Single Xcode target, `Disk Inventory Next` (application). Deployment target macOS 10.11;
project version `1.4b2`. Bundle ID `io.github.xxderek.DiskInventoryNext`.

```sh
./BuildRelease.sh                                                       # Release build
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Debug
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Release clean
```

The project path contains a space — always quote it.

### The build will not work from a fresh clone

Two dependencies are neither vendored nor fetched by any script. They are resolved through
`FRAMEWORK_SEARCH_PATHS_OMNI` / `FRAMEWORK_SEARCH_PATHS_TREEMAP` in `project.pbxproj`,
which point four directory levels above `SRCROOT` at the original author's machine layout:

| Configuration | Omni frameworks | TreeMapView |
| --- | --- | --- |
| Debug | `$(SRCROOT)/../../../../OmniFrameworks_2018-09-22/Build/Products/Debug` | `$(SRCROOT)/../../../../TreeMapView/vdev/make/Build/Products/Debug` |
| Release | `$(SRCROOT)/../../../../OmniFrameworks_2018-09-22/Build/Release` | `$(SRCROOT)/../../../../TreeMapView/vdev/make/src/Build/Release` |

The app links `OmniAppKit`, `OmniBase`, `OmniFoundation`, and `TreeMapView.framework`.
Neither directory exists in a checkout of this repo. Before assuming a build failure is
caused by a code change, check whether these paths resolve; if not, the fix is to supply
the frameworks and repoint those two build settings, not to edit source. A built copy of
`TreeMapView.framework` ships inside an installed `/Applications/Disk Inventory X.app/Contents/Frameworks/`
(the *original* app, if present — its bundle name is unaffected by this fork's rename).

### Tests

There is no test target and no test files — `xcodebuild test` has nothing to run. Verify
changes by building and exercising the app against a real volume or folder.

## Memory management: manual retain/release, not ARC

`CLANG_ENABLE_OBJC_ARC` is unset, so the entire codebase is MRR. New code must balance
`retain`/`release`/`autorelease` by hand and implement `dealloc`. This is the most common
way to break this codebase — recent upstream history includes a dedicated commit fixing
`FSItem` leaks (`76304d9`).

## Architecture

### FileSystemDoc is the hub

`FileSystemDoc` (an `NSDocument`) owns essentially all state: the scanned tree, the
selection, the zoom stack, per-kind statistics, and per-document view options. Views do
not talk to each other — they read from the document and resynchronize via
`NSNotificationCenter`. The notifications are declared at the bottom of `FileSystemDoc.h`:

- `GlobalSelectionChangedNotification` — selection changed (userInfo has `NewItem`/`OldItem`)
- `ZoomedItemChangedNotification` — zoom target changed
- `FSItemsChangedNotification` — items added/removed/modified (e.g. after trash or refresh)
- `ViewOptionChangedNotification` — a display toggle changed; option name under `ChangedViewOption`

Observers live in `TreeMapViewController.m`, `FilesOutlineViewController.m`, and
`FileKindsTableController.m`. **When adding a mutation that affects displayed data, post
the matching notification from the document** — otherwise views silently go stale. The
header comments mark which document methods already post which notification.

### FSItem is the tree node

`FSItem` wraps an `NSURL` and models one file, folder, or synthetic entry. `FSItemType`
distinguishes real entries from the two synthetic ones the treemap draws:
`FreeSpaceItem` (volume free space) and `OtherSpaceItem` (space used by files outside the
scanned root). Code that walks the tree must handle these — check `isSpecialItem`.

Scanning is recursive via `loadChildren`, driven from `FileSystemDoc readFromFile:ofType:`.
`FSItem` calls back into the document through an informal delegate protocol
(`NSObject(FSItemDelegate)` at the bottom of `FSItem.h`) to ask whether to descend into
packages, whether to use physical vs. logical size, whether to ignore creator codes, and
to report progress. The delegate returning `NO` from `fsItemEnteringFolder:` is how
cancellation works — it raises `FSItemLoadingCanceledException`. Scanning therefore uses
**exceptions for control flow**; `FSItemLoadingFailedException` signals an unreadable or
ejected volume. Wrap tree walks accordingly.

The scan is **synchronous on the main thread**, not backgrounded. Responsiveness comes from
`FileSystemDoc fsItemEnteringFolder:` calling `[_progressController runEventLoop]` on every
folder to pump events manually, then returning `![_progressController cancelPressed]`. Any
work added to that callback runs once per directory and directly slows every scan.

Sizes are `unsigned long long` / `UInt64` throughout. Do not narrow them.

### Aggregation and lookup

`FileKindStatistic` (declared in `FileSystemDoc.h`, not its own file) aggregates count and
total size per file kind; the document keeps a kind-name → statistic dictionary and
recalculates it when view options change. `FSItemIndex` is a hand-rolled name/kind/path
index — the header notes SearchKit was tried and abandoned as too slow, so don't
"modernize" it back.

`FileTypeColors` assigns treemap colors per kind, reserving distinct colors for the
largest kinds.

### Controllers

`MainWindowController` owns the split view (outline + treemap) and nearly every `IBAction`
(zoom, refresh, trash, reveal in Finder, drawer toggles). The per-view controllers
(`TreeMapViewController`, `FilesOutlineViewController`, `FileKindsTableController`,
`SelectionListTableController`) each manage one pane. `MyDocumentController` is an
`NSDocumentController` subclass handling app-level concerns (preferences panel, donation
panel, zoom-stack menu). Drawers are used for the kind statistics and selection list —
deprecated by Apple and visually imperfect in dark mode, per `documentation/release notes.txt`.

### Preferences: two layers

Global app settings are `NSUserDefaults` keys declared in `Preferences.h`. Some are read
through `boolForVersionDependantKey:`, a category that scopes a default to the app version
so "don't show this again" dialogs reappear after an upgrade. Separately, each document
holds a `_viewOptions` dictionary of per-window display toggles, accessed through the
`NSMutableDictionary(DocumentPreferences)` category. Adding a display toggle usually means
touching both layers plus a `ViewOptionChangedNotification` post.

### Prefix header

`Disk Inventory Next_Prefix.pch` is precompiled into every file and already imports Cocoa,
Carbon, and `OmniBase`. It also defines the logging macro:

```objc
#define LOG(x, args...) { if (g_EnableLogging) NSLog(x, ## args); }
```

Use `LOG(...)` rather than bare `NSLog`; it is gated on the `EnableLogging` preference.

### macOS privacy-protected folders

Modern macOS blocks Desktop/Documents/Downloads and similar. `FileSystemDoc
checkForProtectedFolders:` detects them before scanning via
`privacyProtectedFoldersInURL:` (in `Foundation Extensions/NSFileManager-Extensions`) and
shows a one-time explanatory alert gated on `DontShowPrivacyWarningMessage`.
`NSURL-Extensions` adds `stillExists` for revalidating URLs after a volume is ejected.
Background and localized strings: `documentation/macOS privacy protected folders.txt`.

## UI files are binary `.nib`, not `.xib`

Every interface lives in compiled `.nib` bundles under the `.lproj` directories. They are
not text and cannot be edited or diffed with normal tools — open them in Interface Builder.
Localizations: `de`, `en`, `es`, `fr` (`English.lproj` is a legacy leftover holding only
Help index files). A UI change means updating the `.nib` in each of the four languages plus
`Localizable.strings`.

To change nib text without Interface Builder, round-trip through `ibtool`:

```sh
ibtool --generate-strings-file /tmp/x.strings en.lproj/MainMenu.nib   # extract
# edit /tmp/x.strings (it is UTF-16 — do not sed it blindly)
ibtool --strings-file /tmp/x.strings --write /tmp/new.nib en.lproj/MainMenu.nib
```

This recompiles `keyedobjects.nib` with the current Xcode toolchain. Two consequences seen
during the rename: the archive shrinks (modern compiler, benign), and per-OS variants like
`keyedobjects-101300.nib` are **not** regenerated — current `ibtool` no longer emits them
even with `--minimum-deployment-target`. AppKit falls back to `keyedobjects.nib`, so this
is safe, but nib edits made this way have not been verified at runtime (the app can't be
built here — see Dependencies).

## Vendored legacy code

`CocoaTech-Depreciated/` holds third-party `NT*` classes (pasteboard, info view, ID3
helpers) kept for compatibility. Treat as legacy; prefer not to extend it.

## Naming

The app was renamed from "Disk Inventory X" to "Disk Inventory Next" on 2026-08-15.
Two places still say "Disk Inventory X" **on purpose** — do not rename them:

- `documentation/release notes.txt` and
  `documentation/macOS privacy protected folders - localized strings.rtf` — a historical
  record of releases that really were Disk Inventory X. Rewriting them would falsify history.
- Tjark Derlien's copyright lines in every source header. GPL-3 §4 requires keeping them
  intact; add new copyright lines alongside, never in place of.

Note `NSLocalizedString` keys are the English strings themselves, so changing a literal in
a `.m` file requires the same change to the key **and** value in all four
`Localizable.strings`, or translations silently fall back to the raw key.

## Encoding: everything text is UTF-8

Normalized on 2026-08-15. Every text file in the repo is UTF-8 (most are pure ASCII), and
all 89 `fileEncoding` entries in `project.pbxproj` are `4` (`NSUTF8StringEncoding`). Keep
it that way — write new files as UTF-8 and do not reintroduce `fileEncoding = 30`
(MacRoman), which is what 69 of them used to be.

Two consequences worth knowing:

- **`.strings` sources are UTF-8**, which Xcode auto-detects (they carry no `fileEncoding`
  entry). `builtin-copyStrings` still re-encodes them to UTF-16 *in the built product* via
  `--outputencoding UTF-16`, so runtime behavior is unchanged. Don't "fix" the source files
  back to UTF-16.
- **`sed` across the tree is now safe.** It previously failed with `illegal byte sequence`
  on MacRoman files; if you still hit that, something non-UTF-8 has crept back in.

Genuinely binary files must never be treated as text — `.gitattributes` marks them. The
trap is `*/Help/Help idx`: an Apple Help Indexer `Bud1` container with no file extension
that encoding heuristics will happily misread as text.

## Reference

Upstream notes live in `documentation/` — `release notes.txt` (version history),
`known bugs.txt`, and `feature suggestions.txt` are the useful ones for understanding
intended behavior and what was deliberately left unimplemented.

Licensed GPL-3 (`COPYING`). Source files carry a GPL header naming Tjark Derlien —
preserve it when editing, and match it when adding files. As a modified version, the
README must keep its §5(a) modification notice and date.
