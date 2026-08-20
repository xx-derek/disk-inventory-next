//
//  DIXVolumeList.m
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

#import "DIXVolumeList.h"

NSString *DIXVolumeListChangedNotification = @"DIXVolumeListChangedNotification";

//Everything a row needs. Asked for in one call when the list is built, because
//each of these is a round trip to the file system and a network volume that has
//gone away can make one of them slow.
static NSArray<NSURLResourceKey>* VolumeResourceKeys( void )
{
	static NSArray<NSURLResourceKey> *keys = nil;

	if ( keys == nil )
		keys = @[ NSURLLocalizedNameKey,
				  NSURLVolumeTotalCapacityKey,
				  NSURLVolumeAvailableCapacityKey,
				  NSURLVolumeSupportsVolumeSizesKey,
				  NSURLVolumeLocalizedFormatDescriptionKey,
				  NSURLEffectiveIconKey ];

	return keys;
}

@interface DIXVolume()
{
	NSURL *_url;
	NSString *_name;
	NSImage *_icon;
	NSString *_formatDescription;
	unsigned long long _totalCapacity;
	unsigned long long _availableCapacity;
	BOOL _knowsItsSize;
}
- (instancetype) initWithURL: (NSURL*) url;
- (void) rereadAvailableCapacity;
@end

@implementation DIXVolume

- (instancetype) initWithURL: (NSURL*) url
{
	self = [super init];

	if ( self == nil )
		return nil;

	_url = url;

	NSDictionary<NSURLResourceKey, id> *values =
		[url resourceValuesForKeys: VolumeResourceKeys() error: NULL];

	//A volume can disappear between being listed and being asked about, and a
	//stalled network mount answers nothing at all. Either way the row still gets
	//built - with the path's last component for a name, which is what the
	//Finder shows - rather than the volume vanishing from a list that is meant
	//to say what is mounted.
	_name = [values objectForKey: NSURLLocalizedNameKey];

	if ( [_name length] == 0 )
		_name = [url lastPathComponent];

	_icon = [values objectForKey: NSURLEffectiveIconKey];
	_formatDescription = [values objectForKey: NSURLVolumeLocalizedFormatDescriptionKey];

	_knowsItsSize = [[values objectForKey: NSURLVolumeSupportsVolumeSizesKey] boolValue];
	_totalCapacity = [[values objectForKey: NSURLVolumeTotalCapacityKey] unsignedLongLongValue];
	_availableCapacity = [[values objectForKey: NSURLVolumeAvailableCapacityKey] unsignedLongLongValue];

	return self;
}

//Only the free space. The name, the icon and the format do not move, and
//re-reading them would be several file system round trips a few seconds apart
//for values that cannot have changed without a notification saying so.
- (void) rereadAvailableCapacity
{
	//the value is cached on the NSURL, so it has to be told to forget
	[_url removeCachedResourceValueForKey: NSURLVolumeAvailableCapacityKey];

	NSNumber *available = nil;

	if ( [_url getResourceValue: &available forKey: NSURLVolumeAvailableCapacityKey error: NULL] )
		_availableCapacity = [available unsignedLongLongValue];
}

- (NSURL*) url                          { return _url; }
- (NSString*) name                      { return _name; }
- (NSImage*) icon                       { return _icon; }
- (NSString*) formatDescription         { return _formatDescription; }
- (unsigned long long) totalCapacity    { return _totalCapacity; }
- (unsigned long long) availableCapacity { return _availableCapacity; }
- (BOOL) knowsItsSize                   { return _knowsItsSize; }

- (double) usedFraction
{
	if ( !_knowsItsSize || _totalCapacity == 0 )
		return 0.0;

	if ( _availableCapacity >= _totalCapacity )
		return 0.0;

	return (double) ( _totalCapacity - _availableCapacity ) / (double) _totalCapacity;
}

@end

@implementation DIXVolumeList

+ (DIXVolumeList*) sharedList
{
	static DIXVolumeList *list = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ list = [[DIXVolumeList alloc] init]; } );

	return list;
}

- (instancetype) init
{
	self = [super init];

	if ( self == nil )
		return nil;

	NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

	for ( NSNotificationName name in @[ NSWorkspaceDidMountNotification,
										NSWorkspaceDidUnmountNotification,
										NSWorkspaceDidRenameVolumeNotification ] )
	{
		[workspaceCenter addObserver: self
							selector: @selector(onVolumesChanged:)
								name: name
							  object: nil];
	}

	[self rebuild];

	return self;
}

- (void) dealloc
{
	//A singleton never gets here, but it is the pair to the registration above
	//and leaving it out would be a trap for anyone who later makes this ordinary.
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self];
}

- (NSArray<DIXVolume*>*) volumes
{
	return _volumes;
}

- (void) rebuild
{
	NSArray<NSURL*> *urls =
		[[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys: VolumeResourceKeys()
																			   options: NSVolumeEnumerationSkipHiddenVolumes];

	NSMutableArray<DIXVolume*> *volumes = [NSMutableArray arrayWithCapacity: [urls count]];

	for ( NSURL *url in urls )
		[volumes addObject: [[DIXVolume alloc] initWithURL: url]];

	_volumes = volumes;
}

- (void) onVolumesChanged: (NSNotification*) notification
{
	[self rebuild];

	[[NSNotificationCenter defaultCenter] postNotificationName: DIXVolumeListChangedNotification
														object: self];
}

- (void) refreshSizes
{
	for ( DIXVolume *volume in _volumes )
		[volume rereadAvailableCapacity];

	[[NSNotificationCenter defaultCenter] postNotificationName: DIXVolumeListChangedNotification
														object: self];
}

@end
