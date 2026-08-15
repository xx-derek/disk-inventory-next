//
//  NSImage-Extensions.h
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

@interface NSImage(DiskInventoryExtensions)

//Looks up an SF Symbol by name, for the toolbar and the preferences panel,
//which both take their symbol names from a property list.
//
//A symbol that does not exist on the running system returns nil rather than a
//blank image, so the caller can say which name was wrong. That matters because
//the names are data, not code: a typo in the plist cannot be caught by the
//compiler, and the symbol set grows with each macOS release, so a name that
//works here may be missing on the oldest system the app still supports.
//
//The description becomes the image's accessibility description, which is what
//VoiceOver reads for a toolbar button; pass the item's label.
+ (NSImage*) imageForSymbolName: (NSString*) symbolName
	   accessibilityDescription: (NSString*) description;

@end
