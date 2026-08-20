//
//  DIXRecentScans.m
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

#import "DIXRecentScans.h"

NSString *DIXRecentScansChangedNotification = @"DIXRecentScansChanged";

//Kept in a default of the application's own rather than in Info.plist's
//Registrations: like ScannedItemCounts beside it, this is something the
//application writes down as it goes, not a setting anyone chooses.
static NSString * const kRecentScansKey = @"RecentScans";

static NSString * const kPathKey      = @"path";
static NSString * const kSizeKey      = @"size";
static NSString * const kScannedAtKey = @"scannedAt";

//Long enough to be useful, short enough that the sidebar does not become a
//filing cabinet. The section scrolls past about four of them anyway.
static const NSUInteger kMaximumScans = 20;

#pragma mark --------one entry-----------------

@interface DIXRecentScan()
{
	NSURL *_url;
	unsigned long long _size;
	NSDate *_scannedAt;
}
- (instancetype) initWithPath: (NSString*) path
						 size: (unsigned long long) size
					scannedAt: (NSDate*) scannedAt;
- (NSDictionary*) asDictionary;
@end

@implementation DIXRecentScan

- (instancetype) initWithPath: (NSString*) path
						 size: (unsigned long long) size
					scannedAt: (NSDate*) scannedAt
{
	self = [super init];

	if ( self != nil )
	{
		_url = [NSURL fileURLWithPath: path];
		_size = size;
		_scannedAt = scannedAt;
	}

	return self;
}

- (NSURL*) url                  { return _url; }
- (unsigned long long) size     { return _size; }
- (NSDate*) scannedAt           { return _scannedAt; }

- (NSString*) name
{
	//the last component, except at a volume root where that is empty
	NSString *name = [_url lastPathComponent];

	return [name length] > 0 ? name : [_url path];
}

- (NSString*) abbreviatedPath
{
	return [[_url path] stringByAbbreviatingWithTildeInPath];
}

- (NSDictionary*) asDictionary
{
	return @{ kPathKey: [_url path], kSizeKey: @(_size), kScannedAtKey: _scannedAt };
}

+ (NSString*) relativeTimeStringForDate: (NSDate*) date
{
	if ( date == nil )
		return @"";

	static NSRelativeDateTimeFormatter *formatter = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^
	{
		formatter = [[NSRelativeDateTimeFormatter alloc] init];
		[formatter setDateTimeStyle: NSRelativeDateTimeFormatterStyleNamed];
	} );

	return [formatter localizedStringForDate: date relativeToDate: [NSDate date]];
}

@end

#pragma mark --------the list-----------------

@interface DIXRecentScans()
{
	NSMutableArray<DIXRecentScan*> *_scans;
}
- (void) load;
- (void) save;
@end

@implementation DIXRecentScans

+ (instancetype) sharedList
{
	static DIXRecentScans *shared = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ shared = [[DIXRecentScans alloc] init]; } );

	return shared;
}

- (instancetype) init
{
	self = [super init];

	if ( self != nil )
	{
		_scans = [NSMutableArray array];
		[self load];
	}

	return self;
}

- (void) load
{
	NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey: kRecentScansKey];

	for ( id entry in stored )
	{
		if ( ![entry isKindOfClass: [NSDictionary class]] )
			continue;

		NSString *path = [entry objectForKey: kPathKey];
		NSNumber *size = [entry objectForKey: kSizeKey];
		NSDate *when   = [entry objectForKey: kScannedAtKey];

		if ( ![path isKindOfClass: [NSString class]] || [path length] == 0
			 || ![size isKindOfClass: [NSNumber class]]
			 || ![when isKindOfClass: [NSDate class]] )
			continue;

		[_scans addObject: [[DIXRecentScan alloc] initWithPath: path
														  size: [size unsignedLongLongValue]
													 scannedAt: when]];
	}
}

- (void) save
{
	NSMutableArray *stored = [NSMutableArray array];

	for ( DIXRecentScan *scan in _scans )
		[stored addObject: [scan asDictionary]];

	[[NSUserDefaults standardUserDefaults] setObject: stored forKey: kRecentScansKey];
}

//Folders that have gone are dropped on the way out rather than on the way in,
//so a volume that is merely unmounted comes back with its entry when it
//returns - the same reasoning as pruning ScannedItemCounts on write.
- (NSArray<DIXRecentScan*>*) scans
{
	NSMutableArray<DIXRecentScan*> *live = [NSMutableArray array];
	NSFileManager *fileManager = [NSFileManager defaultManager];

	for ( DIXRecentScan *scan in _scans )
	{
		if ( [fileManager fileExistsAtPath: [[scan url] path]] )
			[live addObject: scan];
	}

	return live;
}

- (void) recordScanOfURL: (NSURL*) url size: (unsigned long long) size
{
	if ( [[url path] length] == 0 )
		return;

	//One line per folder, so scanning the same one twice moves it to the front
	//and replaces what it says rather than adding a second row saying something
	//older.
	[self removeEntryForPath: [url path]];

	[_scans insertObject: [[DIXRecentScan alloc] initWithPath: [url path]
														 size: size
													scannedAt: [NSDate date]]
				 atIndex: 0];

	while ( [_scans count] > kMaximumScans )
		[_scans removeLastObject];

	[self save];

	[[NSNotificationCenter defaultCenter]
		postNotificationName: DIXRecentScansChangedNotification object: self];
}

- (void) removeEntryForPath: (NSString*) path
{
	NSUInteger index = 0;

	for ( DIXRecentScan *scan in [_scans copy] )
	{
		if ( [[[scan url] path] isEqualToString: path] )
		{
			[_scans removeObjectAtIndex: index];
			continue;
		}

		index++;
	}
}

- (void) removeScanForURL: (NSURL*) url
{
	[self removeEntryForPath: [url path]];
	[self save];

	[[NSNotificationCenter defaultCenter]
		postNotificationName: DIXRecentScansChangedNotification object: self];
}

@end
