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

//for debugging and logging purposes
unsigned g_fileCount;
unsigned g_folderCount;
static unsigned g_packageCheckCount = 0;

//global cache for kind names
NSMutableDictionary *g_kindNameDictionary = nil;

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
	  setKindString: (BOOL) setKindString
	usePhysicalSize: (BOOL) usePhysicalSize;

- (void) setParent: (FSItem*) parent;
- (void) onParentDealloc;

- (NSComparisonResult) compareSizeDescendingly: (FSItem*) other; //compares sizes

- (void) loadChildrenAndSetKindStrings: (BOOL) setKindStrings
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
	//instantiate the dictionaries for global kind names cache
	g_kindNameDictionary = [[NSMutableDictionary alloc] init];
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
    
    _fileURL = url;
    
    if ( [url isDirectory] )
        _childs = [[NSMutableArray alloc] init];
    
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

- (NSURL *) fileURL
{
	if ( ![self isSpecialItem] )
		return _fileURL;
	else
		return [[self root] fileURL];
}

- (void) setFileURL: (NSURL*) url
{
	NSAssert( ![self isSpecialItem], @"free and other space items don't habe a NTFileDesc object");
	
	_fileURL = url;
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
	if ( ![self isSpecialItem] )
	{
		return [[self fileURL] cachedIsDirectory];
	}
	else
		return NO;
}

- (BOOL) isPackage
{
	if ( ![self isSpecialItem] )
		return [[self fileURL] cachedIsPackage];
	else
		return NO;
}

- (BOOL)isAlias
{
	if ( ![self isSpecialItem] )
	{
		return [[self fileURL] cachedIsAliasOrSymbolicLink];
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
	[self loadChildrenAndSetKindStrings: YES
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
				//File
				if ( usePhysicalSize )
					size = [[[self fileURL] cachedPhysicalSize] unsignedLongLongValue];
				else
					size = [[[self fileURL] cachedLogicalSize] unsignedLongLongValue];
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
    NSString *uti = [[self fileURL] cachedUTI];
    
    if ( g_kindNameDictionary == nil )
        g_kindNameDictionary = [[NSMutableDictionary alloc] init];

    _kindName = [g_kindNameDictionary objectForKey: uti];

    if ( _kindName == nil )
    {
        //Copy* returns +1, so ownership is transferred to ARC rather than bridged
        _kindName = CFBridgingRelease( UTTypeCopyDescription( (__bridge CFStringRef) uti ) );
        
        //remember kind name for similar files
        if ( _kindName != nil )
            [g_kindNameDictionary setObject: _kindName forKey: uti];
     }

    if ( _kindName == nil )
    {
        _kindName = [[self fileURL] getCachedStringValue: NSURLLocalizedTypeDescriptionKey];
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
			return [[self fileURL] cachedName];
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
			return [[self fileURL] cachedPath];
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
                name = [[self fileURL] cachedName];
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

@implementation FSItem(Private)

- (id) initWithURL: (NSURL*)url
            parent: (FSItem*) parent
     setKindString: (BOOL) setKindString
   usePhysicalSize: (BOOL) usePhysicalSize
{
    self = [super init];
	
	_type = FileFolderItem;
    _parent = parent;	//no retain
    
    if ( parent != nil )
        [parent->_childs addObject: self];
    
    //_hash = 0;	//will be generated on demand (see FSItem.hash)
	
    _fileURL = url;
	
	BOOL isFolder = [_fileURL isDirectory];

	if ( !isFolder )
	{
		//-physicalSize and -logicalSize hand back an NSNumber; passing it
		//straight to -setSizeValue: stored the pointer as the size. Harmless in
		//practice only because -recalculateSize:updateParent: overwrites every
		//size before anything displays one.
		 if ( usePhysicalSize )
			[self setSizeValue: [[url physicalSize] unsignedLongLongValue]];
		 else
			[self setSizeValue: [[url logicalSize] unsignedLongLongValue]];
	}
    else
        _childs = [[NSMutableArray<FSItem*> alloc] init];
	
	if ( setKindString )
		[self setKindStringIncludingChildren: NO];
	
    if ( isFolder )
		g_folderCount++;
    else
        g_fileCount++;
	
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
    
    NSArray<NSString*> *urlProperties = [NSArray<NSString*> arrayWithObjects:
                                        //NSURLLocalizedNameKey,
                                        NSURLNameKey,
                                        NSURLIsVolumeKey,
                                        NSURLIsPackageKey,
                                        NSURLIsDirectoryKey,
                                        //NSURLIsSymbolicLinkKey,
                                        NSURLTypeIdentifierKey,
                                        //NSURLLocalizedTypeDescriptionKey,
                                        NSURLFileSizeKey,
                                        NSURLTotalFileAllocatedSizeKey,
                                        NSURLFileSizeKey,
                                        NSURLTotalFileAllocatedSizeKey,
                                        nil];

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
                                          else
                                              return YES;
                                      }
                                      ];
    NSUInteger lastEnumLevel = 1;
    BOOL lastItemWasDir = NO;
    FSItem *lastDirItem = nil;
    
    for ( NSURL *currentUrl in dirEnum)
    {
        // cache all needed properties (NSURL purges all values upon next pass through the run loop)
        [currentUrl cacheResourcesInArray: urlProperties];
        
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
                                            setKindString: setKindStrings
                                          usePhysicalSize: usePhysicalSize];
        
        if ( [currentUrl isFirmlink] )
        {
            // tests show that firmlinks are not followed by NSDirectoryEnumerator, but
            // Apple tends to change thinks so we tell the enumerator to not enter the directory
            [dirEnum skipDescendants];
            [currentItem loadChildrenAndSetKindStrings: setKindStrings
                                       usePhysicalSize: usePhysicalSize];
        }
        else if ( [currentUrl isVolume] )
        {
            // on 10.15 Beta 7 the mount point /System/Volume/data is followed,
            // although this should not be the case according to the docs
            [dirEnum skipDescendants];
        }
        
        lastItemWasDir = [currentUrl isDirectory];
        
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
    
    
	[self recalculateSize:YES updateParent:NO];
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

