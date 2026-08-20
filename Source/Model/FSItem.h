//
//  FSItem.h
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

//Incremented as each item is created, on whichever queue created it - subtrees
//are walked concurrently - so these are atomic. Readers get a snapshot that may
//be a few items stale, which is all a progress bar needs.
extern _Atomic unsigned g_fileCount;
extern _Atomic unsigned g_folderCount;

@interface NSString (ComparisonAdditions)
- (NSComparisonResult) compareAsFilesystemName: (NSString*) other;
@end

typedef enum
{
	FileFolderItem, //regular file or folder
	OtherSpaceItem, //represents "other" space (that means the space occupied by the rest of the files on the volume)
	FreeSpaceItem	//free space on volume
} FSItemType;

//Which of an item's fields a search looks at. Declared here rather than in
//FSItemIndex.h, its natural home, because FileSystemDoc's search API needs the
//type and FSItemIndex.h imports FileSystemDoc.h for FileKindStatistic - so the
//enum is the one piece of that header that cannot live behind the cycle.
typedef enum
{
	FSItemIndexName = 1,
	FSItemIndexKind = 2,
	FSItemIndexPath = 4,
	FSItemIndexAll = 0xffff
} FSItemIndexType;

//Flags kept in one byte rather than as four BOOLs, because there are millions
//of these. isPackage is resolved on demand and remembered, since only a folder
//is ever asked and answering means going to LaunchServices.
enum
{
	kFSItemIsFolder			= 1 << 0,
	kFSItemIsAlias			= 1 << 1,
	kFSItemIsPackage		= 1 << 2,
	kFSItemPackageResolved	= 1 << 3,
};

@interface FSItem : NSObject {
	//Only the root of a scan keeps a URL. Every other item keeps its name and
	//builds one from the chain when asked - see -fileURL.
	//
	//A retained NSURL costs far more than it looks. Measured on a whole-volume
	//scan of 4,646,058 items, which came to 5.3 GB: the NSURLs were 446 MB, the
	//_FileCache CoreServices attaches to each one as soon as a resource value is
	//read was 1,487 MB, and the dictionaries this code cached values in were
	//1,169 MB - together 57% of the process, against 7% for the FSItems
	//themselves. A name-only node measured 103 bytes an item against 1,129.
	NSURL *_rootURL;			//root items only; nil for everything below
	NSString *_name;			//everything below the root
	//Unretained on purpose: _childs owns downwards, so a strong back-pointer
	//would be a cycle on every node in the tree. __unsafe_unretained rather
	//than __weak because a scan builds millions of these and -dealloc already
	//clears the children's pointers by hand (see -onParentDealloc).
	__unsafe_unretained FSItem *_parent;	//only valid for non-root items
	NSMutableDictionary *_icons; //holds icons in various sizes (see iconWithSize:)
	FSItemType _type;
    NSNumber *_size;
	UInt64 _sizeValue;
	//The two sizes a file reports, so -recalculateSize: can answer for either
	//mode without going back to the file system. They used to be read back out
	//of the URL's resource cache, which is one of the things that made keeping
	//that cache unavoidable.
	UInt64 _logicalSize;
	UInt64 _physicalSize;
    NSString *_kindName;
    //unsigned _hash;
    NSMutableArray<FSItem*> *_childs;
	uint8_t _flags;
	__unsafe_unretained id _delegate;	//not retained
}

- (id) initWithPath: (NSString *) path;
- (id) initWithURL: (NSURL *) url;

- (id) initAsOtherSpaceItemForParent: (FSItem*) parent;
- (id) initAsFreeSpaceItemForParent: (FSItem*) parent;

- (id) delegate;
- (void) setDelegate: (id) delegate;

- (FSItemType) type;
- (BOOL) isSpecialItem;

- (NSURL *) fileURL;
- (void) setFileURL: (NSURL*) url;

- (void) loadChildren;

- (NSString *) description;

- (BOOL) isFolder; //returns NO for an alias pointing to a directory (in contrast to NTFileDesc.isDirectory)
- (BOOL) isPackage;
- (BOOL) isAlias;

- (BOOL) exists;

- (BOOL) isRoot;
- (FSItem*) parent;
- (FSItem*) root;

- (NSImage*) iconWithSize: (unsigned) iconSize;

- (NSEnumerator *) childEnumerator;
- (FSItem*) childAtIndex: (NSUInteger) index;
- (NSUInteger) childCount;

- (void) removeChild: (FSItem*) child updateParent: (BOOL) updateParent; //child will be released!
- (void) insertChild: (FSItem*) newChild updateParent: (BOOL) updateParent;
- (void) replaceChild: (FSItem*) oldChild withItem: (FSItem*) newChild updateParent: (BOOL) updateParent;

- (void) recalculateSize: (BOOL) usePhysicalSize updateParent: (BOOL) updateParent;
	//just recalculates size (no file system access)

- (void) setKindString; //will ask delegate whether to ignore creator codes
- (void) setKindStringIncludingChildren: (BOOL) includingChildren;

- (NSNumber*) size;
- (unsigned long long) sizeValue;

- (NSString *) name;
- (NSString *) path;
- (NSString *) folderName;

- (NSString *) displayName;
- (NSString *) displayFolderName; //folder name relative to root item, not "/"
- (NSString *) displayPath; //path relative to root item, not "/"
- (NSString *) kindName;

- (NSComparisonResult) compareSize: (FSItem*) other;
- (NSComparisonResult) compareDisplayName: (FSItem*) other;

- (NSArray<NSPasteboardType>*) supportedPasteboardTypes;
- (BOOL) supportsPasteboardType: (NSString*) type;
//NSFilenamesPboardType, which was deprecated in 10.14 and has no replacement.
//It is still offered for receivers that predate NSPasteboardTypeFileURL, so the
//deprecation is isolated behind this rather than suppressed at each use.
NSPasteboardType FSItemLegacyFilenamesPasteboardType( void );

- (void) writeToPasteboard: (NSPasteboard*) pasteboard;
- (void) writeToPasteboard: (NSPasteboard*) pasteboard withTypes: (NSArray*) types;

//- (unsigned) hash;
@end

/* optional delegate methods */
@interface NSObject(FSItemDelegate)
- (BOOL) fsItemEnteringFolder: (FSItem*) item; //delegate may return NO to stop loading in "loadChilds"
- (BOOL) fsItemExittingFolder: (FSItem*) item;
- (BOOL) fsItemShouldIgnoreCreatorCode: (FSItem*) item; //default is NO (if not implemented by delegate)
- (BOOL) fsItemShouldLookIntoPackages: (FSItem*) item; //set kind string in "loadChilds?";
													   //default is NO (if not implemented by delegate)
- (BOOL) fsItemShouldUsePhysicalFileSize: (FSItem*) item;
- (NSUInteger) fsItemMaxConcurrentSubtreeWalks: (FSItem*) item; //1 walks in order; default if not implemented
@end

//Exception raised by FSItem
//delegate canceled the loading (see above)
extern NSString* FSItemLoadingCanceledException;
//error while enumerating files/folders (e.g. volume has been ejected (unmounted)) 
extern NSString* FSItemLoadingFailedException;
