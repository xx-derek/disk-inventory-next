# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Disk Inventory Next — a macOS disk usage visualizer (treemap + outline view), written in
Objective-C/Cocoa. This is a renamed fork of Tjark Derlien's **Disk Inventory X** at
`gitlab.com/tderlien/disk-inventory-x`; `origin` is this fork on GitHub and `upstream`
that GitLab repository. (The two were named the other way round until 2026-08-17, so
older instructions may have them reversed — check `git remote -v` before pushing.) The
rename landed 2026-08-15; goals are current-macOS support and UI modernization. See
README.md for the fork relationship and how to sync upstream.

Anything still named "Disk Inventory X" is either upstream history or a deliberate
historical record — see [Naming](#naming) below before "fixing" it.

## Building

Single Xcode target, `Disk Inventory Next` (application). Deployment target macOS 11.0;
`ARCHS = $(ARCHS_STANDARD)`, so the product is a universal arm64 + x86_64 binary. Project
version `1.0.0` (`CURRENT_PROJECT_VERSION` `1`). Bundle ID
`io.github.xxderek.DiskInventoryNext`.

The version was `1.4b2` until 2026-08-16, which was **Derlien's** number carried over by the
rename — and a beta at that. This fork's own numbering starts at 1.0.0. Nothing else should
hardcode it: `CFBundleGetInfoString`, which froze it into four `InfoPlist.strings` files,
was removed, and the About box takes the version from the build settings.

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
`itemRectByPathToItem:` areas against weight fractions) and anything that loads a nib or
reads a localized string — compile a probe **into the built `.app`'s `Contents/MacOS/`** so
`[NSBundle mainBundle]` resolves. That is how the settings pages, the Info panel and the
`Preferences.strings` translations were checked.

Two things a probe cannot show you. **`-cacheDisplayInRect:toBitmapImageRep:` comes back
blank** for layer-backed text fields, so render through `-dataWithPDFInsideRect:` instead,
or screenshot the real window. And **a probe outside a modal session will not reproduce
modal-session behaviour** — the progress bar drew its indeterminate animation over the top
of a determinate value only in the running app, and looked correct in isolation.

When testing anything about treemap coordinates, **derive the test points from the view's
bounds, never from `itemRectByPathToItem:`.** A point taken from a cell rect round-trips
through the very conversion under test, so a broken conversion still passes — that is
exactly how the flipped-backing bug above survived a layout test, an area-proportionality
test and a synthetic-click test before a real click found it. Useful assertions: every cell
rect lies inside the view's bounds, and a grid of points across the bounds all hit a cell
whose rect contains that point.

The same method is the wrong side of an **area**-proportionality test too, for a different
reason: it answers with the nearest *drawn ancestor* when an item got no cell of its own, so
every merged file reports the remainder's rect. Asked that way the check reported an 86,000%
error against a layout that was in fact exact. Compare `[TMVItem weight]` against
`itemRectByCellId:` over the renderer tree, where every cell — remainders included — has a
rect and a weight of its own. That reads 0.000% and 100% coverage.

## Layout on disk

Sources moved out of the repository root into `Source/` on 2026-08-15; before that date
every `.h`/`.m` sat flat beside `Info.plist`, so paths in older commits will not match.
The directories mirror the Xcode groups one-for-one — a file's group **is** its folder.

```
Source/App/                    main.m, the prefix header, MainWindow(Controller),
                               MyDocumentController, AppController, ToolbarWindowController
Source/Model/                  FSItem(+Utilities), FSItemIndex, FileSystemDoc, FileTypeColors
Source/Controllers/            one controller per pane, plus the selection-list trio
Source/Panels/                 Info, Drives and Loading panels, and the volume transformers
Source/Preferences/            Preferences, PrefsPanelController, PrefsPageBase/Record,
                               PrefsPageLayout, the two pages
Source/Views/                  DIXTableView, DIXOutlineView, ImageAndTextCell, GenericArrayController
Source/Extensions/             NSAlert-, NSURL- and NSFileManager-Extensions
Source/Helpers/                Timing, FileSizeFormatter, FileSizeTransformer, AppsForItem
Source/TreeMapView/            the treemap widget — see its own section below
Resources/                     Images.xcassets (the app icon), AppIcon-master.png (its
                               source artwork, not in the Xcode project) and the toolbar plist
```

`Info.plist`, `version.plist`, the entitlements, `documentation/` and the five `.lproj`
bundles stay at the root: the localized nibs are the app's UI and moving them buys nothing.

Two build settings depend on this layout — update them together with any further move:

- `GCC_PREFIX_HEADER = "Source/App/Disk Inventory Next_Prefix.pch"`.
- `HEADER_SEARCH_PATHS` is `$(SRCROOT)` **and** `$(SRCROOT)/Source`. The second entry is
  what makes `#import <TreeMapView/…>` resolve to `Source/TreeMapView/`.

Plain `#import "Foo.h"` keeps working across directories because Xcode's header maps
(`USE_HEADERMAP`, on by default) map every project header by bare filename. That only
covers files that are *file references in the project* — a header that exists on disk but
was never added to the project will not be found from another directory.

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
- **`FSItem` owns nothing on the pasteboard.** `-declareTypes:owner:` does not retain its
  owner, and `FSItem` passes `self`; that is safe only because an item lives as long as
  the document's tree. Anything shorter-lived must not be a pasteboard owner. (The old
  `NTPasteboardHelper` existed to park a short-lived owner in a static set; it is gone.)

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

`FSItem` models one file, folder, or synthetic entry. It keeps a **name**, not a URL —
only the root of a scan keeps one, and `-fileURL` builds the rest from the parent chain on
demand. That is not a stylistic choice: a retained `NSURL` costs about 96 bytes, plus the
320-byte `_FileCache` CoreServices attaches to it the moment a resource value is read, plus
the path strings both hold. On a scan of `/` — 2.3 million items — those came to 57% of the
process against 7% for the `FSItem`s themselves, and dropping them took the tree from about
1,129 bytes an item to 214. So **anything the tree is asked for in bulk must be an ivar**
(name, folder-ness, alias-ness, both file sizes, kind); `-fileURL` is for one-off work on
one item — reveal in the Finder, the Info panel, dragging, an icon — and allocates a URL
per ancestor each time it is called. `FSItemType`
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

**The scan runs on a background queue** as of 2026-08-15; before that it was synchronous on
the main thread, pumping the event loop from inside the directory walk every 0.2 seconds.
`FileSystemDoc -_runScanBlockOffMainThread:` dispatches the walk and keeps the main thread
in the progress panel's modal session until it finishes.

What that means for anything touching the walk:

- **The `FSItemDelegate` callbacks run on the scan queue.** They must not touch a view.
  `-fsItemEnteringFolder:` records the path under `_scanLock` for the main thread to pick
  up, and answers `![self _scanWasCancelled]`. The three option callbacks answer from
  snapshots taken in `-_beginScan`, so the queue never reads document state the main thread
  could be writing.
- **All scans share one serial queue**, so two documents opening at once do not walk
  simultaneously, which matches the old behaviour where a second scan simply waited.
  *Within* one scan, subtrees are walked concurrently — the root is enumerated one level
  deep and each subdirectory handed to a queue, up to the `ScanConcurrency` preference
  (1–8, default 2; 1 is the serial walk). That is why the process-wide state the walk
  touches is now guarded: `g_fileCount`/`g_folderCount` are atomic, the two kind-name
  caches take a lock, and `LoadFirmlinks()` is a `dispatch_once`. Add anything
  process-wide to the walk and it needs the same treatment.
- **A directory that mirrors its own volume will be walked twice, and one exists.**
  `/.nofollow` sits at the root of the boot volume and its listing *is* the root's listing,
  itself included. A flat `NSDirectoryEnumerator` declines to descend into it unprompted,
  so this never mattered until subtrees got enumerators of their own — at which point a
  scan of `/` built 4,647,615 items where the volume holds 2,323,854, with the size and the
  memory to match. **The guard has to read a freshly made `NSURL`, not the one the
  enumerator handed back**: asked about `.nofollow` the enumerator's batched attributes say
  `NSURLIsVolumeKey` is false — they describe the entry as its parent sees it — while
  stat'ing that path on its own says true. `ShouldWalkSubtreeSeparately()` does both that
  and an `NSURLFileResourceIdentifierKey` comparison against the scan root, which is the
  general form: `/.nofollow`'s identifier is byte-for-byte `/`'s.
- **Nothing catches this except a scan whose root is a volume root.** No folder contains a
  mirror of its volume, so `/usr/share`, `/Applications` and `/System/Library` all pass
  while `/` is twice its true size. Test the walk against `/`, not only against folders.
- **The exception is carried back by hand.** The walk uses exceptions as ordinary control
  flow, and one raised on the queue cannot be caught on the main thread; the block catches
  it and `-_runScanBlockOffMainThread:` returns it to be re-raised.
- **`refreshFileKindStatistics` stays on the main thread.** It posts KVO for
  `kindStatistics`, which bound controls observe, and `-reserveColorsForLargestKinds`
  mutates the `FileTypeColors` singleton other documents read while drawing. It is also
  cheap next to the walk: measured over `/usr/share`, 20,179 items, the statistics pass
  takes 0.01 s against 0.16 s for the walk — it was 0.7 s for the walk when this was
  written, which is the measure of what has happened to the walk since.

**Moving the walk off the main thread did not make scanning faster** and was not meant to.
On a warm cache the times were the same within run-to-run variance (0.63–0.71 s before,
0.67 s median after). What it changed is that the main thread is no longer doing file I/O,
so the panel animates, Cancel responds at once, and the application stays usable — where it
used to be frozen between pumps, which on slow or network volumes is most of the time.

Scanning *did* get faster afterwards, and separately: the same folder now takes about
0.16 s and `/System/Library` went from 11.96 s to about 4.8 s. That came from asking
LaunchServices for a file's type once per extension rather than once per file, dropping
resource keys nothing read, and walking subtrees concurrently — not from the queue.

One measured trap: waking the main thread every 50 ms *and* redrawing the path label every
time cost about 7% of scan time. The label is throttled to 0.1 s separately from the wake
interval; keep those two numbers apart.

### Estimating scan progress

A directory walk has no total to divide by, so the panel gets one of two things:

- **What the last scan of this exact path found.** Every completed scan writes its item
  count to the `ScannedItemCounts` user default, keyed by path, and the next scan of that
  path divides by it. Exact by construction and self-correcting. It is internal state, not
  a setting, so it is deliberately not in `Info.plist`'s `Registrations`; entries for paths
  that no longer exist are pruned when it is written, so it cannot grow without bound.
- **`statfs` for a whole volume**, where `f_files - f_ffree` is the number of inodes in use
  and close to what the walk will visit. It answers for the *volume*, so it is no use for a
  folder inside one — asked about `/usr/share` it reports the boot volume's 458,726 against
  the 20,180 actually there. Hence the `isVolume` test.

With neither, the bar stays indeterminate and the percentage is blank rather than showing
a number that would be made up. The percentage is held at 99% until the scan really ends,
because the total is an estimate and a full bar over a still-running scan reads as a hang.

Counting is done in `-fsItemEnteringFolder:` by reading `g_fileCount + g_folderCount`,
which the walk increments on that same thread — so no synchronising is needed to read them,
only to publish the total. Folder granularity is plenty: a 20,000-item scan passes through
there about 900 times.

**Do not start the progress indicator's indeterminate animation unless you mean it.** Once
that animation is running inside a modal session, `-setIndeterminate:NO` does not reliably
stop it drawing: `-isIndeterminate` answers `NO` while the barber pole carries on over the
top of the value, so the bar and the percentage disagree — the label read 91% while the bar
showed a sliver at the far right. The panel therefore starts the indicator stopped, and
`-setProgressFraction:` animates it only in the no-estimate case.

Sizes are `unsigned long long` / `UInt64` throughout. Do not narrow them.

### Aggregation and lookup

`FileKindStatistic` (declared in `FileSystemDoc.h`, not its own file) aggregates count and
total size per file kind; the document keeps a kind-name → statistic dictionary and
recalculates it when view options change. `FSItemIndex` is a hand-rolled name/kind/path
index — the header notes SearchKit was tried and abandoned as too slow, so don't
"modernize" it back.

`FileTypeColors` assigns treemap colors per kind, reserving distinct colors for the
largest kinds. Kinds past the twelve-colour palette get a light grey ramp.

**The palette and the cushion shading are one design, not two.** Cushion shading darkens
each cell towards its rim, so a base colour is the *brightest* that cell will ever be. The
saturated primaries this started with — pure blue, pure red — therefore ran from full
intensity at the centre to near-black at the edge, which is what made the treemap read as
glowing blobs rather than as curved tiles.

The fix is not to pale the colours down. **Shading multiplies all three components by the
same number, so it changes value and never touches saturation** — which means a washed-out
treemap is always the palette's doing, not the shading's. A first attempt raised every
component to around 0.8; that produced a map that was light and unmistakably grey (mean
per-pixel saturation 0.26). The palette is now twelve hues 30° apart that keep a high peak
(~0.95) and let their other components fall to ~0.4, which more than doubles that figure
to 0.58.

Saturated colours darken into muddy ones — orange into brown — so the shading constants
in `TMVCushionRenderer` compensate: `Ia`, the unlit floor, is 0.68 (from 0.10), and
`TMVMaxColorBrightness`, the cap on a base colour's mean, is 0.85 (from 0.6). The dome is
still plainly visible because the remaining 0.32 of range falls over a curve.

Changing one without the other undoes it. A low `Ia` brings the dark rims back; a low
brightness cap dims everything to mud; a low-contrast palette turns the map grey however
light it is. `Ia + Is` must stay at 1.0 — that is what guarantees a pixel cannot exceed its
base colour, and it took the render from 81 clipped pixels to none.

A saturated colour has a *lower* mean than a pale one at the same peak, so raising the
brightness cap and raising saturation do not fight each other.

The two synthetic cells are deliberately neutral so they read as "not a file kind":
free space is the lightest thing on the map, other space a mid grey (set in
`TreeMapViewController treeMapView:willDisplayItem:withRenderer:`, not in the palette).

### What changed since the last scan

Two stores, and they are not the same thing. `DIXRecentScans` keeps **one total per
folder** in a user default — that is what the sidebar's SOURCES rows and the summary strip's
`+2.81 GB` are made of. `DIXScanHistory` keeps the sizes **inside** a scan, one plist per
scanned folder under Application Support, which is the only way to answer *what* changed
rather than *how much*. Both are read in `-readFromFile:ofType:` immediately before they are
overwritten, and the result is parked on the document (`-previousScanSize`,
`-previousScanDate`, `-changesSinceLastScan`) because no window exists yet.

The snapshot is bounded by a **megabyte floor applied on the way down**: a child cannot
exceed its parent, so a folder under the floor is never descended into. That, plus a
5,000-row cap, is what keeps a scan of a whole volume from writing a file the size of the
scan. The walk is iterative — `/` is deep enough in places that the stack is the wrong
place to find that out.

A folder and the one thing inside it that explains its change **collapse to one row**
(deeper wins at ≥90% of the same-signed delta), which is what names `IMG_4821.MOV` rather
than `Movies`, while still naming `DerivedData` rather than the thousand files under it.

Two things about the window (`DIXChangesController`, opened from the strip's *what grew*):

- **"Show only these on the map" dims, it does not remove** — the same choke point as the
  kind filter, `-[TreeMapViewController cellColorForItem:]`. Removing cells would relayout
  the map, and the one thing this window is built around is that a cell's area is its size.
  The two filters read as `AND`, so a kind and a change narrow together.
- **The filter is resolved to `FSItem`s once and re-resolved whenever the tree changes.**
  Paths outlive a refresh (which replaces items wholesale) and a trash (which removes one);
  resolved items do not. `-_resolveChangeFilter` runs beside `-_pruneReclaimBasket` at both
  `FSItemsChangedNotification` sites — dropping the filter instead would undo it at exactly
  the moment reviewing a change leads to trashing something.

### Controllers

`MainWindowController` owns the split view (outline + treemap) and nearly every `IBAction`
(zoom, refresh, trash, reveal in Finder, pane toggles). The per-view controllers
(`TreeMapViewController`, `FilesOutlineViewController`, `FileKindsTableController`,
`SelectionListTableController`) each manage one pane. `MyDocumentController` is an
`NSDocumentController` subclass handling app-level concerns (preferences panel, donation
panel, zoom-stack menu).

The kind statistics and selection list were `NSDrawer`s until 2026-08-15 — deprecated by
Apple and visually imperfect in dark mode, per `documentation/release notes.txt`. They are
now collapsible `NSSplitView` panes built in `-buildSidePanes`, statistics leading and
selection list below. `-toggleFileKindsDrawer:` and `-toggleSelectionListDrawer:` keep
their old names because the main menu nib and the toolbar plist name those selectors.

### Preferences: two layers

Global app settings are `NSUserDefaults` keys declared in `Preferences.h`. Some are read
through `boolForVersionDependantKey:`, a category that scopes a default to the app version
so "don't show this again" dialogs reappear after an upgrade. Separately, each document
holds a `_viewOptions` dictionary of per-window display toggles, accessed through the
`NSMutableDictionary(DocumentPreferences)` category. Adding a display toggle usually means
touching both layers plus a `ViewOptionChangedNotification` post.

**The settings pages are built in code, not in nibs.** A page overrides
`-[PrefsPageBase buildControlBox]` and describes itself through `PrefsPageLayout`: a
section label, then checkboxes, each optionally with explanatory text. Alignment is a
property of the layout rather than of whoever last opened Interface Builder — which is how
the two pages had drifted into different shapes, one of them with no label column at all.
Adding a setting is one `-addCheckboxTitled:defaultsKey:help:` call plus its string in the
four `Preferences.strings`, where it used to be eight nib bundles. There is one other
control: `-addPopUpWithValues:defaultsKey:trailingTitle:help:`, a pop-up of numbers with a
caption after it, used for `ScanConcurrency`. The values become the menu items' tags and
the binding is `NSSelectedTagBinding`, so what is stored is the number chosen rather than
where it sat in the menu.

`-buildControlBox` returning nil still falls back to loading the page record's nib, so a
page needing something a grid of checkboxes cannot express is not locked out.

Two things to know. Checkboxes bind to `NSUserDefaultsController`, which is what makes a
change take effect immediately and what lets Restore Defaults show up without reloading
the page. And **`PrefsPageLayout` must size its grid with `-setFrameSize:[grid fittingSize]`**
before returning it: the panel sizes the window from `-[pageView frame]`, and a grid that
has never been laid out still carries the frame it was created with — which produced a
736-point window around 552 points of content.

### Prefix header

`Source/App/Disk Inventory Next_Prefix.pch` is precompiled into every file and already
imports Cocoa and Carbon. It also defines the logging macro:

```objc
#define LOG(x, args...) { if (g_EnableLogging) NSLog(x, ## args); }
```

Use `LOG(...)` rather than bare `NSLog`; it is gated on the `EnableLogging` preference.

### macOS privacy-protected folders

Modern macOS blocks Desktop/Documents/Downloads and similar. `FileSystemDoc
checkForProtectedFolders:` detects them before scanning via
`privacyProtectedFoldersInURL:` (in `Source/Extensions/NSFileManager-Extensions`) and
shows a one-time explanatory alert gated on `DontShowPrivacyWarningMessage`.
`NSURL-Extensions` adds `stillExists` for revalidating URLs after a volume is ejected.
Background and localized strings: `documentation/macOS privacy protected folders.txt`.

## UI files are binary `.nib`, not `.xib`

Every interface lives in compiled `.nib` bundles under the `.lproj` directories. They are
not text and cannot be edited or diffed with normal tools — open them in Interface Builder.
Localizations: `de`, `en`, `es`, `fr` (`English.lproj` is a legacy leftover holding only
Help index files). Three nibs remain per language — `MainMenu`, `TreeMap`, `LoadingPanel`.
The three preference-page nibs were deleted on 2026-08-15 when those pages moved into code,
`InfoPanel` on 2026-08-20 when the inspector replaced the floating Info window, and
`VolumesPanel` on 2026-08-21 when the volume picker replaced the Drives panel. A UI change means updating the `.nib` in each of the four languages plus
`Localizable.strings`.

To change nib text without Interface Builder, round-trip through `ibtool`:

```sh
ibtool --generate-strings-file /tmp/x.strings en.lproj/MainMenu.nib   # extract
# edit /tmp/x.strings (it is UTF-16 — do not sed it blindly)
ibtool --strings-file /tmp/x.strings --write /tmp/new.nib en.lproj/MainMenu.nib
```

This recompiles `keyedobjects.nib` with the current Xcode toolchain, and the archive shrinks
(modern compiler, benign).

> **A per-OS variant beats the file you just edited.** Some `.nib` bundles also contain
> `keyedobjects-101300.nib`. AppKit **prefers** that variant on macOS 10.13 and later, so
> editing `keyedobjects.nib` alone changes nothing at runtime — and current `ibtool` cannot
> regenerate the variant, even with `--minimum-deployment-target`. An earlier version of
> this file claimed AppKit falls back to `keyedobjects.nib`; that is wrong, and it cost a
> debugging session. Delete the variant so the edited nib is the only one:
>
> ```sh
> find . -name "keyedobjects-*.nib" -not -path "./build/*"
> ```
>
> Only `en.lproj` and `fr.lproj/TreeMap.nib` ever had one, and both are now gone. The
> symptom is nasty: `de` and `es` pick up the edit while `en` and `fr` silently do not, so
> the app behaves differently per language. Worse, an edit can appear to work for the wrong
> reason — removing the `OASplitView` class made the stale nib fall back to `NSSplitView`
> because the custom class no longer existed, which looked exactly like success.

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

## `Source/TreeMapView/` — the replaced dependency

The app used to link four prebuilt frameworks. All four were Intel-only binaries with no
headers, which made an Apple silicon build impossible, and none was in the repo. **The app
now links only system frameworks.**

The OmniGroup half was migrated away entirely (see [Where the Omni code went](#where-the-omni-code-went)).
What remains is the treemap widget, in `Source/TreeMapView/`, resolved by
`HEADER_SEARCH_PATHS` (`$(SRCROOT)/Source`) rather than a framework search path, so
`#import <TreeMapView/…>` still works.

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
- **A remainder's count is `-[TMVItem mergedItemCount]`, never `mergedItems.count`.** One
  merged entry can be a folder packed in whole, and it stands for every file under it. The
  data source answers per item through `-treeMapView:itemCountByItem:`
  (`-[FSItem representedFileCount]`), summed once when the remainder is built because it
  walks. Counting entries instead understated `/usr/share` as 5,164 against 8,969.
- **The cache bitmap cannot be drawn into with AppKit.** It is 24-bit RGB with no alpha
  (`initRGBBitmapWithWidth:height:`), and CoreGraphics has no bitmap context of that shape:
  `+[NSGraphicsContext graphicsContextWithBitmapImageRep:]` answers **nil** for it, so an
  `NSRectFill` through it silently does nothing and the bitmap keeps the zeroes it was
  allocated with. That is where the map's black margin came from — it read as deliberate in
  dark and was plainly wrong in light. Write bytes, as `TMVCushionRenderer` does and as
  `-fillCache:withColor:` now does, using `-bytesPerRow` and `-bitsPerPixel`. A colour from
  the asset catalog must be resolved inside `-[NSAppearance performAsCurrentDrawingAppearance:]`
  first: this runs while building a bitmap, not while drawing into the view, so nothing has
  made the view's appearance current.

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
| `OAPasteboardHelper` | `NTPasteboardHelper`, then deleted — `FSItem` promises its own data via `-declareTypes:owner:self` |
| `OASplitView` | plain `NSSplitView` (`setPositionAutosaveName:` → `setAutosaveName:`) |
| `+[NSString isEmptyString:]`, `-[NSDictionary boolForKey:]`, `-[NSMutableDictionary setBoolValue:forKey:]`, the two `NSMutableArray` sorts, `+horizontalEllipsisString`, `-[NSTableView setFont:]` | inlined at their call sites |
| `OBPRECONDITION` | `NSAssert` (both compile out in release builds) |

`OASplitView` was the one class named inside the compiled nibs. It was removed by editing
the XIB and recompiling — see [Editing a nib without Interface Builder](#ui-files-are-binary-nib-not-xib).
Nothing else was ever nib-referenced, which is why the rest was a rename rather than a rewrite.

Two Omni mechanisms are gone rather than reimplemented, so **`Info.plist` no longer drives
them and `Source/App/main.m` does**: `NSPrincipalClass` is plain `NSApplication` (was `OAApplication`),
and `OFControllerClass` is removed. The factory defaults still live in `Info.plist`, now
under the `Registrations` key (`AppRegistrationsKey` in `Preferences.h`, renamed from
`OFRegistrations`), but `RegisterFactoryDefaults()` in `Source/App/main.m` registers them before
`NSApplicationMain`. **Adding a preference means adding it there**, or bound controls will
read nil. `PrefsPanelController` reads its page list from the same dict, keyed by its own
class name, and skips any page whose class is not in the binary. There used to be a third,
disabled `FinderCMPrefPage` entry relying on that; it was removed on 2026-08-15 along with
its nibs, since neither the class nor the page had existed for years.

`AppController` was an `OAController` and is now an empty `NSObject`; nothing instantiates
it, since only `OFControllerClass` ever did.

## Icons are SF Symbols, not files

There are no icon bitmaps. The 11 toolbar images and 3 preference-page images were
deleted on 2026-08-15 and replaced with SF Symbols, which is why the deployment target
is 11.0 — `+[NSImage imageWithSystemSymbolName:accessibilityDescription:]` needs it.

The symbol names are **data, not code**: they live in `Resources/Toolbar/MainWindowToolbar.toolbar`
under `symbolName` (plus `symbolNameOffState` / `symbolNameMixedState` for items with
state, currently only `ShowPackageContents`) and in `Info.plist`'s `Registrations` under
`symbol` for each preferences page. A typo compiles fine and shows an empty toolbar
button, so both go through `+[NSImage imageForSymbolName:accessibilityDescription:]`
(`Source/Extensions/NSImage-Extensions`), which returns nil and logs the bad name rather
than handing back a blank image. The accessibility description is the item's label, which
is what VoiceOver reads.

Adding a toolbar item means adding a `symbolName`, and checking the symbol exists **in
SF Symbols 2** — the app targets macOS 11, and the symbol set grows every release, so a
name that resolves on a current Mac may be missing on the oldest supported one.

`Resources/Images.xcassets/AppIcon.appiconset` is the app icon. All ten slots are filled,
1024px included, as of 2026-08-15 — the earlier artwork topped out at 512 and left that
slot empty. Three pixel sizes serve two slots each (32, 256, 512), and the catalog is
happy to name the same file twice rather than carry duplicates.

`Resources/AppIcon-master.png` is the 1280px source, kept in the repo but deliberately
**not** added to the Xcode project, so it is not copied into the bundle. It is there so
the sizes can be regenerated; the previous icon had no such master, which is exactly why
the 1024 slot sat empty.

macOS reads the icon from `Assets.car` via `CFBundleIconName`. `AppIcon.icns` is a
compatibility copy and `iconutil` only ever extracts four sizes from it — that is normal
and not a sign the catalog is short. To check what the system actually shows, ask
`-[NSWorkspace iconForFile:]` for the built `.app`.

## The title bar accessory, and why it is not the toolbar

The breadcrumb and the sidebar button live in an `NSTitlebarAccessoryViewController`
(`-installTitleAccessory`), not in the toolbar. That is forced, not stylistic.

The app builds against the macOS 26 SDK, so it opts into Liquid Glass, and **on macOS 26 a
toolbar draws every item inside a glass capsule** — the item's view goes into an
`NSToolbarItemViewer` inside an `NSGlassContainerView`. Right for the view-mode control and
the inspector button, which the design also draws with a background; wrong for the
breadcrumb, which is a title and came out looking like text inside a button.

Nothing supported switches the capsule off. `NSToolbarItemViewer` has `-glassBehavior` and
`-setTransparentBackground:`, and both are private. An accessory goes into an
`NSTitlebarAccessoryClipView` instead, never entering the glass container.

Four things here are not guessable:

- **A leading accessory is laid out before the toolbar's own items** — measured, the
  accessory at x=88 and the first toolbar item at x=274. That is why the sidebar button had
  to come along: left as `NSToolbarToggleSidebarItem` it would have sat to the *right* of
  the breadcrumb, where the design has it to the left. It is now a plain borderless
  `NSButton` targeting the window controller directly, so the responder-chain problem below
  no longer arises — `MainWindow`'s `-toggleSidebar:` override is kept for the menu.
- **`NSWindow` implements `-toggleSidebar:` itself**, so a nil-target action walks the
  responder chain and stops at the window, which comes *before* the window controller.
  AppKit's own sidebars do not hit this because `NSSplitViewController` sits ahead of the
  window via the content view controller.
- **The accessory is laid out from its view's frame, and the title bar does not watch it.**
  Widening the breadcrumb without `-setNeedsLayout:` on the clip view leaves the old width
  and clips the last segment. AppKit stretches the accessory to the full title-bar height
  (52 pt) whatever height its view was created at, so the children carry
  `NSViewMinYMargin | NSViewMaxYMargin` to stay centred.
- **`-[NSSplitView setPosition:ofDividerAtIndex:]` is not animatable.** Going through the
  `-animator` proxy sets it immediately; sampling the pane width midway showed it already
  at the target. `-animateKindStatisticsDividerTo:completion:` steps it on a timer
  instead, and `splitView:constrainMinCoordinate:ofSubviewAt:` has to stop enforcing its
  120-point minimum while that runs, or the slide stops dead instead of reaching zero.

The breadcrumb starts 14 pt past the sidebar's trailing edge, measured from the live pane
rather than from `[DIXTheme sidebarWidth]`, because the divider is draggable and the pane
collapses; `-splitViewDidResizeSubviews:` re-runs the layout. At the designed 244 pt
sidebar that puts it at x=258, which is where the design has it.

**The title bar's colours are painted by `-colourTitleBar`, into the theme frame.** AppKit's
own band is neither of the design's values — measured, `#2A353A` over a `#2F2C2B` sidebar,
cold slate on a warm window. `-setTitlebarAppearsTransparent:YES` opens the band up;
`_titleBarBand`, `_titleBarSidebarBand` and `_titleBarSidebarEdge` go into
`[[window contentView] superview]` **below every sibling**, so the traffic lights and the
toolbar stay above them. Three things to know:

- **The sidebar runs up through the title bar** in the design — its fill and its trailing
  border reach the top of the window, with the traffic lights sitting on them. It cannot be
  an accessory: a leading accessory is laid out after the traffic lights, so it never
  reaches x=0, and `NSTitlebarAccessoryClipView` clips it anyway.
- **Add them one above the last, not all `relativeTo:nil`.** `NSWindowBelow` against nil is
  below *everything*, which buried the edge under the band it is the edge of.
- **The window's background is `-ground`, not `-toolbar`**, since it reaches every part of
  the window nothing covers — there is a 9 pt strip between the file list and the map.

Sizes come from geometry, not constants: the band's height is the frame's less the content
view's, which is 0 in full screen and takes all three out of the way by itself.

**Glass cannot be screenshotted from inside the process.** `-cacheDisplayInRect:` over the
toolbar comes back fully transparent — the capsule is composited by the window server via
`CABackdropLayer`/`CAPortalLayer`, not drawn into the view tree. Verify this area by
asserting on the view hierarchy instead: the breadcrumb's ancestors must include
`NSTitlebarAccessoryClipView` and must not include `NSToolbarItemViewer`.

The flat fills *can* be, and from outside the process the whole window can: `screencapture
-x -o -l <windowid>` works, with the id from `CGWindowListCopyWindowInfo` (it is
`CGWindowListCreateImage` that is gone). **Dark-mode readings come back 8–15 per channel
lighter** through the sRGB conversion, light near-exact — so compare against the design's
*screenshots* rather than its hex values, which is what makes `#2a2827` and `#383534` the
same colour.

`-toolbarAutosaveIdentifier` is deliberately separate from `-toolbarConfigurationName`:
AppKit keys the saved toolbar layout on the `NSToolbar` identifier, so bumping it discards
a layout that refers to items which no longer exist. It is at `MainWindowToolbar-4` — most
recently because the breadcrumb and the sidebar button left the toolbar, and a saved layout
still naming both would draw a second sidebar button beside the accessory's own.
**Bump it again whenever items are removed**, or existing users keep a stale toolbar and
never see the new ones.

## Every scroll view goes through `DIXControls`

`+[DIXControls useOverlayScrollersIn:]` on each one, at the point it is built. Left alone,
a list carries a permanent scroll bar and loses 17pt of width to it, which no part of the
design has. Two separate causes, and both have to be dealt with:

- **`autohidesScrollers` defaults to `NO`**, and the file list's scroll view comes from
  `TreeMap.nib`, where nothing sets it. With legacy scrollers that keeps one drawn even
  when the content fits — measured, 17 points of a 200-point scroll view.
- **The system preference's default is "Automatic", which means legacy scrollers whenever a
  mouse is connected** — laid out beside the content rather than over it. An explicit
  "Always" is honoured, since that one is an accessibility choice made in System Settings;
  everything else becomes overlay.

`-setScrollerStyle:` does not stay set. `NSScrollView` observes
`NSPreferredScrollerStyleDidChangeNotification` and answers it by adopting the preferred
style again, so plugging a mouse in puts the gutter back. `DIXScrollerStyleKeeper` holds the
scroll views weakly and sets them again on the next turn of the run loop — not from inside
the notification, where AppKit's own handler may come second and win.

### Making a probe's window key

Anything that only draws when a view has the keyboard focus — the focus ring, a table's
emphasized selection — is invisible to a probe whose window never becomes key, and a bare
command-line tool's window never does. Wrap the probe in a minimal `.app` (an `Info.plist`
naming `CFBundleExecutable`, `CFBundleIdentifier` and `NSPrincipalClass`), build the views
in `-applicationDidFinishLaunching:` rather than before `-run`, `open` it, and screenshot
from the shell — `screencapture` inside the probe is a different responsible process and
has no screen-recording permission. `-[NSWindow isKeyWindow]` in the probe's own output
says whether it worked.

That is how the file list's blue-block selection was reproduced and killed, and how the
focus rings were confirmed gone.

**A probe will tell you there is nothing to fix.** `+[NSScroller preferredScrollerStyle]`
answers `Overlay` in a process with no window on screen and `Legacy` once one is up, because
the pointing device is only evaluated then. Two probes said overlay before a screenshot of
the real window showed the scroll bar plainly. Measure this one in a window, or from
outside the process.

## Pasteboard types have two spellings

Worth knowing before touching `FSItem`'s pasteboard code. Every type has a UTI and a
legacy NeXT/Apple name, and **they are different strings**: `NSPasteboardTypeHTML` is
`public.html`, `NSHTMLPboardType` is `Apple HTML pasteboard type`. `-declareTypes:`
advertises *both* whichever one is passed, so the outgoing side does not care — but a
receiver may ask for either, and a plain `-isEqualToString:` against one silently refuses
the other.

`PasteboardTypeMatches()` in `FSItem.m` compares against both, and every incoming
comparison goes through it. Renaming the deprecated constants to their modern equivalents
without it looks like a pure rename and is not: it broke HTML and plain-text requests made
with the legacy spelling, which a probe caught.

`NSFilenamesPboardType` has no modern equivalent and is deliberately still offered for
receivers that predate `NSPasteboardTypeFileURL`. It is reached through
`FSItemLegacyFilenamesPasteboardType()` so the deprecation is suppressed in exactly one
place.

## The donation panel

`DonationPanelController` (`Source/Panels/`) is shown once at first launch, until "Don't
show again" is ticked. It asks for two different things and **must not blur them**: support
for this fork, which goes to a crypto address, and support for Tjark Derlien, whose website
takes donations that do not reach the fork. The panel it replaced solicited under this app's
name and quietly sent people to his site, which was fair to neither party.

**The address exists once, as `kDonationAddress`.** The QR code is generated from that same
constant at runtime with `CIQRCodeGenerator` rather than shipped as an image — a QR that
disagreed with the address printed beside it would send someone's money somewhere neither
party chose, and an image asset is exactly the kind of thing that gets left behind when a
string changes. That is why `CoreImage.framework` is linked.

Two layout details that are not arbitrary. The address has its **own full-width row**: in
the column beside the QR there is not quite room for 42 monospaced characters and it wrapped
mid-address, which is how a transcription error starts. And it is **selectable as well as
copyable**, so someone who does not trust the button can select it by hand.

Changing the address means changing one constant. Check it afterwards by decoding the QR
out of the live view — a probe can pull the `NSImageView`'s image and run `CIDetector` over
it, which is how this was verified.

## The file info list

`DIXFileInfoView` (`Source/Panels/`) is the scrolling title/value list. It used to be three
vendored CocoaTech classes — `NTInfoView` gathering the rows, `NTTitledInfoView` laying
them out by hand, `NTTitledInfoPair` carrying one pair — all removed on 2026-08-15 along
with `NTFilePasteboardSource`, `NTPasteboardHelper` and the already-dead `NTID3Helper`.
**Nothing vendored remains; there is no `Source/CocoaTech-Depreciated/`.** That also
cleared the last files in the repo carrying "All rights reserved" with no license grant.

**The floating Info window it used to live in is gone** (2026-08-20). `InfoPanelController`
and the four `InfoPanel.nib`s were deleted; the design's inspector shows the same rows
against the same selection, and there is no second window to keep in step. Two leftovers are
deliberate: `-showInformationPanel:` keeps its name because `MainMenu.nib` names the
selector — it toggles the inspector now, and the menu item is retitled *Inspector* — and
`FileSystemDoc -setSelectedItem:` no longer pushes the selection at a view, which was the
one place the document drove a view instead of posting to it.

Two things about the view itself are easy to break:

- **The value column's width must come from the title column, never from the value field's
  own frame.** `NSGridView` sizes columns from their content, so a wrapping `NSTextField`
  whose `preferredMaxLayoutWidth` is derived from where it landed shrinks itself on every
  pass. Doing that collapsed the value column to five points and made the grid 1428 points
  tall instead of 166. `-finishRows` pins the title column to the widest title and `-layout`
  computes the rest from the grid's own width.
- **`-removeRowAtIndex:` leaves the row's content views as subviews.** They have to be
  removed by hand or every refresh stacks another set of labels on the last.

`NSLocalizedString` keys are the English strings themselves, and all twelve row titles
(`Name:` … `Application:`) exist in de/en/es/fr. Changing a literal means changing every
`Localizable.strings` too.

Two gaps are deliberate, inherited from the code this replaced: there is no **Size** row
(the old `sizePairs` was commented out and returned an empty array), and the "long format"
variant was dead code — `_longFormat` was never set.

**`usesInspectorLayout` is a second look, not a tweak**, and its numbers are the design's
markup for that block rather than anything chosen here: `padding: 12px 16px`, `gap: 10px`,
a fixed 74 pt key column in `muted` against values in `ink`, and **no rule between rows** —
the design rules the block once, underneath, which the inspector already draws as the
section hairline above the siblings list.

Its `NO` branch — ruled rows, right-aligned bold titles, `Name:`/`Path:` present — is the
floating panel's look and **now has no caller**: `DIXInspectorView` is the only thing that
builds one of these and it sets the flag immediately. Left in place rather than deleted with
the panel, so that the retirement commit stays a retirement; collapsing the two modes into
one is a tidy-up on its own.

Verifying a change here means rendering it, not reading it: a probe compiled into the built
`.app` can drive `-setURL:` and capture the view with `-dataWithPDFInsideRect:`.
`-cacheDisplayInRect:toBitmapImageRep:` returns blank, because the text fields are
layer-backed.

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
all 99 `fileEncoding` entries in `project.pbxproj` are `4` (`NSUTF8StringEncoding`). Keep
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

Licensed GPL-3 (`COPYING`). Most files inherited from upstream carry a GPL header naming
Tjark Derlien — preserve it when editing, never replace it. A handful carry no header at
all (`Timing.*`, `MainWindowController.h` and the three other `/* ClassName */` headers,
the prefix header); they are Derlien's too. As a modified version, the README must keep its
§5(a) modification notice and date.

Files written for this fork carry the same GPL-3 header under "Disk Inventory Next
contributors" — everything under `Source/TreeMapView/`, plus `PrefsPageRecord`,
`PrefsPageLayout`, `NSAlert-Extensions`, `NSImage-Extensions` and
`RegisterFactoryDefaults()` in `Source/App/main.m`. They are not Derlien's work and should
not be attributed to him. Files rewritten rather than written — `DIXFileInfoView` is the
clearest case — carry both. Match whichever header fits when adding a file.

By line count roughly 81% of the `.m`/`.h` still sits in files bearing Derlien's copyright
and 16% in fork-only files, though that undercounts the rewriting: the ARC migration, the
Info panel and the threading of the scan all happened inside files that keep his header.

**`Source/Views/ImageAndTextCell.*` is Apple sample code**, not GPL and not Derlien's. Its
licence does grant use, modification and redistribution in source and binary form, unlike
the CocoaTech files that were removed — but only on condition the notice is retained. Do
not strip it.

Before pulling in any third-party code, check that it is actually licensed. Being public on
GitLab or GitHub is not a license; `treemapview-framework` is the cautionary example
(see [`Source/TreeMapView/`](#sourcetreemapview--the-replaced-dependency) above).
