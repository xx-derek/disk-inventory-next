//
//  DIXControls.h
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

//The handful of elements the design repeats across every screen. They live
//here rather than being redrawn per call site because the design's rules about
//them are easy to break one at a time: chips and bars are square while every
//button is 6pt, and the 2pt section rules must not soften into hairlines.

#pragma mark --------kind chip-----------------

//The 10x10 square that stands for a file kind, in the sidebar legend, the file
//list, the status bar and the change view. Square on purpose - it is a data
//element, not a control.
@interface DIXKindChip : NSView

+ (instancetype) chipWithColor: (NSColor*) color;

@property (nonatomic, strong) NSColor *color;
@property (nonatomic, assign) CGFloat  chipSize;    //defaults to DIXTheme.kindChipSize

@end

#pragma mark --------share bar-----------------

//The thin proportion bar under a sidebar row, a kind row or a volume card.
//Height comes from the frame; the design uses 3pt in the legend, 4pt in
//SOURCES and 6pt on the volume cards.
@interface DIXShareBar : NSView

+ (instancetype) barWithFraction: (double) fraction fillColor: (NSColor*) fillColor;

//clamped to 0...1; values outside that are a bug in the caller's arithmetic
//rather than something to draw
@property (nonatomic, assign) double   fraction;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *trackColor;  //defaults to [DIXTheme barTrack]

@end

#pragma mark --------rules and labels-----------------

@interface DIXControls : NSObject

//2pt ink. Between major sections, and never softened - the design is explicit
//that a hairline here undoes it.
+ (NSBox*) sectionRule;

//1pt separator, between rows within a section
+ (NSBox*) rowSeparator;

//A section header: 11pt bold, letterspaced, uppercased. The caller passes the
//title in its natural case and this uppercases it, so the localized string
//stays readable in the .strings files.
+ (NSTextField*) sectionLabelWithTitle: (NSString*) title;

#pragma mark --------buttons-----------------

//One shape everywhere: a push button at 6pt radius. Only the fill changes.

//Solid accent with a white label. The primary action, and destructive ones:
//Scan, Copy address, Trash, Move to Trash, Delete..., Review...
+ (NSButton*) primaryButtonWithTitle: (NSString*) title
							  target: (id) target
							  action: (SEL) action;

//White with a hairline border. Choose..., Open, Restore..., Cancel, Rescan.
+ (NSButton*) secondaryButtonWithTitle: (NSString*) title
								target: (id) target
								action: (SEL) action;

//Puts "gap" points between a button's image and its title.
//
//NSButton has no such property - imageHugsTitle changes nothing for a rounded
//bezel, measured, and a paragraph style's firstLineHeadIndent is ignored by the
//cell - so the space is a leading space in an attributed title, kerned out to
//the width asked for. The accessible title is set separately, so what VoiceOver
//reads has no stray space in it.
+ (void) setImageTitleGap: (CGFloat) gap onButton: (NSButton*) button;

@end
