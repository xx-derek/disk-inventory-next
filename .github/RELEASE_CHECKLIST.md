# Release checklist

Things a person has to check, because a probe cannot. Almost everything in this fork's
interface was verified by compiling test harnesses into the built `.app` and by taking
screenshots — which proves the code does what it was written to do, and proves nothing
about whether the app is pleasant to use or whether a click lands where it looks.

Each item says how confident we already are:

- **confirmed** — someone has actually used it since the change; re-check for regressions
- **probe only** — verified programmatically or from a screenshot, never clicked
- **never run** — nobody has exercised this at all

---

## Before you start

- [ ] Build Release and confirm 0 warnings:
      `xcodebuild -project "Disk Inventory Next.xcodeproj" -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" build`
- [ ] **Reset to a first-run state**, or most of the first-launch checks below are
      meaningless — the app remembers everything:
      `defaults delete io.github.xxderek.DiskInventoryNext`
      That clears the donation panel's "don't show again", every preference, the toolbar
      layout, the window and split positions, and the remembered scan sizes.
- [ ] Test on a **second Mac** if you can, ideally Intel. The universal binary's x86_64
      slice has never been run — every build and every test in this fork has been on
      Apple silicon.

## First launch — *never run as a sequence*

- [ ] App icon looks right in Finder, in the Dock, and in the menu bar. Check it small:
      the 16pt sizes were only added recently and are downscaled from the 512.
- [ ] **Donation panel** appears, and only once. *(never run — built, then screenshotted)*
  - [ ] QR code scans with a phone wallet and yields
        `0xe56f2b8e59c96e2bcb7b4d9f636cb3badfdd5abc`
  - [ ] **Compare the scanned address against the text** character by character
  - [ ] "Copy Address" copies the same string; paste it somewhere and compare
  - [ ] "Support the Original Author…" opens derlien.com
  - [ ] "Don't show again" sticks across a relaunch
- [ ] **About box**: version reads 1.0.0 (1), the credits scroll, the copyright is legible
      and mentions both holders. *(probe only)*
- [ ] Volumes panel lists your drives with correct sizes and usage bars.

## Scanning — *the riskiest area*

- [ ] Scan a whole volume. *(confirmed)*
- [ ] Scan a folder. *(confirmed)*
- [x] **Cancel a long scan.** *(confirmed by hand, after subtrees began being walked
      concurrently — this is the one path where a mistake hangs the app rather than
      merely looking wrong.)* Still worth repeating on a **network share**, which is
      where a cancelled walk has the longest to wait on something, and which the
      by-hand run is not known to have covered. The window should close cleanly and
      the app stay responsive.
- [ ] While a scan runs, confirm the app is genuinely usable: move the window, switch to
      another app and back, watch the progress bar animate smoothly rather than in jerks.
- [ ] Progress percentage is sensible. *(confirmed)* The **first** scan of a folder shows
      no percentage and a barber-pole bar — that is correct, not a bug; the second scan of
      the same path shows a percentage.
- [ ] Scan something in Desktop/Documents/Downloads and check the privacy explanation
      appears before the system prompt. *(never run)*
- [ ] Eject a volume mid-scan, or scan a disconnecting network share. Should fail
      gracefully, not crash.
- [ ] Refresh (all, and selection).

## Treemap

- [ ] Colours are readable and distinct at a glance. *(probe only — rendered, never
      viewed in the app over a long session)*
- [ ] Clicking a cell selects the matching row in the outline. *(confirmed)*
- [ ] Tooltips and the name/size readout under the map follow the pointer.
- [ ] Zoom in and out, including the animation, and the zoom-stack menu.
- [ ] Free space and other space cells appear when enabled and are visually distinct from
      file kinds.
- [ ] A folder with **more than twelve file kinds** — the thirteenth used to be drawn
      black. *(fixed, probe only)*

## Panes and toolbar

- [ ] **Sidebar button toggles the file-kind statistics pane**, and the pane slides.
      *(never run — I could not click it; the action reaches the window controller only
      because MainWindow forwards `toggleSidebar:`, which is exactly the kind of thing
      that silently does nothing.)*
- [ ] View menu still toggles the same pane and its title flips Show/Hide.
- [ ] Selection list pane toggles.
- [ ] Every toolbar icon is a recognisable SF Symbol and enables/disables correctly with
      the selection. *(probe only)*
- [ ] **Customize Toolbar** works, and the toolbar resets once on first launch after the
      upgrade — the autosave identifier was bumped deliberately.
- [ ] Split dividers drag, and positions survive a relaunch.

## File actions

- [ ] Drag a file to the Finder — a **copy**, not an alias. *(confirmed)*
- [ ] Copy (⌘C) and paste into Finder. *(confirmed)*
- [ ] Services menu on a selected file. *(probe only — the registered send types were
      fixed, but no service has actually been invoked)*
- [ ] Reveal in Finder.
- [ ] Open, and Open With… for a file with several handlers.
- [ ] Move to Trash, including the confirmation, and check the treemap updates.

## Info panel — *rebuilt, probe only*

- [ ] Opens, and follows the selection.
- [ ] Check a plain file, a folder, an application bundle (should show Version), an alias
      or symlink (should show Resolved), and something with a very long path (should wrap,
      not truncate).
- [ ] Values are selectable — try selecting the path and copying it.
- [ ] Permissions match `ls -l` for a couple of files, including a setuid one such as
      `/usr/bin/sudo`.

## Settings — *redesigned, probe only*

- [ ] ⌘, opens it; the menu item and window read "Settings" on macOS 13+.
- [ ] Both pages align consistently; help text reads as secondary.
- [ ] **Scan concurrency**: the pop-up under "Scanning:" offers 1-8 and defaults to 2.
      Set it to 1 and confirm a scan still completes (that is the serial walk); set it
      to 8 and confirm a scan is faster and still correct. *(probe only)*
- [ ] **Cancel a scan at each end of that range** - 1 and 8. Cancellation crosses
      queues now, so it is worth exercising at both. *(confirmed by hand from the
      panel at the default of 2; the probe cancels cleanly at 1, 5, 50, 500 and
      5,000 folders)*
- [ ] **Every checkbox actually changes behaviour** — this is the real test. Toggle each
      and confirm the effect in a new window: package contents, creator code, physical
      size, horizontal split, the three small-font options, shared kind colours, animated
      zooming, free space, other space.
- [ ] Restore Defaults asks first, then visibly resets the checkboxes.
- [ ] Settings survive a relaunch.

## Localizations — *the least verified area*

Run with `AppleLanguages`, e.g.
`open -a "Disk Inventory Next" --args -AppleLanguages '(de)'`

- [ ] German, Spanish and French: the app comes up translated and nothing shows a raw
      English key.
- [ ] **Settings pages in each language.** Their text was migrated out of deleted nibs
      into `Preferences.strings`; it resolved programmatically, but the layout was only
      ever seen in German.
- [ ] **Have a speaker check the strings I invented**: "File kind colors:", "Zooming:",
      "Restore Defaults", "Settings", "Settings…", and the three added for scan
      concurrency - "Scanning:", "folders at a time", and its explanatory sentence,
      whose German, Spanish and French are mine and not a translator's. The other
      settings text is the original translators' work and should be sound.
- [ ] The donation panel is **English only** — decide whether that ships.

## Menus and help

- [ ] Help → Disk Inventory Next Help opens the help book.
- [ ] Every menu item does something or is correctly disabled; nothing crashes.
- [ ] Window title, document proxy icon, and the recent-documents menu.

## Release mechanics — *never run*

- [ ] Push a tag and let the workflow run. Expect it to need a correction: signing and
      notarization have never been exercised.
- [ ] Download the artifact **through a browser**, so it really gets quarantined, and
      follow the install instructions in the release notes exactly as written.
- [ ] Confirm the app opens on a Mac that has never had the source on it.

## Open decisions

- [ ] **Credit the app icon's author.** It arrived as a zip and nobody is named for it.
      The README still credits Anton Repponen for the original icon it replaced.
- [ ] **Confirm 1.0.0 is the version you want.** It is a judgment call — a clean start for a
      renamed product rather than continuing Derlien's 1.4.
- [ ] Two inherited bugs are still open in `documentation/known bugs.txt`: unreadable
      directories report size 0, and a focus-ring artefact when resizing the split.
