//
//  FSItem.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on Mon Sep 29 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "FSItem.h"
#import "NSURL-Extensions.h"
#import <os/lock.h>
#import <stdatomic.h>

//for debugging and logging purposes
_Atomic unsigned g_fileCount;
_Atomic unsigned g_folderCount;
static unsigned g_packageCheckCount = 0;

#pragma mark --------what a running scan has found-----------------

//Relaxed, deliberately. These are read by one thread that only ever displays
//them, so nothing is ordered against them and the default sequential
//consistency would put a barrier on the hot path of every file in the scan.
static _Atomic unsigned long long g_bytesFound;
static _Atomic unsigned g_skippedCount;

//Written before the first queue starts and only read after that, so it needs no
//synchronising of its own - the same rule as FileSystemDoc's option snapshots.
static BOOL g_scanUsesPhysicalSize = NO;

NSString * const FSItemBiggestNameKey = @"name";
NSString * const FSItemBiggestSizeKey = @"size";
NSString * const FSItemBiggestKindKey = @"kind";

//Three entries, biggest first. The lock is taken only by a file that is bigger
//than the smallest one held, and the threshold that decides that is an atomic
//read - so on a real volume almost every file gets one comparison and no lock
//at all after the first moments.
#define kBiggestCount 3

static os_unfair_lock g_biggestLock = OS_UNFAIR_LOCK_INIT;
static NSString *g_biggestNames[kBiggestCount];
static NSString *g_biggestKinds[kBiggestCount];
static unsigned long long g_biggestSizes[kBiggestCount];
static _Atomic unsigned long long g_biggestThreshold;

void FSItemResetScanProgress( BOOL usePhysicalFileSize )
{
	g_scanUsesPhysicalSize = usePhysicalFileSize;

	atomic_store_explicit( &g_bytesFound, 0, memory_order_relaxed );
	atomic_store_explicit( &g_skippedCount, 0, memory_order_relaxed );
	atomic_store_explicit( &g_biggestThreshold, 0, memory_order_relaxed );

	os_unfair_lock_lock( &g_biggestLock );

	for ( unsigned i = 0; i < kBiggestCount; i++ )
	{
		g_biggestNames[i] = nil;
		g_biggestKinds[i] = nil;
		g_biggestSizes[i] = 0;
	}

	os_unfair_lock_unlock( &g_biggestLock );
}

FSItemScanTotals FSItemScanTotalsSoFar( void )
{
	FSItemScanTotals totals;

	totals.files   = g_fileCount;
	totals.folders = g_folderCount;
	totals.skipped = atomic_load_explicit( &g_skippedCount, memory_order_relaxed );
	totals.bytes   = atomic_load_explicit( &g_bytesFound, memory_order_relaxed );

	return totals;
}

NSArray<NSDictionary*>* FSItemBiggestFilesSoFar( void )
{
	NSMutableArray<NSDictionary*> *biggest = [NSMutableArray array];

	os_unfair_lock_lock( &g_biggestLock );

	for ( unsigned i = 0; i < kBiggestCount; i++ )
	{
		if ( g_biggestNames[i] == nil )
			break;

		NSMutableDictionary *entry = [NSMutableDictionary dictionary];

		[entry setObject: g_biggestNames[i] forKey: FSItemBiggestNameKey];
		[entry setObject: @(g_biggestSizes[i]) forKey: FSItemBiggestSizeKey];

		if ( g_biggestKinds[i] != nil )
			[entry setObject: g_biggestKinds[i] forKey: FSItemBiggestKindKey];

		[biggest addObject: entry];
	}

	os_unfair_lock_unlock( &g_biggestLock );

	return biggest;
}

//An insertion sort over three entries, which is the whole of it.
static void RememberIfBiggest( NSString *name, NSString *kind, unsigned long long size )
{
	if ( size <= atomic_load_explicit( &g_biggestThreshold, memory_order_relaxed ) )
		return;

	os_unfair_lock_lock( &g_biggestLock );

	//re-tested under the lock: another queue may have raised the bar since
	if ( size > g_biggestSizes[kBiggestCount - 1] )
	{
		unsigned slot = kBiggestCount - 1;

		while ( slot > 0 && g_biggestSizes[slot - 1] < size )
		{
			g_biggestSizes[slot] = g_biggestSizes[slot - 1];
			g_biggestNames[slot] = g_biggestNames[slot - 1];
			g_biggestKinds[slot] = g_biggestKinds[slot - 1];
			slot--;
		}

		g_biggestSizes[slot] = size;
		g_biggestNames[slot] = name;
		g_biggestKinds[slot] = kind;

		atomic_store_explicit( &g_biggestThreshold,
							   g_biggestSizes[kBiggestCount - 1], memory_order_relaxed );
	}

	os_unfair_lock_unlock( &g_biggestLock );
}

//global cache for kind names, keyed by UTI
NSMutableDictionary *g_kindNameDictionary = nil;

//and keyed by what decides the UTI, so most items never need one fetched -
//see -setKindStringIncludingChildren:
static NSMutableDictionary *g_kindNameByShape = nil;

//Both dictionaries are process-wide and are now written from several queues at
//once, since subtrees are walked concurrently. The lock is held only around the
//dictionary itself, never across a UTTypeCopyDescription, and two queues racing
//to describe the same type is harmless - they compute the same answer.
static os_unfair_lock g_kindNameLock = OS_UNFAIR_LOCK_INIT;

//exceptions
NSString* FSItemLoadingCanceledException = @"FSItemLoadingCanceledException";
NSString* FSItemLoadingFailedException = @"FSItemLoadingFailedException";


@implementation NSString (ComparisonAdditions)
- (NSComparisonResult) compareAsFilesystemName: (NSString*) other
{
	return [self compare: other options: (NSNumericSearch | NSCaseInsensitiveSearch)];
}
@end

//================ interface FSItem(Private) ======================================================

@interface FSItem(Private)

- (id) initWithURL: (NSURL*)url
			 parent: (FSItem*) parent
	  setKindString: (BOOL) setKindString;

- (void) setParent: (FSItem*) parent;
- (void) onParentDealloc;

- (NSComparisonResult) compareSizeDescendingly: (FSItem*) other; //compares sizes

- (void) loadChildrenAndSetKindStrings: (BOOL) setKindStrings
					   usePhysicalSize: (BOOL) usePhysicalSize;


- (void) loadChildrenConcurrentlyWithKindStrings: (BOOL) setKindStrings
								 usePhysicalSize: (BOOL) usePhysicalSize;

- (void) setSize: (NSNumber*) size;
- (void) setSizeValue: (unsigned long long) size;

- (void) childChanged: (FSItem*) child oldSize: (unsigned long long) oldSize newSize: (unsigned long long) newSize;

@end

//Children are kept largest first. Inserting into the already sorted array is
//what keeps loading linear; re-sorting on every file added would not be.
static void InsertChildKeepingSizeOrder( NSMutableArray *children, FSItem *newChild )
{
	const NSUInteger index = [children indexOfObject: newChild
									   inSortedRange: NSMakeRange( 0, [children count] )
											 options: NSBinarySearchingInsertionIndex
									 usingComparator: ^NSComparisonResult( FSItem *left, FSItem *right )
	{
		return [left compareSizeDescendingly: right];
	}];

	[children insertObject: newChild atIndex: index];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSPasteboardType FSItemLegacyFilenamesPasteboardType( void )
{
	return NSFilenamesPboardType;
}

//Every pasteboard type has two spellings: a UTI and the NeXT/Apple name that
//predates it. They are *different strings* — NSPasteboardTypeHTML is
//"public.html", NSHTMLPboardType is "Apple HTML pasteboard type" — but
//-declareTypes: advertises both whichever one is passed in. So a receiver may
//ask for either, and comparing against only one silently refuses half of them.
static NSDictionary<NSPasteboardType, NSPasteboardType>* LegacyPasteboardTypeAliases( void )
{
	static NSDictionary *aliases = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{
		aliases = @{ NSPasteboardTypeString : NSStringPboardType,
					 NSPasteboardTypeTIFF   : NSTIFFPboardType,
					 NSPasteboardTypeRTF    : NSRTFPboardType,
					 NSPasteboardTypeRTFD   : NSRTFDPboardType,
					 NSPasteboardTypeHTML   : NSHTMLPboardType,
					 NSPasteboardTypePDF    : NSPDFPboardType };
	});

	return aliases;
}

#pragma clang diagnostic pop

//YES if `type` names `wanted`, in either spelling.
static BOOL PasteboardTypeMatches( NSPasteboardType type, NSPasteboardType wanted )
{
	if ( [type isEqualToString: wanted] )
		return YES;

	NSPasteboardType legacy = [LegacyPasteboardTypeAliases() objectForKey: wanted];

	return legacy != nil && [type isEqualToString: legacy];
}

//================ implementation FSItem ======================================================

@implementation FSItem

+ (void) initialize
{
	//instantiate the dictionaries for global kind names cache. Both are made here,
	//under +initialize's own guarantees, rather than lazily on a walk that now has
	//several queues in it.
	g_kindNameDictionary = [[NSMutableDictionary alloc] init];
	g_kindNameByShape = [[NSMutableDictionary alloc] init];
}

- (id) initWithPath: (NSString *) path
{
    self = [super init];
    
    NSURL * url = [[NSURL alloc] initFileURLWithPath:path];
    
    return [self initWithURL:url];
}

- (id) initWithURL: (NSURL *) url
{
    self = [super init];
    
    _type = FileFolderItem;

    //the root is the one item that keeps a URL: there is no parent to build one
    //from, and there is exactly one of it
    _rootURL = url;
    _name = [url lastPathComponent];

    if ( [url isDirectory] )
    {
        _flags |= kFSItemIsFolder;
        _childs = [[NSMutableArray alloc] init];
    }

    _parent = nil; //we are the root item
    
    return self;
}

- (id) initAsOtherSpaceItemForParent: (FSItem*) parent
{
    self = [super init];
	
	_type = OtherSpaceItem;
	
	_parent = parent; //weak reference
	
	//NSString* hashString = [[parent path] stringByAppendingString: @"/OtherSpace"];
	//_hash = [hashString hash];
	
	[self recalculateSize: NO updateParent: NO];
	
	return self;
}

- (id) initAsFreeSpaceItemForParent: (FSItem*) parent
{
    self = [super init];
	
	_type = FreeSpaceItem;
	
	_parent = parent;
	
	//NSString* hashString = [[parent path] stringByAppendingString: @"/FreeSpace"];
	//_hash = [hashString hash];
	
	[self recalculateSize: NO updateParent: NO];
	
	return self;
}

- (id) delegate
{
	return [self root]->_delegate;
}

- (void) setDelegate: (id) delegate
{
	_delegate = delegate; //no retain
}

- (void) dealloc
{
	if ( _childs != nil )
	{
		[_childs makeObjectsPerformSelector: @selector(onParentDealloc)];
	}
	
    
    //_parent and _delegate no release!
	
}

- (FSItemType) type
{
	return _type;
}

- (BOOL) isSpecialItem
{
	return _type != FileFolderItem;
}

//Built from the chain rather than stored, for everything but the root. Costs one
//URL per ancestor and is called for one-off work - revealing in the Finder, the
//Info panel, dragging, an icon - never in a loop over the tree. Anything the
//tree is asked for in bulk (name, size, kind, folder-ness) is an ivar.
- (NSURL *) fileURL
{
	if ( [self isSpecialItem] )
		return [[self root] fileURL];

	if ( _rootURL != nil )
		return _rootURL;

	return [[[self parent] fileURL] URLByAppendingPathComponent: _name
													isDirectory: [self isFolder]];
}

- (void) setFileURL: (NSURL*) url
{
	NSAssert( ![self isSpecialItem], @"free and other space items don't habe a NTFileDesc object");

	//Only meaningful for a root, which is the only item that stores one; below
	//that an item's URL is its parent's plus its name, so the name is what moves.
	if ( _rootURL != nil )
		_rootURL = url;

	_name = [url lastPathComponent];
}

/*- (unsigned) hash
{
	if ( _hash == 0 )
		_hash = [[self path] hash];
	
    return _hash;
}
*/
- (BOOL) isEqual: (id) object
{
	//We don't check real equality here. This method is only intended to support NSSet.
    return object == self;
	//a better (but slower) version is:
	/*
	FSItem *item = object;
    return [item isKindOfClass: [FSItem class]]
			&& [self type] == [item type]
			&& [[self fileDesc] isEqualToDesc: [item fileDesc]];
	*/
}

- (NSString *) description
{
	switch ( [self type] )
	{
		case FileFolderItem:
			return [[self fileURL] description];
		case FreeSpaceItem:
			return @"FreeSpaceItem";
		case OtherSpaceItem:
			return @"OtherSpaceItem";
	}
	
	NSAssert( NO, @"unknown item type" );
	return @"";		
}

- (FSItem*) parent
{
    return _parent;
}

- (FSItem*) root
{
    if ( [self isRoot] )
        return self;
    else
        return [[self parent] root];
}

- (BOOL) isRoot
{
    return _parent == nil;
}

- (BOOL) isFolder
{
	return ( _flags & kFSItemIsFolder ) != 0;
}

- (BOOL) isPackage
{
	if ( [self isSpecialItem] || ![self isFolder] )
		return NO;

	//Resolved when first asked and then remembered. Only a folder can be one,
	//and answering means asking LaunchServices, which opens the file - so this
	//is deliberately not gathered for every item during the walk.
	if ( ( _flags & kFSItemPackageResolved ) == 0 )
	{
		if ( [[self fileURL] isPackage] )
			_flags |= kFSItemIsPackage;

		_flags |= kFSItemPackageResolved;
	}

	return ( _flags & kFSItemIsPackage ) != 0;
}

- (BOOL)isAlias
{
	if ( ![self isSpecialItem] )
	{
		return ( _flags & kFSItemIsAlias ) != 0;
	}
	else
		return NO;
}

- (BOOL) exists
{
	return [[self fileURL] stillExists];
}

- (NSImage*) iconWithSize: (unsigned) iconSize
{
	//items for free space and other space don't have an icon
	if ( [self isSpecialItem] )
		return nil;
	
	if ( _icons == nil )
		_icons = [[NSMutableDictionary alloc] init];
	
	NSNumber *key = [NSNumber numberWithUnsignedInt: iconSize];
	NSImage *icon = [_icons objectForKey: key];
	if ( icon == nil )
	{
        icon = [[NSWorkspace sharedWorkspace] iconForFile:[[self fileURL] path]];
        [icon setSize:NSMakeSize(iconSize, iconSize)];

        if ( icon == nil )
			icon = (id) [NSNull null];
		
		[_icons setObject: icon forKey: key];
	}
	
	return (icon == (id)[NSNull null]) ? nil : icon;
}

#pragma mark -----------------child handlers-----------------------

- (NSEnumerator *) childEnumerator
{
	if ( ![self isSpecialItem] )
		return [_childs objectEnumerator];
	else
		return nil;
}

- (FSItem*) childAtIndex: (NSUInteger) index
{
	if ( ![self isSpecialItem] )
		return [_childs objectAtIndex: index];
	else
		return nil;
}

- (NSUInteger) childCount
{
	if ( ![self isSpecialItem] )
		return [_childs count];
	else
		return 0;
}

- (void) removeChild: (FSItem*) child updateParent: (BOOL) updateParent
{
	NSAssert( ![self isSpecialItem], @"removeChild is illegal call for special item" );
	
	NSUInteger index = [_childs indexOfObjectIdenticalTo: child];
	if ( index != NSNotFound )
	{
		unsigned long long myOldSize = [self sizeValue];
		unsigned long long myNewSize = myOldSize - [child sizeValue];
		
		[self setSizeValue: myNewSize];
		
		[_childs removeObjectAtIndex: index];
		
		if ( updateParent && ![self isRoot] )
			[[self parent] childChanged: self oldSize: myOldSize newSize: myNewSize];
	}
}

- (void) insertChild: (FSItem*) newChild updateParent: (BOOL) updateParent
{
	unsigned long long myOldSize = [self sizeValue];
	
	[newChild setParent: self];
	
	//insert child sorted by size
	InsertChildKeepingSizeOrder( _childs, newChild );
	
	[self setSizeValue: [self sizeValue] + [newChild sizeValue]];
	
	if ( updateParent && ![self isRoot] )
		[[self parent] childChanged: self oldSize: myOldSize newSize: [self sizeValue]];
}

- (void) replaceChild: (FSItem*) oldChild
			 withItem: (FSItem*) newChild
		 updateParent: (BOOL) updateParent
{
	if ( oldChild != newChild )
	{
		unsigned long long myOldSize = [self sizeValue];
		
		[self removeChild: oldChild updateParent: NO];
		[self insertChild: newChild updateParent: NO];
		
		if ( updateParent && ![self isRoot] )
			[[self parent] childChanged: self oldSize: myOldSize newSize: [self sizeValue]];
	}
}

//if this is a folder, load all containing files
- (void) loadChildren
{
	BOOL usePhysicalSize = NO;
	
	id delegate = [self delegate];
	if ( [delegate respondsToSelector: @selector(fsItemShouldUsePhysicalFileSize:)] )
		usePhysicalSize = [delegate fsItemShouldUsePhysicalFileSize: self];
	
	//use new optimized version of loadChilds
	[self loadChildrenConcurrentlyWithKindStrings: YES
								 usePhysicalSize: usePhysicalSize];
	
	LOG (@"package check count: %d", g_packageCheckCount);
}

#pragma mark -----------------sizes-----------------------

- (NSNumber*) size
{
	if ( _size == nil )
		//_size = [[NSNumber alloc] initWithUnsignedLongLong: [[self fileDesc] size]];
		_size = [[NSNumber alloc] initWithUnsignedLongLong: _sizeValue];
	
    return _size;
}

- (unsigned long long) sizeValue
{
	return _sizeValue;
}

- (void) recalculateSize: (BOOL) usePhysicalSize updateParent: (BOOL) updateParent
{
	unsigned long long oldSize = [self sizeValue];
	UInt64 size = 0;
	
	switch ( [self type] )
	{
		case FileFolderItem:
			if ( [self isFolder] )
			{
				NSUInteger i = [_childs count];
				while ( i-- )
				{
					FSItem *child = [_childs objectAtIndex: i];
					
					[child recalculateSize: usePhysicalSize updateParent: NO];
						 
					size += [child sizeValue];
				}
				[_childs sortUsingSelector: @selector(compareSizeDescendingly:)];
			}
			else
			{
				//File: both sizes were read when the item was made, so this
				//needs no file system access and works after the URL is gone
				size = usePhysicalSize ? _physicalSize : _logicalSize;
			}
			break;
			
		case FreeSpaceItem:
            {
                NSNumber *freeSpace = [[self fileURL] getCachedNumberValue: NSURLVolumeAvailableCapacityKey];
                size = freeSpace == nil ? 0 : [freeSpace unsignedLongLongValue];
            }
			break;
			
		case OtherSpaceItem:
            {
                NSNumber *totalSpace = [[self fileURL] getCachedNumberValue: NSURLVolumeTotalCapacityKey];
                NSNumber *freeSpace = [[self fileURL] getCachedNumberValue: NSURLVolumeAvailableCapacityKey];

                UInt64 totalSpaceVal = totalSpace == nil ? 0 : [totalSpace unsignedLongLongValue];
                UInt64 freeSpaceVal = freeSpace == nil ? 0 : [freeSpace unsignedLongLongValue];

                //the root item must has finished calculating it's size, otherwise this doesn't work
                size = totalSpaceVal
                        - [[self root] sizeValue]
                        - freeSpaceVal;
            }
			break;
	}
	
	[self setSizeValue: size];
	
	if ( updateParent && ![self isRoot])
		[[self parent] childChanged: self oldSize: oldSize newSize: size];
}

//get display string for kind ("Application", "Simple Text Document", ...)
- (NSString *) kindName
{
	if ( ![self isSpecialItem] )
	{
	    if ( _kindName == nil )
			[self setKindString];
		
		return _kindName;
	}
	else
		return @"";
}

- (void) setKindString
{
	BOOL ignoreCreatorCode = NO;
	
	id delegate = [self delegate];
	if ( [delegate respondsToSelector: @selector(fsItemShouldIgnoreCreatorCode:)] )
		ignoreCreatorCode = [delegate fsItemShouldIgnoreCreatorCode: self];
	
	[self setKindStringIncludingChildren: NO];
}

//determines the kind of the file/folder as it is shown in the Finder's get info dialog.
//This routine tries to associate certain file criteria (type, creator, extension, ..)
//with the kind names so it can determine the kind name for similar files without asking
//the finder again and again.
- (void) setKindStringIncludingChildren: (BOOL) includingChildren
{
/*
    BOOL askLSCopyKindStringForTypeInfo = NO; //will be set to YES if file has type, creator or extension
	
	if ( [fileDesc isVolume] )
		kindNameKey = @".Volume";
	else if ( [self isAlias] )
		kindNameKey = @".Alias";
	else if (type != kLSUnknownType || creator != kLSUnknownCreator)
	{
		askLSCopyKindStringForTypeInfo = YES;
		kindNameKey = [[NSMutableString alloc] init];
		
		if (type != kLSUnknownType)
		{
			NSString *typeString = [[NSString alloc] initWithBytes:&type length:sizeof(OSType) encoding:NSMacOSRomanStringEncoding];
			[kindNameKey appendFormat:@"T:%@ ", typeString];
		}
		if (creator != kLSUnknownCreator)
		{
			NSString *creatorString = [[NSString alloc] initWithBytes:&creator length:sizeof(OSType) encoding:NSMacOSRomanStringEncoding];
			[kindNameKey appendFormat:@"C:%@ ", creatorString];
		}
		
		if (extension)
			[kindNameKey appendString: extension];
	}
	else if ( [fileDesc isDirectory] && ( extension == nil || ![fileDesc isPackage] ) ) //regular folder (no package)
		kindNameKey = @".Folder";
	else if ( extension != nil )
	{
		askLSCopyKindStringForTypeInfo = YES;
		kindNameKey = extension;
	}
	else if ( [fileDesc isExecutableBitSet] )
		kindNameKey = @".UnixExecutable";
	else
		kindNameKey = @".unknown";
	
	if ( g_kindNameDictionary == nil )
		g_kindNameDictionary = [[NSMutableDictionary alloc] init];
	
	NSString *kindName = [g_kindNameDictionary objectForKey: kindNameKey];
	
	if ( kindName != nil )
		[[self fileDesc] setKindString: kindName];
	else
	{
		if ( askLSCopyKindStringForTypeInfo )
			LSCopyKindStringForTypeInfo( type, creator, (CFStringRef)extension, (CFStringRef*) &kindName);	// kindName is retained
		
		if ( kindName == nil )
			kindName = [fileDesc kindString];
		
		if ( kindName != nil )
		{
			//remember kind name for similar files
			[g_kindNameDictionary setObject: kindName forKey: kindNameKey];Re: DiskInventory X is not compatible with MacOS Catalina (10.15)
			
			[fileDesc setKindString: kindName];
		}
		else
			LOG( @"couldn't get kind name for '%@'; will use default kind", [self path]);
	}
	
 */
    //What this needs is the UTI, and asking a URL for one is the most expensive
    //thing the whole walk does: LaunchServices answers NSURLTypeIdentifierKey by
    //reading the item's HFS type and creator, which means opening it. Measured
    //over /System/Library it is 1.55 s of an 8.0 s enumeration - more than any
    //other key, and more than everything this method then does with the answer.
    //
    //But a tree has tens of thousands of files and a few dozen extensions, and
    //the extension is what decides the type. So the first .dylib pays for the
    //lookup and the rest share the answer.
    //
    //The key has to carry everything else that can change the type:
    //
    // - directory or not, because a ".app" folder is a bundle and a ".app" file
    //   is not, and because a folder with no extension is just a folder;
    // - not an alias or a symlink, whose type is its own whatever it is named -
    //   NSURLIsAliasFileKey covers both, and unlike the type identifier it comes
    //   from the cheap attribute batch (measured at about 1% of enumeration);
    // - and an extensionless *file* is deliberately never cached, because with no
    //   extension the type falls back to the executable bit, so two of them need
    //   not agree.
    NSString *shapeKey = nil;

    if ( ( _flags & kFSItemIsAlias ) == 0 )
    {
        const BOOL isDirectory = [self isFolder];
        NSString *extension = [[self name] pathExtension];

        if ( isDirectory || [extension length] > 0 )
            shapeKey = [NSString stringWithFormat: @"%c:%@",
                                                   isDirectory ? 'd' : 'f',
                                                   [extension lowercaseString]];
    }

    if ( shapeKey != nil )
    {
        os_unfair_lock_lock( &g_kindNameLock );
        _kindName = [g_kindNameByShape objectForKey: shapeKey];
        os_unfair_lock_unlock( &g_kindNameLock );
    }

    if ( _kindName == nil )
    {
        //the one place the kind derivation still needs a URL, and only for the
        //first item of a given shape
        NSString *uti = [[self fileURL] UTI];

        if ( uti != nil )
        {
            os_unfair_lock_lock( &g_kindNameLock );
            _kindName = [g_kindNameDictionary objectForKey: uti];
            os_unfair_lock_unlock( &g_kindNameLock );
        }

        if ( _kindName == nil )
        {
            //Copy* returns +1, so ownership is transferred to ARC rather than bridged
            _kindName = CFBridgingRelease( UTTypeCopyDescription( (__bridge CFStringRef) uti ) );

            //remember kind name for similar files
            if ( _kindName != nil && uti != nil )
            {
                os_unfair_lock_lock( &g_kindNameLock );
                [g_kindNameDictionary setObject: _kindName forKey: uti];
                os_unfair_lock_unlock( &g_kindNameLock );
            }
        }

        if ( _kindName == nil )
            _kindName = [[self fileURL] getStringValue: NSURLLocalizedTypeDescriptionKey];

        //so the next item of the same shape does not repeat the lookup
        if ( _kindName != nil && shapeKey != nil )
        {
            os_unfair_lock_lock( &g_kindNameLock );
            [g_kindNameByShape setObject: _kindName forKey: shapeKey];
            os_unfair_lock_unlock( &g_kindNameLock );
        }
    }
    
    //let our childs do the same
	if ( includingChildren && [self isFolder] )
	{
		NSUInteger i = [self childCount];
		while ( i-- )
			[[self childAtIndex: i] setKindStringIncludingChildren: YES];
	}
}

- (NSString *) name
{
	switch ( [self type] )
	{
		case FileFolderItem:
			return _name != nil ? _name : @"";
		case FreeSpaceItem:
			return @"FreeSpaceItem";
		case OtherSpaceItem:
			return @"OtherSpaceItem";
	}
	
	NSAssert( NO, @"unknown item type" );
	return @"";
}

- (NSString *) path
{
	if ( ![self isSpecialItem] )
	{
		if ( [self isRoot] )
			return [_rootURL path];
		else
		{
			//parent path + "/" + name
			return [[[self parent] path] stringByAppendingPathComponent: [self name]];
		}
	}
	else
		return [self name];
}

- (NSString *) folderName
{
	if ( ![self isSpecialItem] )
	{
		FSItem *parent = [self parent];
		if ( parent == nil )
			return [[self path] stringByDeletingLastPathComponent];
		else
			return [parent path];
	}
	else
		return @"";
}

//display string for name (with or without extension; localized file names)
- (NSString *) displayName
{
	switch ( [self type] )
	{
		case FileFolderItem:
        {
            NSString *name = [[self fileURL] cachedDisplayName];
            if ( name == nil )
                name = [self name];
            if ( name == nil )
                name = @"";
			return name;
        }
		case FreeSpaceItem:
			return NSLocalizedString( @"free space on drive", @"" );
		case OtherSpaceItem:
			return NSLocalizedString( @"space occupied by other files and folders", @"" );
	}
	
	NSAssert( NO, @"unknown item type" );
	return @"";
}

- (NSString *) displayFolderName
{
	if ( ![self isSpecialItem] )
	{
		FSItem *parent = [self parent];
		if ( parent != nil )
			return [[parent displayFolderName] stringByAppendingPathComponent: [parent displayName]];
		else
			return @"";
	}
	else
		return @"";
}

- (NSString *) displayPath
{
	if ( ![self isSpecialItem] )
		return [[self displayFolderName] stringByAppendingPathComponent: [self displayName]];
	else
		return [self displayName];
}

#pragma mark -----------------comparison helpers-----------------------

- (NSComparisonResult) compareSize: (FSItem*) other
{
	//if just one of the 2 FSItems (self xor other) is a special item, then the special item is considered to be
	//smaller (so the special items are at the end of the child array)
	if ( [self isSpecialItem] ^ [other isSpecialItem] )
		return NSOrderedDescending;
	
	UInt64 mySize = [self sizeValue];
	UInt64 otherSize = [other sizeValue];
	
	if ( mySize > otherSize )
		return NSOrderedDescending;
	if ( mySize < otherSize )
		return NSOrderedAscending;
	
	//if both FSItems have the same size, order by their names
	//(we don't use displayName here as this may result in a call to "LSCopyDisplayNameForRef")
	return [[self name] compareAsFilesystemName: [other name]];
}

- (NSComparisonResult) compareDisplayName: (FSItem*) other
{
	return [[self displayName] compareAsFilesystemName: [other displayName]];
}

#pragma mark -----------------pasteboard support-----------------------

- (NSArray<NSPasteboardType>*) supportedPasteboardTypes
{
	//NSPasteboardTypeFileURL comes first, because a receiver takes the first type
	//it understands. NSFilenamesPboardType is kept for older receivers, but it can
	//no longer carry a file on its own: macOS stopped mapping it to public.file-url,
	//so it now arrives as an unregistered dynamic UTI that nothing recognises. That
	//is why dragging to the Finder, and copying a file, silently did nothing.
	NSMutableArray<NSPasteboardType> *types = [NSMutableArray arrayWithObjects: NSPasteboardTypeFileURL,
                                                                                FSItemLegacyFilenamesPasteboardType(),
                                                                                NSPasteboardTypeString,
                                                                                NSFileContentsPboardType,
                                                                                nil ];

    NSString * uti = [[self fileURL] cachedUTI];

#define TESTTYPE( test, type ) if ( [uti isEqualToString:(NSString*)test] ) [types addObject: type]

	TESTTYPE( kUTTypeRTF, NSPasteboardTypeRTF );
	TESTTYPE( kUTTypeRTFD, NSPasteboardTypeRTFD );
	TESTTYPE( kUTTypeHTML, NSPasteboardTypeHTML );
	TESTTYPE( kUTTypePDF, NSPasteboardTypePDF );

#undef TESTTYPE
    
    // add TIFF is this is an image
    if ( UTTypeConformsTo((__bridge CFStringRef)uti, kUTTypeImage) )
        [types addObject: NSPasteboardTypeTIFF];

	return types;
}

- (BOOL) supportsPasteboardType: (NSString*) type
{
	NSString * uti = [[self fileURL] cachedUTI];

	//Every branch below has a matching one in -pasteboard:provideDataForType:;
	//this method decides what is promised, that one has to deliver it.
	//
	//The HTML and PDF tests used to compare the file's UTI against the
	//pasteboard type name rather than the UTI ("NeXT HTML pasteboard type" and
	//friends), which can never match, so neither type was ever offered.
	return [type isEqualToString: NSPasteboardTypeFileURL]
			|| [type isEqualToString: FSItemLegacyFilenamesPasteboardType()]
			|| PasteboardTypeMatches( type, NSPasteboardTypeString )
			|| [type isEqualToString: NSFileContentsPboardType]
			|| (PasteboardTypeMatches( type, NSPasteboardTypeTIFF ) && UTTypeConformsTo((__bridge CFStringRef)uti, kUTTypeImage))
			|| (PasteboardTypeMatches( type, NSPasteboardTypeRTF ) && [uti isEqualToString:(__bridge NSString*)kUTTypeRTF])
			|| (PasteboardTypeMatches( type, NSPasteboardTypeRTFD ) && [uti isEqualToString:(__bridge NSString*)kUTTypeFlatRTFD])
			|| (PasteboardTypeMatches( type, NSPasteboardTypeHTML ) && [uti isEqualToString:(__bridge NSString*)kUTTypeHTML])
			|| (PasteboardTypeMatches( type, NSPasteboardTypePDF ) && [uti isEqualToString:(__bridge NSString*)kUTTypePDF]);
}

//The data is promised rather than written: -pasteboard:provideDataForType:
//supplies it if and when the receiver actually asks. Note that a pasteboard
//does not retain its owner — this is safe because an FSItem lives as long as
//the document's tree does.
- (void) writeToPasteboard: (NSPasteboard*) pboard
{
	[pboard declareTypes:[self supportedPasteboardTypes] owner:self];
}

//The Services machinery passes on whatever the chosen service asks for, which
//can include types this particular file cannot supply. -declareTypes:owner:
//promises data for everything it lists, so the request is filtered first and
//the pasteboard is left untouched if nothing survives.
- (void) writeToPasteboard: (NSPasteboard*) pasteboard withTypes: (NSArray<NSPasteboardType>*) types
{
	NSMutableArray<NSPasteboardType> *supportedTypes = [NSMutableArray arrayWithCapacity: [types count]];

	for ( NSPasteboardType type in types )
		if ( [self supportsPasteboardType: type] )
			[supportedTypes addObject: type];

	if ( [supportedTypes count] > 0 )
		[pasteboard declareTypes: supportedTypes owner: self];
}

- (void)pasteboard:(NSPasteboard *)pboard provideDataForType:(NSString *)type
{
	LOG( @"entering FSItem.pasteboard:provideDataForType: %@", type )
	
    NSURL *url = [self fileURL];
    NSString *path = [url cachedPath];
    NSString * uti = [url cachedUTI];

	if ([type isEqualToString:NSPasteboardTypeFileURL])
	{
		//how NSURL itself writes a file URL: the absolute string as UTF-8
		[pboard setString:[url absoluteString] forType:NSPasteboardTypeFileURL];
	}
	else if ([type isEqualToString:FSItemLegacyFilenamesPasteboardType()])
	{
		NSArray* pathsArray = [NSArray arrayWithObject: path];
		
		[pboard setPropertyList:pathsArray forType:FSItemLegacyFilenamesPasteboardType()];
	}
	else if (PasteboardTypeMatches( type, NSPasteboardTypeString ))
	{
		// set the path
		[pboard setString:path forType:NSPasteboardTypeString];
	}
	else if ([type isEqualToString:NSFileContentsPboardType])
	{
		// write the contents
		[pboard writeFileContents:path];
	}
    else if (PasteboardTypeMatches( type, NSPasteboardTypeTIFF ))
    {
        if ([uti isEqualToString: (__bridge NSString *)kUTTypeTIFF])
            [pboard setData:[NSData dataWithContentsOfFile:[url path]] forType:NSPasteboardTypeTIFF];
        else if ( UTTypeConformsTo((__bridge CFStringRef)uti, kUTTypeImage) )
        {
            // open the image and return TIFFRepresentation
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:[url path]];

            if (image)
            {
                NSData* data = [image TIFFRepresentation];

                if (data)
                    [pboard setData:data forType:NSPasteboardTypeTIFF];
            }
        }
    }
	else if (PasteboardTypeMatches( type, NSPasteboardTypeRTF ))
	{
		if ([uti isEqualToString:(__bridge NSString*)kUTTypeRTF])
			[pboard setData:[NSData dataWithContentsOfFile:path] forType:NSPasteboardTypeRTF];
	}
	else if (PasteboardTypeMatches( type, NSPasteboardTypeRTFD ))
	{
		if ([uti isEqualToString:(__bridge NSString*)kUTTypeFlatRTFD])
		{
			NSFileWrapper *tempRTFDData = [[NSFileWrapper alloc] initWithURL:[NSURL fileURLWithPath:path] options:0 error:NULL];
			[pboard setData:[tempRTFDData serializedRepresentation] forType:NSPasteboardTypeRTFD];
		}
	}
	else if (PasteboardTypeMatches( type, NSPasteboardTypeHTML ))
	{
		if ([uti isEqualToString:(__bridge NSString*)kUTTypeHTML])
			[pboard setData:[NSData dataWithContentsOfFile:path] forType:NSPasteboardTypeHTML];
	}
	else if (PasteboardTypeMatches( type, NSPasteboardTypePDF ))
	{
		if ([uti isEqualToString:(__bridge NSString*)kUTTypePDF])
			[pboard setData:[NSData dataWithContentsOfFile:path] forType:NSPasteboardTypePDF];
	}
	
	LOG( @"    exiting FSItem.pasteboard:provideDataForType: %@", type )
}

@end

//================ implementation FSItem(Private) ======================================================

//The resource keys the walk asks for. Shared by the two entry points below -
//the concurrent shallow pass over a scan root, and the deep walk of one
//subtree - so there is one list to keep honest rather than two.
static NSArray<NSURLResourceKey>* ScanResourceKeys( void )
{
	//Every key here is paid for twice per item: the enumerator prefetches them,
	//and -cacheResourcesInArray: below fetches each one again. So the list is
	//worth keeping honest.
	//
	//NSURLFileSizeKey and NSURLTotalFileAllocatedSizeKey used to be listed
	//twice each, which simply did that work twice. Measured over /System/Library
	//(435,460 items), enumerating and fetching every key: 8.99 s with the
	//duplicates, 8.58 s without them.
	//
	//NSURLIsPackageKey is gone, which takes it to 8.41 s. Only a directory can
	//be a package, and both callers ask only once past a directory test - this
	//method returns early on ![self isFolder], and -setKindString: short-
	//circuits on [fileDesc isDirectory] - so the answer was being computed for
	//every file to be looked at for almost none of them. Nothing sees a
	//different value: -getCachedResourceValue: falls back to a live fetch and
	//caches it, so the folders that ask still get an answer.
	//
	//The larger cost is NSURLTypeIdentifierKey, and it is deliberately still
	//here. It and NSURLIsPackageKey are both answered by LaunchServices, which
	//reads the item's HFS type and creator - opening the file to do it - so
	//they share that work and dropping only one saves little: without the type
	//identifier as well the same walk is 6.69 s, against 8.41 s for dropping
	//IsPackage alone. But the type identifier is what -setKindString: needs,
	//and every item needs a kind eventually, for the statistics and the
	//treemap's colours. Dropping it here would defer that cost rather than
	//remove it, and lose the enumerator's batching with it. Worth revisiting
	//only together with making kind determination lazy.
	static NSArray *keys = nil;
	static dispatch_once_t once;
	dispatch_once( &once, ^{
		keys = @[ //NSURLLocalizedNameKey,
                                           NSURLNameKey,
                                           NSURLIsVolumeKey,
                                           NSURLIsDirectoryKey,
                                           //NSURLIsAliasFileKey covers a Finder alias and a symlink
                                           //alike, and is what keeps those off the extension-keyed
                                           //kind cache. It rides along in the cheap attribute batch;
                                           //NSURLTypeIdentifierKey, which used to be here, does not -
                                           //it is answered by LaunchServices, one file open each, and
                                           //is now fetched only for the first item of a given shape.
                                           NSURLIsAliasFileKey,
                                           //NSURLLocalizedTypeDescriptionKey,
                                           //NSURLTotalFileSizeKey rather than NSURLFileSizeKey: the
                                           //two size accessors ask for TotalFileSize and
                                           //TotalFileAllocatedSize, so prefetching FileSizeKey
                                           //cached a key nothing reads first while leaving the one
                                           //logical sizes actually want to be fetched per file,
                                           //outside the enumerator's batch. It is also what
                                           //-cachedPhysicalSize falls back to.
                                           NSURLTotalFileSizeKey,
                                           NSURLTotalFileAllocatedSizeKey ];
	});

	return keys;
}

@implementation FSItem(Private)

- (id) initWithURL: (NSURL*)url
            parent: (FSItem*) parent
     setKindString: (BOOL) setKindString
{
    self = [super init];
	
	_type = FileFolderItem;
    _parent = parent;	//no retain
    
    if ( parent != nil )
        [parent->_childs addObject: self];
    
    //_hash = 0;	//will be generated on demand (see FSItem.hash)
	
    //Everything this item will ever be asked for in bulk is taken from the URL
    //here and kept as an ivar, so the URL itself need not be - it goes out of
    //scope with the enumerator's autorelease pool, and the _FileCache
    //CoreServices attached to it goes with it. That is where the memory was.
    //Read straight from the URL, not through -cacheResourcesInArray:. That side
    //dictionary existed because NSURL purges its own cache on a run-loop pass and
    //the values were wanted again later; nothing wants them later now, and every
    //one of them is read exactly once, here, while the enumerator's prefetch is
    //still warm. It was 9.3 million dictionaries on a volume scan.
    _name = [url name];

    const BOOL isFolder = [url isDirectory];

    if ( isFolder )
        _flags |= kFSItemIsFolder;

    if ( [url isAliasOrSymbolicLink] )
        _flags |= kFSItemIsAlias;

    //Both sizes, not the one the current mode wants: -recalculateSize: is run
    //again when the preference is toggled, and going back to the file system for
    //4.6 million files at that point is not an option now the URLs are gone.
    _logicalSize  = [[url logicalSize] unsignedLongLongValue];
    _physicalSize = [[url physicalSize] unsignedLongLongValue];

	if ( isFolder )
        _childs = [[NSMutableArray<FSItem*> alloc] init];
	
	if ( setKindString )
		[self setKindStringIncludingChildren: NO];
	
    if ( isFolder )
		g_folderCount++;
    else
    {
        g_fileCount++;

        //The running total and the biggest-so-far list, both for the scanning
        //screen. Only files: a folder's size is the sum of what is under it and
        //is not known until the walk leaves it.
        const unsigned long long counted = g_scanUsesPhysicalSize ? _physicalSize : _logicalSize;

        atomic_fetch_add_explicit( &g_bytesFound, counted, memory_order_relaxed );

        RememberIfBiggest( _name, _kindName, counted );
    }

    return self;
}

- (void) setParent: (FSItem*) parent
{
	_parent = parent; //weak reference (parents owns us)
	
	_delegate = nil; //we use our parent's delegate
	
	//_hash = 0; //our hash is now invalid as it depends on the path
}

- (void) onParentDealloc
{
	_parent = nil;
}


//How many subtrees to walk at once when the delegate does not say. The walk is
//I/O bound - sampling it finds getattrlistbulk and the open(2) of each
//directory, with userspace down to noise - so what this buys is several
//requests outstanding at a time rather than several cores busy. Measured over
///System/Library: 1.52x at two, 1.96x at four, 2.23x at eight, and flat after.
//
//The document answers with the ScanConcurrency preference instead, because the
//best value depends on the drive rather than on the machine: an internal SSD
//likes several requests in flight, a network share may not. Two is the default
//there - a real gain, and a modest number of directories open at once.
static const NSUInteger kDefaultConcurrentSubtreeWalks = 2;

//The scan root is walked one level deep, and each subdirectory below it is then
//walked whole, several at a time. Everything under a given subdirectory stays on
//one queue, so the deep walk itself is untouched - it is the same method the
//firmlink case has always called.
//
//Splitting only at the top level is crude: a root whose weight is in one child
//gains little, which is what /Applications does (1.48x, where /System/Library
//gets 2.23x). It is also the split that needs no changes to the tree building at
//all, since each queue owns its own subtree and touches nobody else's array.
//Whether a child is worth handing to an enumerator of its own.
//
//The answer is taken from a freshly made URL, not from the one the directory
//enumerator handed back, because the two disagree. /.nofollow is a directory
//that mirrors the entire root volume - its listing is /'s listing, itself
//included - and the enumerator's batched attributes describe it as an ordinary
//directory, isVolume NO, while stat'ing that path on its own answers YES.
//
//A flat walk never had to care: NSDirectoryEnumerator declines to descend into
//it of its own accord. Walking subtrees separately bypasses whatever policy it
//was applying, and this one cost the whole volume twice - a scan of / built
//4,647,615 items where the volume holds 2,323,854, half of them under
///.nofollow, with sizes and memory to match.
//
//The identifier test is the general form of the same thing: a child that is the
//scan root over again is a mirror whatever it happens to be called.
static BOOL ShouldWalkSubtreeSeparately( NSURL *childUrl, NSURL *rootUrl )
{
	NSURL *freshUrl = [NSURL fileURLWithPath: [childUrl path]];

	NSNumber *isVolume = nil;
	[freshUrl getResourceValue: &isVolume forKey: NSURLIsVolumeKey error: nil];

	if ( [isVolume boolValue] )
		return NO;

	id childId = nil, rootId = nil;
	[freshUrl getResourceValue: &childId forKey: NSURLFileResourceIdentifierKey error: nil];
	[rootUrl getResourceValue: &rootId forKey: NSURLFileResourceIdentifierKey error: nil];

	return !( childId != nil && rootId != nil && [childId isEqual: rootId] );
}

- (void) loadChildrenConcurrentlyWithKindStrings: (BOOL) setKindStrings
								 usePhysicalSize: (BOOL) usePhysicalSize
{
	if ( ![self isFolder] )
		return;

	id delegate = [self delegate];

	if ( [delegate respondsToSelector: @selector(fsItemEnteringFolder:)]
		 && ![delegate fsItemEnteringFolder: self] )
	{
		[NSException raise: FSItemLoadingCanceledException format: @""];
	}

	_childs = [[NSMutableArray alloc] init];

	NSArray<NSURLResourceKey> *urlProperties = ScanResourceKeys();

	NSDirectoryEnumerator *dirEnum =
		[[NSFileManager defaultManager] enumeratorAtURL: [self fileURL]
							 includingPropertiesForKeys: urlProperties
												options: NSDirectoryEnumerationSkipsSubdirectoryDescendants
										   errorHandler: ^(NSURL *url, NSError *error)
		{
			LOG(@"error listing '%@': %@", [url path], error);

			if ( [url isEqualToURL: [self fileURL]] )
				return (BOOL) NO;

			atomic_fetch_add_explicit( &g_skippedCount, 1, memory_order_relaxed );
			return (BOOL) YES;
		}];

	NSUInteger concurrency = kDefaultConcurrentSubtreeWalks;

	if ( [delegate respondsToSelector: @selector(fsItemMaxConcurrentSubtreeWalks:)] )
		concurrency = [delegate fsItemMaxConcurrentSubtreeWalks: self];

	if ( concurrency < 1 )
		concurrency = 1;

	NSMutableArray<FSItem*> *subtrees = [[NSMutableArray alloc] init];

	for ( NSURL *currentUrl in dirEnum )
	{
		FSItem *child = [[FSItem alloc] initWithURL: currentUrl
											 parent: self
									  setKindString: setKindStrings];

		//a volume mounted below this folder is somebody else's tree, and a
		//directory that turns out to be this one again is nobody's
		if ( [child isFolder] && ShouldWalkSubtreeSeparately( currentUrl, [self fileURL] ) )
			[subtrees addObject: child];
	}

	if ( concurrency > 1 && [subtrees count] > 1 )
	{
		dispatch_queue_t queue = dispatch_get_global_queue( QOS_CLASS_UTILITY, 0 );
		dispatch_group_t group = dispatch_group_create();
		dispatch_semaphore_t slots = dispatch_semaphore_create( (intptr_t) concurrency );

		//A cancelled scan raises, and an exception raised on one of these queues
		//cannot be caught by whoever called us - the same reason
		//-_runScanBlockOffMainThread: carries one back by hand. So each subtree
		//catches its own and the first is re-raised here, on the calling thread,
		//where the existing machinery is waiting for it.
		__block NSException *failure = nil;
		NSLock *failureLock = [[NSLock alloc] init];

		for ( FSItem *subtree in subtrees )
		{
			[failureLock lock];
			const BOOL alreadyFailed = ( failure != nil );
			[failureLock unlock];

			//cancelling should stop handing out work, not merely stop doing it
			if ( alreadyFailed )
				break;

			dispatch_semaphore_wait( slots, DISPATCH_TIME_FOREVER );

			dispatch_group_async( group, queue, ^{
				@autoreleasepool
				{
					@try
					{
						[subtree loadChildrenAndSetKindStrings: setKindStrings
											   usePhysicalSize: usePhysicalSize];
					}
					@catch ( NSException *exception )
					{
						[failureLock lock];
						if ( failure == nil )
							failure = exception;
						[failureLock unlock];
					}
				}

				dispatch_semaphore_signal( slots );
			});
		}

		dispatch_group_wait( group, DISPATCH_TIME_FOREVER );

		if ( failure != nil )
			[failure raise];
	}
	else
	{
		for ( FSItem *subtree in subtrees )
			[subtree loadChildrenAndSetKindStrings: setKindStrings
								   usePhysicalSize: usePhysicalSize];
	}

	if ( [delegate respondsToSelector: @selector(fsItemExittingFolder:)]
		 && ![delegate fsItemExittingFolder: self] )
	{
		[NSException raise: FSItemLoadingCanceledException format: @""];
	}

	[self recalculateSize: usePhysicalSize updateParent: NO];
}

- (void) loadChildrenAndSetKindStrings: (BOOL) setKindStrings
					   usePhysicalSize: (BOOL) usePhysicalSize
{
    if ( ![self isFolder] )
        return;
	
	id delegate = [self delegate];
	
    //should we cancel the loading?
    if ( [delegate respondsToSelector: @selector(fsItemEnteringFolder:)]
        && ![delegate fsItemEnteringFolder: self] )
    {
        [NSException raise: FSItemLoadingCanceledException format: @""];
    }

    _childs = [[NSMutableArray alloc] init];

    //should the kind strings of our childs should be set initially?
	//this an optimization
	if ( setKindStrings && ![self isRoot] )
	{
		if ( ![delegate respondsToSelector:@selector(fsItemShouldLookIntoPackages:)]
			|| ![delegate fsItemShouldLookIntoPackages: self] )
		{
			setKindStrings = ![self isPackage];
		}
	}
    
    NSArray<NSString*> *urlProperties = ScanResourceKeys();

    // stack of directories (Path to directory currently beeing canned)
    NSMutableArray<FSItem*> *itemStack = [[NSMutableArray alloc] init];
    
    [itemStack addObject:self];
    
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtURL: [self fileURL]
                                                          includingPropertiesForKeys: urlProperties
                                                                             options: 0//NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                        errorHandler: ^(NSURL *url, NSError *error)
                                      {
                                          // Handle the error.
                                          // Return YES if the enumeration should continue after the error.
                                          LOG(@"error listing '%@': %@", [url path], error);
                                          // stop if there is a problem with the directory itself
                                          if ( [url isEqualToURL: [self fileURL]])
                                              return NO;

                                          //Counted, not just logged: the scanning
                                          //screen says how many, and a scan of a
                                          //volume that quietly skipped a thousand
                                          //protected folders is a scan whose total
                                          //means something different.
                                          atomic_fetch_add_explicit( &g_skippedCount, 1,
                                                                     memory_order_relaxed );
                                          return YES;
                                      }
                                      ];
    NSUInteger lastEnumLevel = 1;
    BOOL lastItemWasDir = NO;
    FSItem *lastDirItem = nil;
    
    for ( NSURL *currentUrl in dirEnum)
    {
        
        if ( [dirEnum level] > lastEnumLevel )
        {
#ifdef DEBUG
            // we have entered a sub directory
            // we expect NSDirectoryEnumerator do do a "deep first" search, so:
            
            NSAssert(lastItemWasDir, @"if we are now one level deeper, the last item must have been a directory");
            NSAssert(lastDirItem == [[itemStack lastObject]->_childs lastObject], @"lastDirItem is supposed to be last item added as last child\n   last dir:            '%@'\n    last child:  '%@'",
                     [[lastDirItem fileURL] path], [[[[itemStack lastObject]->_childs lastObject] fileURL] path]);
            // level must be one deeper
            NSAssert( (lastEnumLevel +1) == [dirEnum level], @"not dived into dir?? current level: %lu, last level: %lu", lastEnumLevel, [dirEnum level]);
            
            NSURL *lastDirUrl = [lastDirItem fileURL];
            
            // "item" must be immediate child of "lastDir"
            NSAssert([currentUrl residesInDirectoryURL: lastDirUrl], @"current item is not child of last dir\n    current path: '%@'\n    current dir:  '%@'\n   last dir:            '%@'",
                     [currentUrl path],
                     [[currentUrl path] stringByDeletingLastPathComponent],
                     [lastDirUrl path]);
#endif
            [itemStack addObject: lastDirItem];
            
            //should we cancel the loading?
            if ( [delegate respondsToSelector: @selector(fsItemEnteringFolder:)]
                && ![delegate fsItemEnteringFolder: lastDirItem] )
            {
                [NSException raise: FSItemLoadingCanceledException format: @""];
            }
        }
        else if ([dirEnum level] < lastEnumLevel )
        {
            // level can be one or more steps higher
            NSUInteger levelsWalkedUp = lastEnumLevel - [dirEnum level];
            
            // walk n levels up
            for ( NSUInteger i = 0; i < levelsWalkedUp; i++ )
            {
                //should we cancel the loading?
                if ( [delegate respondsToSelector: @selector(fsItemExittingFolder:)]
                    && ![delegate fsItemExittingFolder: [itemStack lastObject]] )
                {
                    [NSException raise: FSItemLoadingCanceledException format: @""];
                }

                [itemStack removeLastObject];
            }
            
#ifdef DEBUG
            // .. and check whether the current url resides in that directory
            NSURL *directoryURLExpected = [[itemStack lastObject] fileURL];
            
            // "currentUrl" must be immediate child of "directoryURLExpected"
            NSAssert([currentUrl residesInDirectoryURL: directoryURLExpected], @"current item is not child of last dir\n    current path: '%@'\n    current dir:  '%@'\n   dir expected:            '%@'",
                     [currentUrl path],
                     [[currentUrl path] stringByDeletingLastPathComponent],
                     [directoryURLExpected path]);
#endif
        }
        else
        {
#ifdef DEBUG
            // "item" must be immediate child of current directory
            NSAssert([currentUrl residesInDirectoryURL: [[itemStack lastObject] fileURL]], @"current item is not child of last dir\n    current path: '%@'\n    current dir:  '%@'\n   last dir:            '%@'",
                     [currentUrl path],
                     [[currentUrl path] stringByDeletingLastPathComponent],
                     [[[itemStack lastObject] fileURL] path]);
#endif
        }
        
        FSItem *currentItem = [[FSItem alloc] initWithURL: currentUrl
                                                   parent: [itemStack lastObject]
                                            setKindString: setKindStrings];

        //Both tests below only ever answer YES for a directory - a firmlink is
        //one, and so is a volume's root - so a file need not be asked at all.
        //Folder-ness comes from the item, which read it while the enumerator's
        //prefetch was warm, rather than from the URL a second time.
        //That matters most for -isFirmlink, which is a lookup in a dictionary
        //keyed by NSURL, so every item was paying to hash a URL to discover it
        //was not one of the handful of firmlinks.
        const BOOL isDirectory = [currentItem isFolder];

        if ( isDirectory && [currentUrl isFirmlink] )
        {
            // tests show that firmlinks are not followed by NSDirectoryEnumerator, but
            // Apple tends to change thinks so we tell the enumerator to not enter the directory
            [dirEnum skipDescendants];
            [currentItem loadChildrenAndSetKindStrings: setKindStrings
                                       usePhysicalSize: usePhysicalSize];
        }
        else if ( isDirectory && [currentUrl isVolume] )
        {
            // on 10.15 Beta 7 the mount point /System/Volume/data is followed,
            // although this should not be the case according to the docs
            [dirEnum skipDescendants];
        }

        lastItemWasDir = isDirectory;
        
        lastDirItem = lastItemWasDir ? currentItem : nil;
        
        lastEnumLevel = [dirEnum level];
        
    }
 
    // signal exiting of remaining folders
    for ( FSItem * stackItem in [itemStack reverseObjectEnumerator] )
    {
        //should we cancel the loading?
        if ( [delegate respondsToSelector: @selector(fsItemExittingFolder:)]
            && ![delegate fsItemExittingFolder: stackItem] )
        {
            [NSException raise: FSItemLoadingCanceledException format: @""];
        }
     }
    
    
	//usePhysicalSize, not a hardcoded YES. It is threaded down from
	//-fsItemShouldUsePhysicalFileSize: for exactly this, and passing YES
	//regardless meant a scan always produced allocated sizes: with the
	//preference off the tree still showed them, and went on showing them until
	//the user toggled the preference, because -recalculateTotalSize is only
	//ever called from -setShowPhysicalFileSize:. The default is on, which is
	//why this was invisible unless you turned it off.
	[self recalculateSize: usePhysicalSize updateParent: NO];
}

//compare the size of 2 FSItems
- (NSComparisonResult) compareSizeDescendingly: (FSItem*) other
{
	//flip result of compareSize:
	switch( [self compareSize: other] )
	{
		case NSOrderedDescending:
			return NSOrderedAscending;
		case NSOrderedAscending:
			return NSOrderedDescending;
		default:
			return NSOrderedSame;
	}
}

- (void) setSize: (NSNumber*) newSize
{
	NSParameterAssert( newSize != nil );
	
	if ( _size != newSize )
	{
		_size = newSize;
		
		_sizeValue = [_size unsignedLongLongValue];
	}
}

- (void) setSizeValue: (unsigned long long) newSize
{
	_sizeValue = newSize;
	_size = nil;
}

- (void) childChanged: (FSItem*) child
			  oldSize: (unsigned long long) oldSize
			  newSize: (unsigned long long) newSize
{
	if ( oldSize == newSize )
		return;
	
	unsigned long long myOldSize = [self sizeValue];
	unsigned long long myNewSize = myOldSize - oldSize + newSize;
	
	//child will be released by "removeChild", so prevent it from beeing freed
	
	//keep childs array sorted
	[self removeChild: child updateParent: NO];
	[self insertChild: child updateParent: NO];
	
	[self setSizeValue: myNewSize];
	
	if ( ![self isRoot] )
		[[self parent] childChanged: self oldSize: myOldSize newSize: myNewSize];
}

@end

