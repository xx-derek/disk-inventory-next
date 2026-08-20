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
//twice. The design was drawn light-only with literal hex values; everything
//neutral here is instead a semantic NSColor, which lands close to the drawn
//value in light mode and keeps dark mode working. Only the accent family is
//literal, as asset-catalog colours with hand-picked dark variants.
//
//Where a semantic colour is not an exact match for the design's hex the
//comment says so. Those differences are deliberate: the platform's own value
//is the one that stays right when Apple changes it, and a 1-2% neutral step
//is not what makes the design read.

@interface DIXTheme : NSObject

#pragma mark --------surfaces-----------------

//The window's own background. Semantic, and the right thing to give a window.
+ (NSColor*) ground;

//content surfaces: the treemap's inset, list backgrounds, cards
+ (NSColor*) surface;       // #ffffff

//One step off the content surface, for chrome that is not content: status bar,
//inspector, cards, toolbar fills. The design separates ground (#f3f2f2),
//toolbar (#f6f5f4) and inspector (#faf9f8) by a percent or two.
//
//This one token is derived rather than semantic, and that is deliberate:
//measured on macOS 26, -windowBackgroundColor, -controlBackgroundColor and
//-textBackgroundColor all resolve to the same value (#ffffff light, #1e1e1e
//dark), so no pair of semantic colours can express the step any more. AppKit
//now draws that separation with NSVisualEffectView materials instead - so
//prefer a material (.headerView, .sidebar, .contentBackground) where a view
//can have one, and use this only for flat fills that cannot.
+ (NSColor*) chrome;

//Sidebar fill. NSSplitViewItem +sidebarWithViewController: supplies the real
//sidebar material on its own, so this is for sidebar-like fills elsewhere.
+ (NSColor*) sidebar;       // ~#efedec

//the row highlight the design uses in the sidebar and the kinds legend
+ (NSColor*) selectedRowFill;   // ~#e2dedb / #e7e4e2

#pragma mark --------text-----------------

+ (NSColor*) ink;               // #201e1d
+ (NSColor*) bodyText;          // ~#56524f
+ (NSColor*) secondaryText;     // ~#7d7875 / #8d8885
+ (NSColor*) tertiaryText;      // ~#9a9694

#pragma mark --------lines-----------------

//0.5pt pane borders and hairlines, and the 1pt separator between rows. The
//design distinguishes #d9d6d4, #e6e3e1 and #eeecea; separatorColor is the
//platform's single answer to all three and the thickness carries the
//difference, which is what the eye reads anyway.
+ (NSColor*) hairline;

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

//shrinkage in the change view; growth uses the accent
+ (NSColor*) positive;          // #3d7a3d

//the flat fill for "other space" - neutral on purpose, since it is not a kind
+ (NSColor*) neutralFill;       // ~#b9b5b2

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
