//
//  DIXStatusBarView.h
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

//The strip along the bottom of the map: what the pointer is over on the left,
//and a hint about what can be done with it on the right.
//
//It replaces two loose NSTextFields that sat at the bottom of TreeMap.nib and
//between them said only a name and a size. The figure worth having and missing
//from those is the share - what percentage of the scan the item under the
//pointer accounts for - because that is the number the treemap is drawing.

@interface DIXStatusBarView : NSView

//Height the window should give it. The design's 42pt.
+ (CGFloat) preferredHeight;

//The item under the pointer. Passing a nil name clears the whole left side.
//The chip carries the kind colour; pass nil for the synthetic cells, which have
//no kind.
- (void) setItemName: (NSString*) name
			  detail: (NSString*) detail
		   kindColor: (NSColor*) kindColor;

//the pointer left the map
- (void) clearItem;

//What the map could not draw, shown whenever nothing is under the pointer -
//"36,022 files are too small to draw" over "2.02 GB · 2.1% of this scan".
//Hovering a cell replaces it and moving off the map puts it back, so the figure
//is never in the way and never has to be gone looking for.
//
//It is here rather than in a corner of the map because the rule it serves is
//that space is never silently omitted: the cells cannot add up to the total the
//summary strip prints, and this is where that is admitted. Pass a nil summary
//when nothing was aggregated.
- (void) setIdleSummary: (NSString*) summary detail: (NSString*) detail;

//The right-hand hint, which changes with the view mode.
- (void) setHint: (NSString*) hint;

//Says something for a few seconds and then puts the hint back - "Freed 4.12 GB"
//after a trash. Calling it again restarts the clock rather than stacking.
- (void) flashMessage: (NSString*) message;

@end
