//
//  NSView-BackingCoordsHelpers.h
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

//AppKit's -convertRectToBacking: and friends only rescale; they leave the y
//axis pointing whichever way the view's coordinate system does. A bitmap always
//starts at its top-left corner, so for an unflipped view the y axis has to be
//mirrored as well or everything drawn into the bitmap comes out upside down.

@interface NSView(BackingCoordsHelpers)

- (NSPoint) convertPointToBackingRespectingFlipped: (NSPoint) point;
- (NSPoint) convertPointFromBackingRespectingFlipped: (NSPoint) point;

- (NSSize) convertSizeToBackingRespectingFlipped: (NSSize) size;
- (NSSize) convertSizeFromBackingRespectingFlipped: (NSSize) size;

- (NSRect) convertRectToBackingRespectingFlipped: (NSRect) rect;
- (NSRect) convertRectFromBackingRespectingFlipped: (NSRect) rect;

@end
