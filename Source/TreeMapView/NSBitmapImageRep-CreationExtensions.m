//
//  NSBitmapImageRep-CreationExtensions.m
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

#import "NSBitmapImageRep-CreationExtensions.h"
#import "NSView-BackingCoordsHelpers.h"

@implementation NSBitmapImageRep(CreationExtensions)

- (id) initRGBBitmapWithWidth: (NSInteger) width height: (NSInteger) height
{
	if ( width < 1 ) width = 1;
	if ( height < 1 ) height = 1;

	return [self initWithBitmapDataPlanes: NULL
							   pixelsWide: width
							   pixelsHigh: height
							bitsPerSample: 8
						  samplesPerPixel: 3
								 hasAlpha: NO
								 isPlanar: NO
						   colorSpaceName: NSCalibratedRGBColorSpace
							 bitmapFormat: 0
							  bytesPerRow: 0		//let AppKit pick the row padding
							 bitsPerPixel: 0];
}

+ (NSBitmapImageRep*) imageRepCompatibleWithView: (NSView*) view
{
	const NSSize backingSize = [view convertSizeToBackingRespectingFlipped: [view bounds].size];

	NSBitmapImageRep *bitmap = [[self alloc] initRGBBitmapWithWidth: (NSInteger) ceil( backingSize.width )
															height: (NSInteger) ceil( backingSize.height )];

	return bitmap;
}

- (NSImage*) suitableImageForView: (NSView*) view
{
	//the rep counts in pixels, the image in points; setting the size explicitly
	//is what tells AppKit the difference on a Retina display
	const NSSize pointSize = [view convertSizeFromBackingRespectingFlipped:
								   NSMakeSize( [self pixelsWide], [self pixelsHigh] )];

	NSImage *image = [[NSImage alloc] initWithSize: pointSize];
	[image addRepresentation: self];

	return image;
}

@end
