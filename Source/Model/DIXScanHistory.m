//
//  DIXScanHistory.m
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

#import "DIXScanHistory.h"
#import "FSItem.h"

//Nothing smaller than this is recorded or reported. A megabyte is under a
//thousandth of a modern volume, and a list of everything that moved by a
//kilobyte is a list nobody reads.
static const unsigned long long kSnapshotFloor = 1024ULL * 1024ULL;

//And no more than this many rows per snapshot, largest first, so a volume with
//a million qualifying files cannot write a file the size of the scan.
static const NSUInteger kMaximumEntries = 5000;

//A child cannot be larger than its parent, so a folder under the floor has
//nothing under it worth walking into.
static NSString * const kPathKey  = @"path";
static NSString * const kDateKey  = @"scannedAt";
static NSString * const kTotalKey = @"total";
static NSString * const kItemsKey = @"items";

//================ DIXScanChange ======================================================

@implementation DIXScanChange
{
	NSString *_path;
	long long _delta;
}

- (instancetype) initWithPath: (NSString*) path delta: (long long) delta
{
	self = [super init];

	if ( self != nil )
	{
		_path = [path copy];
		_delta = delta;
	}

	return self;
}

- (NSString*) path   { return _path; }
- (long long) delta  { return _delta; }
- (NSString*) name   { return [_path lastPathComponent]; }

- (NSString*) folderPath
{
	return [[_path stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];
}

@end

//================ DIXScanHistory ======================================================

@implementation DIXScanHistory

+ (DIXScanHistory*) sharedHistory
{
	static DIXScanHistory *history = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ history = [[DIXScanHistory alloc] init]; } );

	return history;
}

#pragma mark --------where the snapshots live-----------------

- (NSURL*) snapshotDirectory
{
	NSURL *support = [[[NSFileManager defaultManager]
		URLsForDirectory: NSApplicationSupportDirectory inDomains: NSUserDomainMask] firstObject];

	if ( support == nil )
		return nil;

	NSURL *directory = [[support URLByAppendingPathComponent: @"Disk Inventory Next"]
									 URLByAppendingPathComponent: @"Scans"];

	[[NSFileManager defaultManager] createDirectoryAtURL: directory
							 withIntermediateDirectories: YES
											  attributes: nil
												   error: NULL];
	return directory;
}

//One file per scanned folder, named for its path rather than by it: a path
//makes a poor file name and a hash of one is fixed length. The path is stored
//inside the file as well, so a stray snapshot can still say what it describes.
- (NSURL*) snapshotURLForPath: (NSString*) path
{
	NSURL *directory = [self snapshotDirectory];

	if ( directory == nil || [path length] == 0 )
		return nil;

	unsigned long long hash = 14695981039346656037ULL;   //FNV-1a, for a short stable name

	for ( NSUInteger i = 0; i < [path length]; i++ )
	{
		hash ^= (unsigned long long) [path characterAtIndex: i];
		hash *= 1099511628211ULL;
	}

	return [directory URLByAppendingPathComponent:
		[NSString stringWithFormat: @"%016llx.plist", hash]];
}

- (NSDictionary*) snapshotForPath: (NSString*) path
{
	NSURL *url = [self snapshotURLForPath: path];

	if ( url == nil )
		return nil;

	NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfURL: url];

	//A hash collision would describe a different folder, which is worse than
	//having no history at all - so the path is checked, not assumed.
	if ( ![[snapshot objectForKey: kPathKey] isEqualToString: path] )
		return nil;

	return snapshot;
}

- (NSDate*) snapshotDateForURL: (NSURL*) url
{
	id date = [[self snapshotForPath: [url path]] objectForKey: kDateKey];

	return [date isKindOfClass: [NSDate class]] ? date : nil;
}

#pragma mark --------writing one-----------------

//Collected iteratively rather than recursively: a scan of a volume is millions
//of items deep in places, and the stack is not the place to find that out.
- (NSMutableDictionary<NSString*, NSNumber*>*) sizesUnderItem: (FSItem*) rootItem
{
	NSMutableDictionary<NSString*, NSNumber*> *sizes = [NSMutableDictionary dictionary];
	NSMutableArray<FSItem*> *pending = [NSMutableArray arrayWithObject: rootItem];

	while ( [pending count] > 0 )
	{
		FSItem *item = [pending lastObject];
		[pending removeLastObject];

		for ( NSUInteger i = 0; i < [item childCount]; i++ )
		{
			FSItem *child = [item childAtIndex: i];

			if ( [child isSpecialItem] )
				continue;

			const unsigned long long size = [[child size] unsignedLongLongValue];

			//under the floor, and so is everything below it
			if ( size < kSnapshotFloor )
				continue;

			NSString *path = [child path];

			if ( [path length] > 0 )
				[sizes setObject: @(size) forKey: path];

			if ( [child isFolder] )
				[pending addObject: child];
		}
	}

	return sizes;
}

- (void) recordSnapshotForItem: (FSItem*) rootItem
{
	NSString *path = [rootItem path];
	NSURL *url = [self snapshotURLForPath: path];

	if ( url == nil || [path length] == 0 )
		return;

	NSMutableDictionary<NSString*, NSNumber*> *sizes = [self sizesUnderItem: rootItem];

	//Trimmed to the largest, which is what a comparison is going to be about
	//anyway. Sorting a few thousand keys is nothing beside the walk above.
	if ( [sizes count] > kMaximumEntries )
	{
		NSArray<NSString*> *ordered = [sizes keysSortedByValueUsingComparator:
			^NSComparisonResult ( NSNumber *a, NSNumber *b ) { return [b compare: a]; }];

		NSMutableDictionary<NSString*, NSNumber*> *trimmed = [NSMutableDictionary dictionary];

		for ( NSUInteger i = 0; i < kMaximumEntries; i++ )
			[trimmed setObject: [sizes objectForKey: [ordered objectAtIndex: i]]
						forKey: [ordered objectAtIndex: i]];

		sizes = trimmed;
	}

	NSDictionary *snapshot = @{ kPathKey:  path,
								kDateKey:  [NSDate date],
								kTotalKey: @([[rootItem size] unsignedLongLongValue]),
								kItemsKey: sizes };

	[snapshot writeToURL: url atomically: YES];
}

#pragma mark --------comparing two-----------------

- (NSArray<DIXScanChange*>*) changesForItem: (FSItem*) rootItem
{
	NSDictionary *snapshot = [self snapshotForPath: [rootItem path]];
	NSDictionary<NSString*, NSNumber*> *before = [snapshot objectForKey: kItemsKey];

	if ( ![before isKindOfClass: [NSDictionary class]] )
		return @[];

	NSDictionary<NSString*, NSNumber*> *now = [self sizesUnderItem: rootItem];

	NSMutableSet<NSString*> *paths = [NSMutableSet setWithArray: [before allKeys]];
	[paths addObjectsFromArray: [now allKeys]];

	NSMutableArray<DIXScanChange*> *changes = [NSMutableArray array];

	for ( NSString *path in paths )
	{
		const long long was = (long long) [[before objectForKey: path] unsignedLongLongValue];
		const long long is  = (long long) [[now objectForKey: path] unsignedLongLongValue];
		const long long delta = is - was;

		if ( (unsigned long long) llabs( delta ) < kSnapshotFloor )
			continue;

		[changes addObject: [[DIXScanChange alloc] initWithPath: path delta: delta]];
	}

	[changes sortUsingComparator: ^NSComparisonResult ( DIXScanChange *a, DIXScanChange *b )
	{
		const long long x = llabs( [a delta] ), y = llabs( [b delta] );

		return ( x == y ) ? NSOrderedSame : ( x > y ? NSOrderedAscending : NSOrderedDescending );
	}];

	return [self collapsed: changes];
}

//A folder and the one thing inside it that explains its growth are the same
//news told twice. Walking biggest-first, a descendant replaces the ancestor
//already kept when it accounts for nearly all of it - which is how the design's
//list names IMG_4821.MOV rather than the Movies folder holding it - and is
//dropped when it does not, where the folder is the better answer.
- (NSArray<DIXScanChange*>*) collapsed: (NSArray<DIXScanChange*>*) changes
{
	NSMutableArray<DIXScanChange*> *kept = [NSMutableArray array];

	for ( DIXScanChange *change in changes )
	{
		NSString *path = [[change path] stringByAppendingString: @"/"];
		BOOL handled = NO;

		for ( NSUInteger i = 0; i < [kept count]; i++ )
		{
			DIXScanChange *other = [kept objectAtIndex: i];
			NSString *otherPath = [[other path] stringByAppendingString: @"/"];

			const BOOL isDescendant = [path hasPrefix: otherPath];
			const BOOL isAncestor   = [otherPath hasPrefix: path];

			if ( !isDescendant && !isAncestor )
				continue;

			//same sign and nearly the same figure: one row, the deeper one
			const long long mine = llabs( [change delta] ), theirs = llabs( [other delta] );

			if ( ( [change delta] > 0 ) == ( [other delta] > 0 )
				 && (double) MIN( mine, theirs ) >= 0.9 * (double) MAX( mine, theirs ) )
			{
				if ( isDescendant )
					[kept replaceObjectAtIndex: i withObject: change];
			}

			handled = YES;
			break;
		}

		if ( !handled )
			[kept addObject: change];
	}

	return kept;
}

- (void) deleteAllSnapshots
{
	NSURL *directory = [self snapshotDirectory];

	if ( directory == nil )
		return;

	NSArray<NSURL*> *files = [[NSFileManager defaultManager]
		contentsOfDirectoryAtURL: directory
	  includingPropertiesForKeys: nil
						 options: NSDirectoryEnumerationSkipsHiddenFiles
						   error: NULL];

	for ( NSURL *file in files )
		[[NSFileManager defaultManager] removeItemAtURL: file error: NULL];
}

@end
