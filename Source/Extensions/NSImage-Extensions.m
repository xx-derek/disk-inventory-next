//
//  NSImage-Extensions.m
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

#import "NSImage-Extensions.h"

@implementation NSImage(DiskInventoryExtensions)

+ (NSImage*) imageForSymbolName: (NSString*) symbolName
	   accessibilityDescription: (NSString*) description
{
	if ( [symbolName length] == 0 )
		return nil;

	NSImage *image = [NSImage imageWithSystemSymbolName: symbolName
							   accessibilityDescription: description];

	if ( image == nil )
	{
		//worth a log rather than a silent gap: the name came from a plist, so
		//nothing earlier could have checked it
		NSLog( @"no SF Symbol named '%@'", symbolName );
		return nil;
	}

	//A symbol is a template by default, so the toolbar tints it for the current
	//appearance and for the enabled/disabled state. Saying so explicitly keeps
	//that true if the image is ever handed somewhere that does not assume it.
	[image setTemplate: YES];

	return image;
}

@end
