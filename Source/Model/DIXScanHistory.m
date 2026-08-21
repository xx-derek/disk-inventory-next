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
#import "Preferences.h"

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

//Where the cap above fell: the size of the smallest entry kept. Written only
//when trimming actually happened, and the whole point of it is that a snapshot
//says nothing about anything smaller - see -changesForItem:.
static NSString * const kFloorKey = @"floor";

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

@interface DIXScanHistory()
- (NSURL*) snapshotDirectory;
- (NSArray<NSURL*>*) snapshotFiles;
@end

@implementation DIXScanHistory

+ (DIXScanHistory*) sharedHistory
{
	static DIXScanHistory *history = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ history = [[DIXScanHistory alloc] init]; } );

	return history;
}

#pragma mark --------where the snapshots live-----------------

- (NSURL*) defaultStorageDirectory
{
	NSURL *support = [[[NSFileManager defaultManager]
		URLsForDirectory: NSApplicationSupportDirectory inDomains: NSUserDomainMask] firstObject];

	if ( support == nil )
		return nil;

	return [[support URLByAppendingPathComponent: @"Disk Inventory Next"]
					 URLByAppendingPathComponent: @"Scans"];
}

//A bookmark rather than a path, so the folder can be renamed or moved and still
//be found. Not a *security-scoped* one, which is what the handoff suggests: the
//application is not sandboxed - its entitlements are empty - and asking for
//security scope without the entitlement fails to make a bookmark at all.
- (NSURL*) storageDirectory
{
	NSURL *directory = nil;
	NSData *bookmark = [[NSUserDefaults standardUserDefaults]
							dataForKey: ScanHistoryLocationBookmark];

	if ( [bookmark length] > 0 )
	{
		BOOL stale = NO;

		directory = [NSURL URLByResolvingBookmarkData: bookmark
											  options: 0
										relativeToURL: nil
								  bookmarkDataIsStale: &stale
												error: NULL];

		//A folder on a volume that is not mounted, or one that has been deleted.
		//Falling back is better than failing, and the bookmark is kept so that
		//plugging the drive back in puts things where they were.
		if ( directory != nil && ![directory checkResourceIsReachableAndReturnError: NULL] )
			directory = nil;
	}

	if ( directory == nil )
		directory = [self defaultStorageDirectory];

	if ( directory == nil )
		return nil;

	[[NSFileManager defaultManager] createDirectoryAtURL: directory
							 withIntermediateDirectories: YES
											  attributes: nil
												   error: NULL];
	return directory;
}

//Kept under its old name because everything below reads it, and it is the one
//question the rest of this file asks.
- (NSURL*) snapshotDirectory
{
	return [self storageDirectory];
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
	//"Off" means keep none, so there is nothing to write and nothing left to
	//compare against next time - which is what turns the change window off.
	if ( ![self isRecording] )
		return;

	NSString *path = [rootItem path];
	NSURL *url = [self snapshotURLForPath: path];

	if ( url == nil || [path length] == 0 )
		return;

	NSMutableDictionary<NSString*, NSNumber*> *sizes = [self sizesUnderItem: rootItem];

	//Trimmed to the largest, which is what a comparison is going to be about
	//anyway. Sorting a few thousand keys is nothing beside the walk above.
	unsigned long long floor = kSnapshotFloor;

	if ( [sizes count] > kMaximumEntries )
	{
		NSArray<NSString*> *ordered = [sizes keysSortedByValueUsingComparator:
			^NSComparisonResult ( NSNumber *a, NSNumber *b ) { return [b compare: a]; }];

		NSMutableDictionary<NSString*, NSNumber*> *trimmed = [NSMutableDictionary dictionary];

		for ( NSUInteger i = 0; i < kMaximumEntries; i++ )
			[trimmed setObject: [sizes objectForKey: [ordered objectAtIndex: i]]
						forKey: [ordered objectAtIndex: i]];

		//The smallest thing that survived, which is the line below which this
		//snapshot knows nothing. Recorded because the next scan has to compare
		//like with like: it walks the whole tree down to kSnapshotFloor, and
		//without this every file between the two figures looks brand new.
		floor = [[sizes objectForKey: [ordered objectAtIndex: kMaximumEntries - 1]]
					unsignedLongLongValue];

		sizes = trimmed;
	}

	NSDictionary *snapshot = @{ kPathKey:  path,
								kDateKey:  [NSDate date],
								kTotalKey: @([[rootItem size] unsignedLongLongValue]),
								kFloorKey: @(floor),
								kItemsKey: sizes };

	[snapshot writeToURL: url atomically: YES];
}

#pragma mark --------comparing two-----------------

//The size below which a snapshot knows nothing. Normally the flat floor; for
//one the cap trimmed, the smallest entry that survived it.
- (unsigned long long) floorOfSnapshot: (NSDictionary*) snapshot
								 items: (NSDictionary<NSString*, NSNumber*>*) items
{
	NSNumber *recorded = [snapshot objectForKey: kFloorKey];

	if ( [recorded isKindOfClass: [NSNumber class]] )
		return MAX( kSnapshotFloor, [recorded unsignedLongLongValue] );

	//Written before the trim line was recorded. A snapshot holding exactly the
	//maximum is one that was trimmed, and where it fell is its smallest entry.
	if ( [items count] < kMaximumEntries )
		return kSnapshotFloor;

	unsigned long long smallest = 0;

	for ( NSNumber *size in [items allValues] )
	{
		const unsigned long long value = [size unsignedLongLongValue];

		if ( smallest == 0 || value < smallest )
			smallest = value;
	}

	return MAX( kSnapshotFloor, smallest );
}

- (NSArray<DIXScanChange*>*) changesForItem: (FSItem*) rootItem
{
	NSDictionary *snapshot = [self snapshotForPath: [rootItem path]];
	NSDictionary<NSString*, NSNumber*> *before = [snapshot objectForKey: kItemsKey];

	if ( ![before isKindOfClass: [NSDictionary class]] )
		return @[];

	NSDictionary<NSString*, NSNumber*> *now = [self sizesUnderItem: rootItem];

	NSMutableSet<NSString*> *paths = [NSMutableSet setWithArray: [before allKeys]];
	[paths addObjectsFromArray: [now allKeys]];

	const unsigned long long floor = [self floorOfSnapshot: snapshot items: before];

	NSMutableArray<DIXScanChange*> *changes = [NSMutableArray array];

	for ( NSString *path in paths )
	{
		const long long was = (long long) [[before objectForKey: path] unsignedLongLongValue];
		const long long is  = (long long) [[now objectForKey: path] unsignedLongLongValue];
		const long long delta = is - was;

		if ( (unsigned long long) llabs( delta ) < kSnapshotFloor )
			continue;

		//Absence from a trimmed snapshot is not evidence of absence from the
		//disk. Everything below the trim line was dropped when it was written,
		//so a file that size may well have been sitting there all along - and
		//calling it new invents an addition per file. Measured against a
		///Volumes/External Disk snapshot trimmed at 3.79 MB, that filled the
		//window with identical "+4.0 MB" rows under a +8 kB total.
		//
		//At the line itself, not below it: the cap cuts through a run of files
		//of the same size and keeps an arbitrary part of it, so a file exactly
		//that big is the ambiguous case rather than the safe one.
		//
		//Only for a snapshot that was actually trimmed - an untrimmed one holds
		//everything down to kSnapshotFloor, and absence from it really is
		//evidence. The conservative direction either way: a genuinely new file
		//under the line goes unreported, which is a change missed rather than
		//one made up.
		if ( was == 0 && floor > kSnapshotFloor && (unsigned long long) is <= floor )
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
	for ( NSURL *file in [self snapshotFiles] )
		[[NSFileManager defaultManager] removeItemAtURL: file error: NULL];
}

#pragma mark --------what the settings screen asks-----------------

//Only this application's own files, matched by the name it writes them under -
//a folder someone points at may be a folder they keep other things in, and
//"Delete history now" must not take those with it.
- (NSArray<NSURL*>*) snapshotFiles
{
	NSURL *directory = [self snapshotDirectory];

	if ( directory == nil )
		return @[];

	NSArray<NSURL*> *contents = [[NSFileManager defaultManager]
		contentsOfDirectoryAtURL: directory
	  includingPropertiesForKeys: @[ NSURLFileSizeKey ]
						 options: NSDirectoryEnumerationSkipsHiddenFiles
						   error: NULL];

	NSMutableArray<NSURL*> *files = [NSMutableArray array];

	for ( NSURL *file in contents )
	{
		if ( ![[file pathExtension] isEqualToString: @"plist"] )
			continue;

		//The name is a 16-digit hash and nothing else; anything shaped
		//differently was not written here.
		NSString *stem = [[file lastPathComponent] stringByDeletingPathExtension];

		if ( [stem length] != 16 )
			continue;

		[files addObject: file];
	}

	return files;
}

- (NSUInteger) snapshotCount
{
	return [[self snapshotFiles] count];
}

- (unsigned long long) storedByteCount
{
	unsigned long long total = 0;

	for ( NSURL *file in [self snapshotFiles] )
	{
		NSNumber *size = nil;

		if ( [file getResourceValue: &size forKey: NSURLFileSizeKey error: NULL] )
			total += [size unsignedLongLongValue];
	}

	return total;
}

- (BOOL) moveStorageToDirectory: (NSURL*) url error: (NSError**) error
{
	NSURL *from = [self snapshotDirectory];

	if ( url == nil || from == nil || [[url path] isEqualToString: [from path]] )
		return YES;

	NSFileManager *fileManager = [NSFileManager defaultManager];

	if ( ![fileManager createDirectoryAtURL: url
				withIntermediateDirectories: YES
								 attributes: nil
									  error: error] )
		return NO;

	//Copy everything first, and only then remove: a move that failed half way
	//would leave someone's history split across two folders, which is worse
	//than either place.
	NSMutableArray<NSURL*> *copied = [NSMutableArray array];

	for ( NSURL *file in [self snapshotFiles] )
	{
		NSURL *destination = [url URLByAppendingPathComponent: [file lastPathComponent]];

		[fileManager removeItemAtURL: destination error: NULL];

		if ( ![fileManager copyItemAtURL: file toURL: destination error: error] )
		{
			//back out of what was copied, so the new folder is as it was found
			for ( NSURL *undo in copied )
				[fileManager removeItemAtURL: undo error: NULL];

			return NO;
		}

		[copied addObject: destination];
	}

	NSData *bookmark = [url bookmarkDataWithOptions: 0
					 includingResourceValuesForKeys: nil
									  relativeToURL: nil
											  error: error];

	if ( bookmark == nil )
	{
		for ( NSURL *undo in copied )
			[fileManager removeItemAtURL: undo error: NULL];

		return NO;
	}

	[[NSUserDefaults standardUserDefaults] setObject: bookmark
											  forKey: ScanHistoryLocationBookmark];

	//the originals last, once the new copies are the ones being read
	for ( NSURL *file in [fileManager contentsOfDirectoryAtURL: from
									includingPropertiesForKeys: nil
													   options: NSDirectoryEnumerationSkipsHiddenFiles
														 error: NULL] )
	{
		if ( [[file pathExtension] isEqualToString: @"plist"] )
			[fileManager removeItemAtURL: file error: NULL];
	}

	return YES;
}

- (BOOL) resetStorageLocationWithError: (NSError**) error
{
	NSURL *fallback = [self defaultStorageDirectory];

	if ( fallback == nil )
		return NO;

	if ( ![self moveStorageToDirectory: fallback error: error] )
		return NO;

	//An empty value means the default place, which is what makes a reset of the
	//preferences do the right thing rather than pointing at nothing.
	[[NSUserDefaults standardUserDefaults] removeObjectForKey: ScanHistoryLocationBookmark];

	return YES;
}

#pragma mark --------how long it is kept-----------------

- (BOOL) isRecording
{
	return [[NSUserDefaults standardUserDefaults]
				integerForKey: ScanHistoryRetentionDays] != DIXHistoryOff;
}

- (void) pruneToRetentionWindow
{
	const NSInteger days = [[NSUserDefaults standardUserDefaults]
								integerForKey: ScanHistoryRetentionDays];

	if ( days == DIXHistoryForever )
		return;

	if ( days == DIXHistoryOff )
	{
		[self deleteAllSnapshots];
		return;
	}

	NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow: -(double) days * 24.0 * 60.0 * 60.0];

	for ( NSURL *file in [self snapshotFiles] )
	{
		NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfURL: file];
		id when = [snapshot objectForKey: kDateKey];

		//A file that cannot say when it was written cannot be aged, and is more
		//likely something we did not write than something stale.
		if ( ![when isKindOfClass: [NSDate class]] )
			continue;

		if ( [when compare: cutoff] == NSOrderedAscending )
			[[NSFileManager defaultManager] removeItemAtURL: file error: NULL];
	}
}

@end
