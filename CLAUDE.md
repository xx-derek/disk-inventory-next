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

Single Xcode target, `Disk Inventory Next` (application). Deployment target macOS 11.0;
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
Source/Preferences/            Preferences, PrefsPanelController, PrefsPageBase/Record, the pages
Source/Views/                  DIXTableView, DIXOutlineView, ImageAndTextCell, GenericArrayController
Source/Extensions/             NSAlert-, NSURL- and NSFileManager-Extensions
Source/Helpers/                Timing, FileSizeFormatter, FileSizeTransformer, AppsForItem
Source/TreeMapView/            the treemap widget — see its own section below
Resources/                     Images.xcassets (the app icon) and the toolbar plist
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
four `Preferences.strings`, where it used to be eight nib bundles.

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
Help index files). Six nibs remain per language — `MainMenu`, `TreeMap`, `InfoPanel`,
`LoadingPanel`, `VolumesPanel`, `DonationPanel`; the three preference-page nibs were
deleted on 2026-08-15 when those pages moved into code, and their translations moved into
`Preferences.strings`. A UI change means updating the `.nib` in each of the four languages plus
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
class name, and skips any page whose class is not in the binary — which is why the disabled
`FinderCMPrefPage` entry is harmless.

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

## The sidebar toggle

The statistics pane is toggled by `NSToolbarToggleSidebarItemIdentifier` — AppKit's own
item, so the glyph, the leading placement and the short localized label ("Sidebar") come
from the system. `ToolbarWindowController` gets it for free: it returns nil for any
identifier with no `itemInfoByIdentifier` entry, and AppKit builds standard items itself.

Three things here are not guessable, and each one cost a probe:

- **`NSWindow` implements `-toggleSidebar:` itself.** The standard item has a nil target,
  so the action walks the responder chain — and the walk stops at the window, which comes
  *before* the window controller. Left alone the button is present, enabled, and does
  nothing. `MainWindow` overrides `-toggleSidebar:` and forwards to its window controller;
  that forward is the only reason the button works. AppKit's own sidebars do not need it
  because `NSSplitViewController` sits ahead of the window via the content view controller.
- **The identifier's *value* is `NSToolbarToggleSidebarItem`**, not
  `…ItemIdentifier`. The plist stores values, as the neighbouring
  `NSToolbarFlexibleSpaceItem` shows. Writing the constant's name gives an item AppKit
  silently declines to build.
- **`-[NSSplitView setPosition:ofDividerAtIndex:]` is not animatable.** Going through the
  `-animator` proxy sets it immediately; sampling the pane width midway showed it already
  at the target. `-animateKindStatisticsDividerTo:completion:` steps it on a timer
  instead, and `splitView:constrainMinCoordinate:ofSubviewAt:` has to stop enforcing its
  120-point minimum while that runs, or the slide stops dead instead of reaching zero.

`-toolbarAutosaveIdentifier` is deliberately separate from `-toolbarConfigurationName`:
AppKit keys the saved toolbar layout on the `NSToolbar` identifier, so bumping it discards
a layout that refers to items which no longer exist. It was bumped to `MainWindowToolbar-2`
when the drawer toggle gave way to this item. **Bump it again whenever items are removed**,
or existing users keep a stale toolbar and never see the new ones.

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

## The Info panel

`DIXFileInfoView` (`Source/Panels/`) is the scrolling title/value list. It used to be three
vendored CocoaTech classes — `NTInfoView` gathering the rows, `NTTitledInfoView` laying
them out by hand, `NTTitledInfoPair` carrying one pair — all removed on 2026-08-15 along
with `NTFilePasteboardSource`, `NTPasteboardHelper` and the already-dead `NTID3Helper`.
**Nothing vendored remains; there is no `Source/CocoaTech-Depreciated/`.** That also
cleared the last files in the repo carrying "All rights reserved" with no license grant.

Three things about the replacement are easy to break:

- **The class name is load-bearing.** All four `InfoPanel.nib`s hold an `NSCustomView`
  placeholder naming `DIXFileInfoView`. A placeholder instantiates through
  **`-initWithFrame:`**, not `-initWithCoder:` — which is why the old code's subviews
  existed at all, and why both initialisers now funnel into `-buildViewHierarchy`. Rename
  the class and the panel silently comes up empty.
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

Files written for this fork (everything under `Source/TreeMapView/`, `PrefsPageRecord`,
plus `RegisterFactoryDefaults()` in `Source/App/main.m`) carry the same GPL-3 header under "Disk Inventory
Next contributors" — they are not Derlien's work and should not be attributed to him. Match
whichever header fits when adding a file.

Before pulling in any third-party code, check that it is actually licensed. Being public on
GitLab or GitHub is not a license; `treemapview-framework` is the cautionary example
(see [`Source/TreeMapView/`](#sourcetreemapview--the-replaced-dependency) above).
