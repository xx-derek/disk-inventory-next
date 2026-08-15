//
//  NTPasteboardHelper.m
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

#import "NTPasteboardHelper.h"

@implementation NTPasteboardHelper

+ (NTPasteboardHelper*) helperWithPasteboard: (NSPasteboard*) pasteboard
{
	return [[self alloc] initWithPasteboard: pasteboard];
}

- (id) initWithPasteboard: (NSPasteboard*) pasteboard
{
	self = [super init];
	if ( self == nil )
		return nil;

	_pasteboard = pasteboard;
	_owner = nil;
	_isOwning = NO;

	return self;
}


//A helper that has promised data has to outlive whatever created it, and under
//ARC it cannot simply retain itself. It parks itself here instead, until the
//pasteboard is taken away from it.
static NSMutableSet *g_liveHelpers = nil;

- (void) declareTypes: (NSArray*) types owner: (id) owner
{
	_owner = owner;

	if ( !_isOwning )
	{
		_isOwning = YES;

		if ( g_liveHelpers == nil )
			g_liveHelpers = [[NSMutableSet alloc] init];

		[g_liveHelpers addObject: self];
	}

	[_pasteboard declareTypes: types owner: self];
}

#pragma mark --------NSPasteboard owner-----------------

- (void) pasteboard: (NSPasteboard*) pasteboard provideDataForType: (NSPasteboardType) type
{
	if ( [_owner respondsToSelector: @selector(pasteboard:provideDataForType:)] )
		[_owner pasteboard: pasteboard provideDataForType: type];
}

- (void) pasteboardChangedOwner: (NSPasteboard*) pasteboard
{
	if ( [_owner respondsToSelector: @selector(pasteboardChangedOwner:)] )
		[_owner pasteboardChangedOwner: pasteboard];

	_owner = nil;

	if ( _isOwning )
	{
		_isOwning = NO;

		//dropping out of the set may be the last reference, and we are being
		//called from the pasteboard, so hold on until this returns
		NTPasteboardHelper *keepAlive = self;
		[g_liveHelpers removeObject: self];
		(void) keepAlive;
	}
}

@end
