//
//  DIXTheme.h
//  Disk Inventory Next
//
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import <Cocoa/Cocoa.h>

//The design tokens, in one place, so a colour or a type size is never written
//twice. Every colour is an asset-catalog entry with an Any/Dark pair, taken
//from the handoff's dark-mode table - which is a second token set, not a
//filter: nothing is inverted or dimmed, and several roles move in opposite
//directions between the two.
//
//Nothing here branches on the appearance, and nor should any caller. The one
//exception in the application is TMVCushionRenderer, whose constants are
//numbers rather than colours; it reads the appearance when it builds its
//bitmap and the view invalidates that on -viewDidChangeEffectiveAppearance.

@interface DIXTheme : NSObject

#pragma mark --------surfaces-----------------

//The desk the window sits on.
+ (NSColor*) ground;

//content surfaces: the treemap's inset, list backgrounds, cards
+ (NSColor*) surface;       // #ffffff

//Chrome that is not content: the inspector and the status bar.
+ (NSColor*) chrome;

//The toolbar band.
+ (NSColor*) toolbar;

//A recessed well - a search field, the path chip in settings, the track behind
//a segmented control. In dark it is *darker* than the surface, which is what
//makes it read as recessed rather than raised.
+ (NSColor*) well;

//A raised control's fill.
+ (NSColor*) controlFill;

//Sidebar fill.
+ (NSColor*) sidebar;

//the row highlight the design uses in the sidebar and the kinds legend
+ (NSColor*) selectedRowFill;   // ~#e2dedb / #e7e4e2

#pragma mark --------text-----------------

+ (NSColor*) ink;               // #201e1d
+ (NSColor*) bodyText;          // ~#56524f
+ (NSColor*) secondaryText;     // ~#7d7875 / #8d8885
+ (NSColor*) tertiaryText;      // ~#9a9694

#pragma mark --------lines-----------------

//Pane borders - between the sidebar and the map, above the status bar.
+ (NSColor*) hairline;

//The 1pt line between rows within a section. Lighter than a pane border; the
//design gives them different values and they are no longer conflated.
+ (NSColor*) rowSeparator;

//The 2pt rules between major sections. These are ink, not hairlines - the
//design is explicit that softening them undoes it.
+ (NSColor*) rule;

//borders on secondary buttons and control-sized boxes
+ (NSColor*) controlBorder;     // ~#ceccc9

#pragma mark --------accent-----------------

//The one literal colour family. Reserved for: the primary action, the delta
//figure, the kind-filter affordance, the selected treemap outline, and the
//reclaim/trash buttons. Everything else is neutral.
+ (NSColor*) accent;            // #ec3013
+ (NSColor*) accentPressed;     // #b8250e
+ (NSColor*) accentTint;        // #fdf1ef

//What a label on an accent fill is drawn in. Not always white: the dark
//accent (#ff5a3c) is light enough that white on it fails, so in dark mode a
//label on the fill is near-black. Accent as *text* stays the accent.
+ (NSColor*) onAccent;          // #ffffff light / #1c1b1a dark

//shrinkage in the change view; growth uses the accent
+ (NSColor*) positive;          // #3d7a3d

//The flat "elsewhere" tile - neutral on purpose, since it is not a file kind.
+ (NSColor*) neutralFill;

//Between sections *inside* a pane, where -hairline separates the panes
//themselves. The design draws three weights of line and this is the middle one;
//using the pane border for both makes every internal division too heavy.
+ (NSColor*) contentHairline;   // #e6e3e1 / #333130

//A band that sits above the surface it is on - the inspector's reclaim bar.
//One step lighter than the pane in light, one step lighter in dark too, which
//is why it pairs with neither -surface nor -sidebar.
+ (NSColor*) raised;            // #ffffff / #232120

//The unfilled part of a share bar. Two of them: a share bar on a highlighted
//row sits on a darker background than one on the sidebar's own, so it needs a
//deeper track to read as a track at all.
+ (NSColor*) barTrack;          // #e2dfdd / #333130
+ (NSColor*) barTrackDeep;      // #d3cfcc / #161514

//Quieter than secondaryText and, unlike it, the *same* step in both
//appearances. Section labels, and a share bar that is not the current one.
+ (NSColor*) muted;             // #8d8885 / #7d7875

//The free-space cell: a pale fill inside a dashed outline, drawn as an absence
//rather than as a tile.
+ (NSColor*) freeSpaceFill;
+ (NSColor*) freeSpaceDash;

#pragma mark --------type-----------------

//Display numerals and headlines: bold system font, which is SF Pro Display at
//these sizes. The design asks for Archivo 700 and names this as an acceptable
//substitute; the size and weight jump is what makes the totals read, so keep
//the sizes even where the face differs.
+ (NSFont*) displayFontOfSize: (CGFloat) size;

//section labels: 11pt bold, letterspaced, uppercased by the caller
+ (NSFont*) sectionLabelFont;

//Size columns and any figure that sits above or below another. Proportional
//digits make a column of sizes ripple as it updates.
+ (NSFont*) tabularFontOfSize: (CGFloat) size;

//the donation address, and the history path chip in settings
+ (NSFont*) monoFontOfSize: (CGFloat) size;

//Display type carries -0.02em tracking in the design, which is a kern
//attribute rather than a font trait - so display text has to be drawn from an
//attributed string to get it. This builds one.
+ (NSDictionary<NSAttributedStringKey, id>*) displayAttributesOfSize: (CGFloat) size
															   color: (NSColor*) color;

//and the same for a section label, including the uppercasing convention
+ (NSDictionary<NSAttributedStringKey, id>*) sectionLabelAttributes;

#pragma mark --------metrics-----------------

//6pt on every button and system control, matching AppKit. Data elements -
//kind chips, share bars, section rules, the address box - stay square; that is
//where the system's own geometry belongs.
+ (CGFloat) cornerRadius;           // 6

+ (CGFloat) ruleThickness;          // 2
+ (CGFloat) hairlineThickness;      // 1
+ (CGFloat) kindChipSize;           // 10

+ (CGFloat) sidebarWidth;           // 244
+ (CGFloat) inspectorWidth;         // 300
+ (CGFloat) fileListWidth;          // 320

//Below this the window falls back to Map mode: sidebar + list + a usable map
//does not fit, and three cramped columns are worse than one good one.
+ (CGFloat) bothModeMinimumContentWidth;    // 1000

@end
