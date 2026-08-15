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

Single Xcode target, `Disk Inventory Next` (application). Deployment target macOS 10.13;
`ARCHS = $(ARCHS_STANDARD)`, so the product is a universal arm64 + x86_64 binary. Project
version `1.4b2`. Bundle ID `io.github.xxderek.DiskInventoryNext`.

```sh
./BuildRelease.sh                                                       # Release build
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Debug
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Release clean
```

The project path contains a space — always quote it.

**A fresh clone builds with no setup.** There are no external dependencies and nothing to
fetch. If that ever stops being true, it is a regression, not the normal state.

Signing is the one thing that is machine-specific: `DEVELOPMENT_TEAM` is set to the fork
owner's team, so building on another machine needs an override rather than a project edit:

```sh
xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Release \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER=""
```

Ad-hoc (`"-"`) rather than unsigned: an unsigned binary will not execute on Apple silicon.

### Tests

There is no test target and no test files — `xcodebuild test` has nothing to run. Verify
changes by building and exercising the app against a real volume or folder.

The two pieces worth checking with a throwaway harness rather than by eye are the treemap
layout (cell area must stay proportional to weight — build a synthetic tree, compare
`itemRectByPathToItem:` areas against weight fractions) and the preferences panel (compile
a probe **into the built `.app`'s `Contents/MacOS/`** so `[NSBundle mainBundle]` resolves
and the page nibs load).

When testing anything about treemap coordinates, **derive the test points from the view's
bounds, never from `itemRectByPathToItem:`.** A point taken from a cell rect round-trips
through the very conversion under test, so a broken conversion still passes — that is
exactly how the flipped-backing bug above survived a layout test, an area-proportionality
test and a synthetic-click test before a real click found it. Useful assertions: every cell
rect lies inside the view's bounds, and a grid of points across the bounds all hit a cell
whose rect contains that point.

## Memory management: ARC

`CLANG_ENABLE_OBJC_ARC = YES`. The project was manual retain/release until 2026-08-15;
`git log` before that date is full of hand-balanced `retain`/`release`, so old commits read
differently from current code.

`-fobjc-arc-exceptions` is set in `OTHER_CFLAGS`, and **must stay set**. ARC's exception
cleanup is off by default for Objective-C, and this app throws exceptions as a normal
control-flow path: cancelling a scan raises `FSItemLoadingCanceledException`, and an
ejected volume raises `FSItemLoadingFailedException`. Without the flag, every cancelled
scan would leak whatever was in flight.

### Ownership rules that are not obvious

A few pointers are deliberately not strong. Changing any of them to strong compiles fine
and leaks silently:

- **`FSItem._parent` is `__unsafe_unretained`.** `_childs` owns downwards, so a strong
  back-pointer would put a cycle on every node and leak the entire scanned tree. It is
  unretained rather than weak because a scan builds millions of these and `-dealloc`
  already clears the children's pointers by hand (`-onParentDealloc`).
- **`FSItem._delegate`** (the document) is `__unsafe_unretained` for the same reason.
- **`TMVItem._dataSource`, `_delegate`, `_view`** are `__unsafe_unretained` — the view owns
  the renderer tree and outlives it, and a big treemap holds tens of thousands of cells.
- **`TreeMapView.delegate` / `.dataSource`** are `__weak`: few of them, and self-nilling is
  worth more than the speed.
- **Outlets pointing back up the ownership chain** (`_document`, `_windowController`) are
  `__weak`. Under MRR an `IBOutlet` was never retained; under ARC it is strong by default,
  which turns an upward outlet into a document that never deallocates.
- **`ZoomInfo._delegate` is `__weak`, and `-cancel` exists** because `NSTimer` retains its
  target. A running zoom keeps the `ZoomInfo` alive on its own, so `TreeMapView -dealloc`
  calls `-cancel` rather than just dropping its reference.
- **`NTPasteboardHelper` parks itself in a static set** while it owns a pasteboard, since
  under ARC it can no longer retain itself. It removes itself in `-pasteboardChangedOwner:`,
  holding a local strong reference across the removal.

### Verifying you have not reintroduced a cycle

The compiler cannot help here. Scan a folder repeatedly, dropping the document each time,
and watch `phys_footprint`: it should climb for a dozen passes and then **plateau**. A real
leak keeps growing linearly. Measured after the migration, a 361-file tree plateaus around
27 MB by pass 15 and is still flat at pass 40. Reading only three or four passes is not
enough to tell a leak from the initial ramp.

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
is safe.

### Editing a nib without Interface Builder

For structural changes — swapping a custom class, renaming an outlet — the `designable.nib`
*inside* each `.nib` bundle is the original XIB, in plain XML. Edit that and recompile.
`ibtool` refuses a file named `.nib`, so it has to be copied to a `.xib` first:

```sh
N=en.lproj/TreeMap.nib
sed -i '' 's| customClass="OASplitView"||' "$N/designable.nib"   # edit the XIB source
cp "$N/designable.nib" /tmp/edit.xib                             # ibtool needs the extension
ibtool --compile "$N/keyedobjects.nib" /tmp/edit.xib             # recompile in place
```

Keep `designable.nib` and `keyedobjects.nib` in step, and repeat for all four languages.
The recompile rewrites the archive in the modern NIBArchive format, so `plutil` can no
longer parse the result — that is expected, and AppKit reads both.

This is how `OASplitView` was removed. **Verify at runtime**, not by diffing: load the nib
in a probe and assert the objects survived (see Tests). A structural nib edit that silently
drops a connection will still build.

## `TreeMapView/` — the replaced dependency

The app used to link four prebuilt frameworks. All four were Intel-only binaries with no
headers, which made an Apple silicon build impossible, and none was in the repo. **The app
now links only system frameworks.**

The OmniGroup half was migrated away entirely (see [Where the Omni code went](#where-the-omni-code-went)).
What remains is the treemap widget, in `TreeMapView/`, resolved by `HEADER_SEARCH_PATHS`
(`$(SRCROOT)`) rather than a framework search path, so `#import <TreeMapView/…>` still works.

`TreeMapView` (the `NSView`), `TMVItem` (one cell — layout and hit testing),
`TMVCushionRenderer` (shading), `ZoomInfo` (the zoom effect), plus two small categories.
Written for this fork and GPL-3, from the published algorithms — squarified layout is
Bruls/Huizing/van Wijk 2000, cushion shading is van Wijk/van de Wetering 1999.

**It is not Tjark Derlien's `TreeMapView.framework`, and must not be replaced by it.** That
framework is published at `gitlab.com/tderlien/treemapview-framework` but carries *no
license* — no `LICENSE`, no `COPYING`, and "All rights reserved" in every source file. It
therefore cannot be vendored into this GPL-3 repo or redistributed in a built app. If
Derlien ever licenses it, that decision can be revisited; until then, do not copy code from
it, and be careful that "fixing" a rendering difference does not mean porting his.

Two invariants worth knowing before changing anything here:

- **Layout is computed in backing pixels, not points**, so cushions shade at full Retina
  resolution. Hit tests and `itemRectByCellId:` convert at the boundary — a change that
  mixes the two spaces will look right at 1× and be wrong at 2×.
- **Do not use AppKit's `convertPointToBacking:` / `convertRectToBacking:` here.** On a
  flipped view they convert into a bottom-up space and come back with a negated y, so a
  cell at the top of the view lands at a negative coordinate. `NSView-BackingCoordsHelpers`
  does the scaling itself and orients y downwards from the top-left, which is where a
  bitmap's first row is. Using AppKit's versions put the whole layout outside the view:
  every hit test missed, so clicking selected nothing, and tooltips and the hover readout
  went dead with it.
- **`calcLayout:` stops descending into cells below `TMVMinimumCellSize`.** A deep item can
  have no cell of its own, so `findTMVItemByPathToDataItem:` returns the nearest drawn
  ancestor rather than nil.

Selection notifications are posted for **user-driven changes only**; `selectItemByCellId:`
and `selectItemByPathToItem:` are deliberately silent, so a controller syncing the view to
the document cannot bounce the change back at itself.

## Where the Omni code went

The OmniGroup frameworks are gone; nothing named `OA*`, `OF*` or `OB*` remains. The pieces
the app actually used were folded into its own classes, so **do not reintroduce a
compatibility layer** — if something looks like it is missing, it was inlined:

| Was | Now |
| --- | --- |
| `OAToolbarWindowController` + `OAToolbarItem` + `OAToolbarWindowControllerEx` | `ToolbarWindowController` + `ToolbarItem` |
| `OAPreferenceController` | folded into `PrefsPanelController` |
| `OAPreferenceClient` | folded into `PrefsPageBase` |
| `OAPreferenceClientRecord` | `PrefsPageRecord` |
| `OAPasteboardHelper` | `CocoaTech-Depreciated/NTPasteboardHelper` |
| `OASplitView` | plain `NSSplitView` (`setPositionAutosaveName:` → `setAutosaveName:`) |
| `+[NSString isEmptyString:]`, `-[NSDictionary boolForKey:]`, `-[NSMutableDictionary setBoolValue:forKey:]`, the two `NSMutableArray` sorts, `+horizontalEllipsisString`, `-[NSTableView setFont:]` | inlined at their call sites |
| `OBPRECONDITION` | `NSAssert` (both compile out in release builds) |

`OASplitView` was the one class named inside the compiled nibs. It was removed by editing
the XIB and recompiling — see [Editing a nib without Interface Builder](#ui-files-are-binary-nib-not-xib).
Nothing else was ever nib-referenced, which is why the rest was a rename rather than a rewrite.

Two Omni mechanisms are gone rather than reimplemented, so **`Info.plist` no longer drives
them and `main.m` does**: `NSPrincipalClass` is plain `NSApplication` (was `OAApplication`),
and `OFControllerClass` is removed. The factory defaults still live in `Info.plist`, now
under the `Registrations` key (`AppRegistrationsKey` in `Preferences.h`, renamed from
`OFRegistrations`), but `RegisterFactoryDefaults()` in `main.m` registers them before
`NSApplicationMain`. **Adding a preference means adding it there**, or bound controls will
read nil. `PrefsPanelController` reads its page list from the same dict, keyed by its own
class name, and skips any page whose class is not in the binary — which is why the disabled
`FinderCMPrefPage` entry is harmless.

`AppController` was an `OAController` and is now an empty `NSObject`; nothing instantiates
it, since only `OFControllerClass` ever did.

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

Licensed GPL-3 (`COPYING`). Source files inherited from upstream carry a GPL header naming
Tjark Derlien — preserve it when editing, never replace it. As a modified version, the
README must keep its §5(a) modification notice and date.

Files written for this fork (everything under `TreeMapView/`, `PrefsPageRecord`, plus
`RegisterFactoryDefaults()` in `main.m`) carry the same GPL-3 header under "Disk Inventory
Next contributors" — they are not Derlien's work and should not be attributed to him. Match
whichever header fits when adding a file.

Before pulling in any third-party code, check that it is actually licensed. Being public on
GitLab or GitHub is not a license; `treemapview-framework` is the cautionary example
(see [`TreeMapView/`](#treemapview-and-omnicompat--the-two-replaced-dependencies) above).
