//
//  NSBitmapImageRep-CreationExtensions.h
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

@interface NSBitmapImageRep(CreationExtensions)

//an opaque RGB bitmap, one byte per component and no padding between pixels,
//so the cushion renderer can write straight into -bitmapData
- (id) initRGBBitmapWithWidth: (NSInteger) width height: (NSInteger) height;

//a bitmap sized in the view's backing pixels, so the treemap is rendered at
//full resolution on a Retina display rather than being scaled up
+ (NSBitmapImageRep*) imageRepCompatibleWithView: (NSView*) view;

//wraps the receiver in an image whose size is in points, so drawing it into
//the view maps one bitmap pixel onto one backing pixel
- (NSImage*) suitableImageForView: (NSView*) view;

@end
