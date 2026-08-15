//
//  NTPasteboardHelper.h
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

//A pasteboard owner has to stay alive for as long as the pasteboard might ask
//it for data, which can be long after whatever put it there has gone away.
//NSPasteboard does not retain its owner, so the helper stands in as the owner,
//keeps both itself and the real one alive, and lets go once another application
//takes the pasteboard over.

@interface NTPasteboardHelper : NSObject
{
	NSPasteboard *_pasteboard;
	id _owner;
	BOOL _isOwning;
}

+ (NTPasteboardHelper*) helperWithPasteboard: (NSPasteboard*) pasteboard;

- (id) initWithPasteboard: (NSPasteboard*) pasteboard;

- (void) declareTypes: (NSArray*) types owner: (id) owner;

@end
