//
//  MyDocument.m
//  Disk Accountant
//
//  Created by Tjark Derlien on Wed Oct 08 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "FileSystemDoc.h"
#import <sys/param.h>
#import <sys/mount.h>
#import "NSAlert-Extensions.h"
#import "NSURL-Extensions.h"
#import "MainWindowController.h"
#import "FileSizeFormatter.h"
#import "Timing.h"
#import "FSItem-Utilities.h"
#import "NSFileManager-Extensions.h"
#import "DIXRecentScans.h"
#import "DIXScanHistory.h"
#import "FSItemIndex.h"

NSString *CollectFileKindStatisticsCanceledException = @"CollectFileKindStatisticsCanceledException";

//============ implementation FileKindStatistic ==========================================================

@implementation FileKindStatistic

- (id) initWithItem: (FSItem*) item
{
    self = [super init];
    
    _kindName = [item kindName];

	_size = [item sizeValue];
	
	_items = [[NSMutableSet alloc] initWithObjects: item, nil];

    return self;
}


- (void) addItem: (FSItem* )item
{
	NSParameterAssert( ![_items containsObject: item] );
	
	[_items addObject: item];
	
	_size += [item sizeValue];
}

- (void) removeItem: (FSItem* )item
{
	NSParameterAssert( [_items containsObject: item] );
	
	_size -= [item sizeValue];
	
	[_items removeObject: item];
}

- (NSString*) description
{
    return [[self kindName] stringByAppendingFormat: @" {%lu files; %.1f kB}", (unsigned long) [self fileCount], (float) [self size]/1024]; 
}

- (NSString*) kindName
{
    return _kindName;
}

//# of files of this kind
- (NSUInteger) fileCount
{
	return [_items count];
}

//sum of sizes of files of this kind
- (unsigned long long) size
{
	return _size;
}

- (void) recalculateSize
{
	NSEnumerator *itemEnum = [self itemEnumerator];
	FSItem *item = nil;
	_size = 0;
	while ( (item = [itemEnum nextObject]) != nil )
		_size += [item sizeValue];
}

- (NSSet*) items
{
	return _items;
}

- (NSEnumerator*) itemEnumerator
{
	return [_items objectEnumerator];
}

//compare the size descendingly
- (NSComparisonResult) compareSizeDescendingly: (FileKindStatistic*) other
{
	UInt64 mySize = [self size];
	UInt64 otherSize = [other size];
	
	//we want the sorting to be descending
	if ( mySize < otherSize )
		return NSOrderedDescending;
	if ( mySize > otherSize )
		return NSOrderedAscending;
	
	//if both object have the same size, order by their names
	return [[self kindName] compare: [other kindName] options: NSNumericSearch];
}

@end

//============ interface FileSystemDoc(Private) ==========================================================

//the scan helpers live in the main @implementation, so they are declared here
//rather than in the (Private) category below
@interface FileSystemDoc()
+ (dispatch_queue_t) _scanQueue;
+ (NSUInteger) _estimatedItemCountForURL: (NSURL*) url;
+ (void) _rememberItemCount: (NSUInteger) count forURL: (NSURL*) url;
- (NSException*) _runScanBlockOffMainThread: (void (^)(void)) work estimatingFrom: (NSURL*) rootURL;
- (void) _setScanCurrentPath: (NSString*) path;
- (NSString*) _takeScanCurrentPath;
- (BOOL) _scanWasCancelled;
- (void) _cancelScan;
- (void) _beginScan;

- (void) _recalculateBasketSize;
- (void) _pruneReclaimBasket;
- (void) _resolveChangeFilter;
- (void) _recountItemsIfNeeded;
- (void) _countItemsUnder: (FSItem*) item files: (NSUInteger*) files folders: (NSUInteger*) folders;
- (void) _invalidateItemCounts;

- (FSItemIndex*) _searchIndexBuildingIfNeeded;
- (void) _dropSearchIndex;
- (void) _runSearch;
@end

@interface FileSystemDoc(Private)

- (void) addItemToFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds;
- (void) removeItemFromFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds;
- (void) recalculateFileKindStatisticSizes;
- (void) removePackagesFromFileKindStatistic: (FSItem*) item;
- (void) addPackagesToFileKindStatistic: (FSItem*) item; 	
- (void) removeEmptyKindStatistics;

- (void)checkForProtectedFolders:(NSString * _Nonnull)folder;

- (void) reserveColorsForLargestKinds;

- (void) recalculateTotalSize;

- (NSMutableDictionary*) viewOptions;

- (void) postViewOptionChangedNotificationForOption: (NSString*) optionName;
- (void) postNotificationName: (NSString*) name oldItem: (FSItem*) old newItem:  (FSItem*) new;

@end

//=========== implementation FileSystemDoc ==========================================================

/* keys for Key Value Observing (KVO) */
NSString *DocKeySelectedItem = @"selectedItem";

/* FileSystemDoc Notifications */
NSString *GlobalSelectionChangedNotification = @"GlobalSelectionChanged";
NSString *ZoomedItemChangedNotification = @"ZoomedItemChanged";
NSString *FSItemsChangedNotification = @"FSItemsChanged";
NSString *ViewOptionChangedNotification = @"ViewOptionsChangedNotification";
NSString *ChangedViewOption = @"ChangedViewOption";
NSString *NewItem = @"NewItem";
NSString *OldItem = @"OldItem";
NSString *ReclaimBasketChangedNotification = @"ReclaimBasketChanged";
NSString *FocusedPileChangedNotification = @"FocusedPileChanged";
NSString *SearchResultsChangedNotification = @"SearchResultsChanged";
NSString *DIXKindFilterOption = @"DIXKindFilter";
NSString *DIXViewModeOption = @"DIXViewMode";
NSString *DIXChangeFilterOption = @"DIXChangeFilter";

@implementation FileSystemDoc

- (id)init
{
    self = [super init];
    if ( self != nil )
    {
        // Add your subclass-specific initialization here.
        // If an error occurs here, send a [self release] message and return nil.
		
        _zoomStack = [[NSMutableArray alloc] init];

		_viewOptions = [[NSMutableDictionary alloc] initWithDefaults];

		_basketItems = [[NSMutableSet alloc] init];

		//Map until the window controller has a width to judge by; it promotes
		//this to Both once it knows the content is wide enough.
		_viewMode = DIXViewModeMap;

		NSUserDefaultsController *sharedDefsController = [NSUserDefaultsController sharedUserDefaultsController];
		[sharedDefsController addObserver: self
							   forKeyPath: [@"values." stringByAppendingString: ShareKindColors]
								  options: 0
								  context: (__bridge void*) ShareKindColors];		
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];        
	
	NSUserDefaultsController *sharedDefsController = [NSUserDefaultsController sharedUserDefaultsController];
	[sharedDefsController removeObserver: self forKeyPath: [@"values." stringByAppendingString: ShareKindColors]];
	
	
	

	
}

- (void) makeWindowControllers
{
    // Override method to instantiate controllers for multiple document windows.
    MainWindowController *controller = [[MainWindowController alloc] initWithWindowNibName: [self windowNibName]];
    [self addWindowController:controller];
}


- (NSString *)windowNibName
{
    // Override returning the nib file name of the document
    // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    return @"TreeMap";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
    // Add any code here that needs to be executed once the windowController has loaded the document's window.
}

- (BOOL) readFromFile: (NSString *) folder ofType: (NSString *) docType
{
    [self checkForProtectedFolders:folder];
    
    //now the real work: loading the folder contents
    @try
    {
        g_fileCount = g_folderCount = 0;
        
		_progressController = [[LoadingPanelController alloc] init];
		
		uint64_t startTime = getTime();
		
        _rootItem = [[FSItem alloc] initWithPath: folder];
		if ( ![[_rootItem fileURL] stillExists] )
		{
			_rootItem = nil;
			_progressController = nil;
			LOG( @"readFromFile: path '%@' doesn't exits", folder );
			return NO;
		}
		
		[_rootItem setDelegate: self];

		//Only the walk goes on the queue. The statistics pass stays on the main
		//thread: it posts KVO for "kindStatistics", which bound controls in any
		//open document observe, and -reserveColorsForLargestKinds mutates the
		//FileTypeColors singleton those documents read while drawing. It is a
		//second traversal of a tree already in memory, so it costs a fraction of
		//the walk it follows.
		FSItem *rootItem = _rootItem;
		NSException *scanException = [self _runScanBlockOffMainThread: ^{
			[rootItem loadChildren];
		} estimatingFrom: [rootItem fileURL]];

		//what this path really holds, for the next scan of it to divide by
		[[self class] _rememberItemCount: g_fileCount + g_folderCount forURL: [rootItem fileURL]];

		if ( scanException != nil )
			[scanException raise];
        
 		uint64_t doneLoadingTime = getTime();
		LOG (@"loading time:  %.2f seconds", subtractTime(doneLoadingTime, startTime));
		
        LOG(@"************** Loading complete *******************" );
        LOG(@"%u items created", g_fileCount + g_folderCount );
        LOG(@"%u files", g_fileCount );
        LOG(@"%u folders", g_folderCount );
        
		//ok, now we've got an FSItem for every file and directory in the given folder
		//[_progressController setMessageText: NSLocalizedString( @"Classifying Files", @"")];
				
		//collect sizes and file count of all file kinds
		[self refreshFileKindStatistics];

		uint64_t doneFileKindStatsTime = getTime();
		LOG (@"file kind statistics time:  %.2f seconds", subtractTime(doneFileKindStatsTime, doneLoadingTime));

		//"scanned 2 minutes ago" in the summary strip is measured from here -
		//when the tree is complete, not when the walk was started
		_scanCompletedAt = [NSDate date];

		//Read before the record below overwrites it: what this same folder came
		//to last time is the whole of the summary strip's "+2.81 GB since 8 Aug".
		DIXRecentScan *previous = [[DIXRecentScans sharedList] scanForURL: [rootItem fileURL]];

		_previousScanSize = [previous size];
		_previousScanDate = [previous scannedAt];

		//What changed, worked out against the last snapshot before this scan
		//overwrites it. Held on the document because the window is not built yet.
		_changesSinceLastScan = [[DIXScanHistory sharedHistory] changesForItem: rootItem];

		[[DIXScanHistory sharedHistory] recordSnapshotForItem: rootItem];

		//What the sidebar offers as somewhere you have already been. Recorded
		//here rather than when the document opened, because only now is there a
		//total to show beside it.
		[[DIXRecentScans sharedList] recordScanOfURL: [rootItem fileURL]
												size: [[rootItem size] unsignedLongLongValue]];
		[self _invalidateItemCounts];
		
		//the modal session must be ended in the same NS_DURING section (if no exception occured)
		_progressController = nil;
    }
    @catch(NSException *localException)
    {
        LOG( @"exception '%@' occured during directory traversal: %@", [localException name], [localException reason] );
		
		// according to the docu, we should not end a modal session explicitly in the case of an exception
        // but this seems to be no longer true at least on Mac OS 10.13 (even not when using NS_DURING, NS_HANDLER, ..)
		//[_progressController closeNoModalEnd];
		_progressController = nil;
		
		_rootItem = nil;

		if ( [[localException name] isEqualToString: FSItemLoadingCanceledException]
			 || [[localException name] isEqualToString: CollectFileKindStatisticsCanceledException] )
		{
			//loading canceled by user
		}
		else
		{
			//error
			NSRunInformationalAlertPanel( NSLocalizedString( @"The folder's content could not be loaded.", @""), @"%@", nil, nil, nil, [localException reason]);
		}
		
        return NO;
    }
        
   return YES;
}

- (IBAction) cancelScanningFolder:(id)sender
{
	[[NSApplication sharedApplication] stopModal];
}

- (BOOL) showPhysicalFileSize;
{
    return [[self viewOptions] showPhysicalFileSize];
}

- (void) setShowPhysicalFileSize: (BOOL) show
{
	[[self viewOptions] setShowPhysicalFileSize: show];
	
	[self recalculateTotalSize];
	[self recalculateFileKindStatisticSizes];
	
	[self postViewOptionChangedNotificationForOption: ShowPhysicalFileSize];
}

- (BOOL) showPackageContents
{
    return [[self viewOptions] showPackageContents];
}

- (void) setShowPackageContents: (BOOL) show
{
    show = (show == 0) ? NO : YES;
    if ( show == [[self viewOptions] showPackageContents] )
		return;
    
	// update kind statistics to reflect the chnage in view
    {
        //remove all packages from kind statistic as they are now regarded differently (file<->folder)
        //[self removePackagesFromFileKindStatistic: nil];
        
        [[self viewOptions] setShowPackageContents: show];

        // the methods "removePackagesFromFileKindStatistic" (was called above) and "addPackagesToFileKindStatistic" (was called below)
        // do not work correctly in all cases
        // so for now, we just rebuild the whole statictics which takes more time, but works
        [self refreshFileKindStatistics];

        //re-add packages to statistic
        //[self addPackagesToFileKindStatistic: nil];
    }
    
    FSItem* selectedItem = [self selectedItem];
	
	//invalidate current selection, as the selection might be an item in a package
	//(if "show package content" is turned off, files in packages aren't visible any more)
	if ( ![self showPackageContents] && selectedItem != nil )
		[self setSelectedItem: nil];
	
	[self postViewOptionChangedNotificationForOption: ShowPackageContents];
	
	//if "show package contents" is turned off, check if selection is within a package
	//(as the selection got invalid)
	if ( ![self showPackageContents] && selectedItem != nil)
	{
		//select it's farest parent which is a package
		FSItem *packageItem = nil;
		FSItem *parentItem = [selectedItem parent];
		while ( parentItem != nil && parentItem != [self zoomedItem] )
		{
			if ( [parentItem isPackage] )
				packageItem = parentItem;
			parentItem = [parentItem parent];
		}
		
		selectedItem = packageItem;
	}
	
	//restore selection
	if ( ![self showPackageContents] && selectedItem != nil )
		[self setSelectedItem: selectedItem];
}

- (BOOL) showFreeSpace
{
    return [[self viewOptions] showFreeSpace];
}

- (void) setShowFreeSpace: (BOOL) show
{
	[[self viewOptions] setShowFreeSpace: show];
	
	[self postViewOptionChangedNotificationForOption: ShowFreeSpace];
}

- (BOOL) showOtherSpace
{
    return [[self viewOptions] showOtherSpace];
}

- (void) setShowOtherSpace: (BOOL) show
{
	[[self viewOptions] setShowOtherSpace: show];
	
	[self postViewOptionChangedNotificationForOption: ShowOtherSpace];
}

- (BOOL) ignoreCreatorCode
{
	return [[self viewOptions] ignoreCreatorCode];
}

- (void) setIgnoreCreatorCode: (BOOL) ignoreIt
{
    /*
	[[self viewOptions] setIgnoreCreatorCode: ignoreIt];
	
	[[self rootItem] setKindStringIgnoringCreatorCode: ignoreIt includeChilds: YES];
	
	[self refreshFileKindStatistics];
	
	[self postViewOptionChangedNotificationForOption: IgnoreCreatorCode];
     */
}

//helper method; returns YES/NO for packages in dependency of the showPackageContents-Flag
- (BOOL) itemIsNode: (FSItem*) item
{
    //the zoomed item is always a node, even if it is a package and "show package contents" is turned off
    //(you can always zoom into packages)
    if ( item == [self zoomedItem] )
        return YES;
    
    if ( [self showPackageContents] )
        return [item isFolder];
    else
        return [item isFolder] && ![item isPackage];
}

- (FSItem*) rootItem;
{
    return _rootItem;
}

- (BOOL) moveItemToTrash: (FSItem*) item error:(NSError **)error
{
	NSParameterAssert( item != nil && item != [self zoomedItem] && ![item isSpecialItem] );
	
	// file moved to trash (it's new URL)
    NSURL *newFileInTrash = nil;
    // FSItem representing the trash folder
    FSItem *trashItem = nil;

	//As the trash visible to the user only shows trashed files/folders on local volumes,
	//we delete files/folders on network volumes (like the Finder does).
	//If we would perform a NSWorkspaceRecycleOperation on a file/folder residing on a network volume,
	//it would be moved to .Trashes/.<user-id> on that volume.
	
	if ( [[item fileURL] isLocalVolume] )
	{
        NSFileManager *fm = [NSFileManager defaultManager];
        
        NSURL *trashURL = [fm URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:[item fileURL] create:NO error:nil];
        
        if ( trashURL != nil )
            trashItem = [[self rootItem] findItemByAbsolutePath: [trashURL path] allowAncestors: NO];
        
        // move file/folder to trash
        if ( ![fm trashItemAtURL:[item fileURL] resultingItemURL:&newFileInTrash error:error] )
            return NO;
	}
	else
    {
        // delete file
        if ( ![[NSFileManager defaultManager] removeItemAtURL:[item fileURL] error: error] )
               return NO;
    }
	
	//if the selected item should be removed, invalidate our selection
	if ( [self selectedItem] == item )
		[self setSelectedItem: nil];
    
    // keep data model in sync: remove from folder item, add to trash item, update file kind statistic
	
	// remove the item from the parent's list
	FSItem *parent = [item parent];
	NSAssert( parent != nil, @"root item shouldn't be deletable" );
	
	//retain and autorelease "item", so it will be accessible till all is done
	
	[parent removeChild: item updateParent: YES];
	
	//keep kind statistic in sync
	[self willChangeValueForKey: @"kindStatistics"];
	[self removeItemFromFileKindStatistic: item includingChilds: YES];
	
	//the users's trash may have been created with the trash operation (if item is not on the same volume as the user's home)
	//in this case, we won't see the trashed item, as we are not showing the trash folder currently 
	if ( trashItem != nil && newFileInTrash != nil )
    {
        //keep the size of "itemTrashed", but associate with the valid URL
        [item setFileURL: newFileInTrash];

        [trashItem insertChild: item updateParent: YES];
        
        //keep kind statistic in sync
        [self addItemToFileKindStatistic: item includingChilds: YES];
    }
    
	//"checkTrash" may have editied the kind statistic, so notify observers but now
	[self didChangeValueForKey: @"kindStatistics"];

	//the item just trashed may have been ticked for reclaiming
	[self _pruneReclaimBasket];
	[self _resolveChangeFilter];
	[self _invalidateItemCounts];

	//notify observers of the change
	[[NSNotificationCenter defaultCenter] postNotificationName: FSItemsChangedNotification object: self];
	
	//try to set "parent" as new selection
	if ( parent != [self zoomedItem] )
		[self setSelectedItem: parent];
	
	return YES;
}

- (void) refreshItem: (FSItem*) item
{
	//refresh zoomed item?
	if ( item == nil )
		item = [self zoomedItem];
	
	//remember selection
	NSString *selectedItemPath = nil;
	if ( [self selectedItem] != nil ) 
	{
		selectedItemPath = [[self selectedItem] path];
		[self setSelectedItem: nil];
	}
	
	//refresh item or one of it's ancestors (whichever is still valid)
	BOOL zoomedItemIsInvalid = NO;
	while ( item != nil && ![item exists] )
	{
		if ( item == [self zoomedItem] )
			zoomedItemIsInvalid = YES;
		
		item = [item parent];
	}
	
	if ( item == nil )
	{
		//the folder/volume which we are showing doesn't exist anymore!
        NSString *msg = [NSString stringWithFormat: @"\"%@\" does not exist any more.", [[self rootItem] displayPath]];
        NSString *subMsg = NSLocalizedString( @"The folder will remain visible in Disk Inventory Next, but the files cannot be accessed (e.g. shown in the Finder).",@"");
        
        [NSAlert showInformationalSheetWithMessage: msg
                                       explanation: subMsg
                                         forWindow: [[[self windowControllers] objectAtIndex: 0] window]];

		return;
	}
	
	FSItem *refreshedItem = nil;
	
	NS_DURING
		//we only show a progress indicator if the item to refresh has "many" childs
		//(of course this could have changed since the loading, but what criteria should
		//we use instead?)
		NSAssert( _progressController == nil, @"progress panel wasn't destroyed after last use" );
		unsigned progressPanelLimit = ![[item fileURL] isLocalVolume] ? 200 : 500;
		if ( [item deepFileCountIncludingPackages: YES] > progressPanelLimit )
		{
			//NSWindow *window = [[[self windowControllers] objectAtIndex: 0] window];
			_progressController = [[LoadingPanelController alloc] init];
		}
		
		refreshedItem = [[FSItem alloc] initWithPath: [item path]];
		[refreshedItem setDelegate: self];
		if ( [refreshedItem isFolder] )
		{
			//Only worth a queue when there is a panel to keep alive; without one
			//there is nothing for the main thread to do while it waits, and a
			//small refresh finishes before a queue hop would have paid for
			//itself.
			if ( _progressController != nil )
			{
				FSItem *itemToLoad = refreshedItem;
				NSException *scanException = [self _runScanBlockOffMainThread: ^{
					[itemToLoad loadChildren];
				} estimatingFrom: [itemToLoad fileURL]];

				if ( scanException != nil )
					[scanException raise];
			}
			else
				[refreshedItem loadChildren];
		}
		
		_progressController = nil;
	NS_HANDLER
		[_progressController closeNoModalEnd];
		_progressController = nil;
		
		if ( [[localException name] isEqualToString: FSItemLoadingCanceledException]
			 || [[localException name] isEqualToString: CollectFileKindStatisticsCanceledException] )
		{
			//refreshing canceled by user
		}
		else
		{
			//error
            [NSAlert showInformationalSheetWithMessage: NSLocalizedString( @"The folder's content could not be loaded.", @"")
                                          explanation: [localException reason]
                                            forWindow: [[[self windowControllers] objectAtIndex: 0] window]];

		}
		NS_VOIDRETURN;
	NS_ENDHANDLER
	
	//keep item valid till we are done
	
	if ( _rootItem == item )
	{
		_rootItem = refreshedItem;
		//rebuild file kind statistics
		[self refreshFileKindStatistics];
	}
	else
	{
		//update file kind statistics
		if ( !zoomedItemIsInvalid )
			[self willChangeValueForKey: @"kindStatistics"];
		
		[self removeItemFromFileKindStatistic: item includingChilds: YES];
		
		FSItem *parent = [item parent];
		[parent replaceChild: item withItem: refreshedItem updateParent: YES];
		
		[self addItemToFileKindStatistic: refreshedItem includingChilds: YES];
		
		if ( !zoomedItemIsInvalid )
			[self didChangeValueForKey: @"kindStatistics"];
	}
	
	//if current zoomed item got invalid, zoom out as far as necessary
	if ( zoomedItemIsInvalid )
	{
		FSItem *newZoomItem = item;
		//zoom to an ancestor of "item" which is in the zoom stack
		while ( [_zoomStack indexOfObjectIdenticalTo: newZoomItem] == NSNotFound && newZoomItem != nil )
			newZoomItem = [newZoomItem parent];

		//will posts a notification about the change
		[self zoomOutToItem: newZoomItem];
	}
	else
	{
		if ( [_zoomStack lastObject] == item )
			[_zoomStack replaceObjectAtIndex: ([_zoomStack count]-1) withObject: refreshedItem];

		//a refresh replaces FSItems wholesale, so anything in the basket that
		//has gone from disk has to drop out before the change is announced -
		//and the change filter's items have to be found again
		[self _pruneReclaimBasket];
		[self _resolveChangeFilter];
		[self _invalidateItemCounts];

		//notify observers of the change
		[[NSNotificationCenter defaultCenter] postNotificationName: FSItemsChangedNotification object: self];
	}

	//set selection
	if ( selectedItemPath != nil )
	{
		//find previously select item or one of it's ancestors (whichever still exists)
		FSItem *zoomedItem = [self zoomedItem];
		
		FSItem *newSelection = [zoomedItem findItemByAbsolutePath: selectedItemPath allowAncestors: YES];
				
		if ( newSelection != nil && newSelection != zoomedItem )
			[self setSelectedItem: newSelection];
	}
}

- (FSItem*) zoomedItem
{
    return [_zoomStack count] == 0 ? [self rootItem] : [_zoomStack lastObject];
}

- (void) zoomIntoItem: (FSItem*) item
{
    if ( [_zoomStack count] > 0 && item == [_zoomStack lastObject] )
        return;

	//zooming replaces what the map shows, so a pile focus does not survive it
	_focusedPile = nil;

	FSItem *oldZoomedItem = [self zoomedItem];
    
    //reset selection as the currently selected item might not be a child of the item to zoom in
    //
    //Selecting the item zoomed into instead - symmetric with -zoomOutOneStep,
    //which does re-select what it came from - looks tempting and raises
    //NSInternalInconsistencyException "the given item is no ancestor of self"
    //from -[FSItem(Utilities) fsItemPathFromAncestor:], by way of
    //-[TreeMapViewController onDocumentSelectionChanged]: after the zoom that
    //item *is* the root, so there is no path from the root down to it. Clearing
    //the selection here is load-bearing.
    [self setSelectedItem: nil];

    [_zoomStack addObject: item];
    
    //the file kind statistic should only cover the currently visible part of the file system tree
    //(this depends on the zoomed item and whether package contents is shown or not)
    [self refreshFileKindStatistics];

    [self postNotificationName: ZoomedItemChangedNotification oldItem: oldZoomedItem newItem: [self zoomedItem]];
}

#pragma mark --------searching the scan-----------------

- (NSString*) searchString
{
	return _searchString;
}

//Name, not All, when nothing has been chosen.
//
//The old search field defaulted to All and was right to: it searched one kind's
//items, a few thousand at most. Over a whole scan the path index is the
//expensive one - it holds a distinct long string per item where names repeat, so
//a query scans every path in the tree. Measured over /System/Library's 435,501
//items: 16 ms by name against 285 ms by path, per keystroke. Path is a keystroke
//away in the menu and worth waiting for when asked for; it is not worth making
//every search pay for.
- (FSItemIndexType) searchScope
{
	return _searchScope != 0 ? _searchScope : FSItemIndexName;
}

- (NSArray<FSItem*>*) searchResults
{
	return _searchResults;
}

- (void) setSearchString: (NSString*) searchString
{
	//trimmed, so that a field holding only spaces is not "searching"
	NSString *trimmed = [searchString stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if ( [trimmed length] == 0 )
		trimmed = nil;

	if ( trimmed == _searchString || [trimmed isEqualToString: _searchString] )
		return;

	_searchString = [trimmed copy];

	[self _runSearch];
}

- (void) setSearchScope: (FSItemIndexType) scope
{
	if ( scope == _searchScope )
		return;

	_searchScope = scope;

	if ( _searchString != nil )
		[self _runSearch];
}

//Kept until the tree changes: building it over /usr/share's 20,000 items is not
//free, and a search field is typed into one character at a time.
//
//The items come from a walk of the tree rather than from the kind statistics,
//which would have been the shorter way to a list of everything. Two reasons, and
//both are visible to whoever is typing: the statistics hold **files only**, so a
//folder could never be found by name; and they are built from the *zoomed* item,
//so what they cover shrinks as you zoom in, while the field says "this scan".
//
//The kind index still comes from the statistics, since that is what they are.
//That one does follow the zoom - searching by kind while zoomed in searches what
//is on screen. Name and path do not.
- (FSItemIndex*) _searchIndexBuildingIfNeeded
{
	if ( _searchIndex != nil )
		return _searchIndex;

	FSItem *root = [self rootItem];

	if ( root == nil )
		return nil;

	FSItemIndex *index = [[FSItemIndex alloc] initWithKindStatistics: [self kindStatistics]];

	NSMutableArray<FSItem*> *everything = [NSMutableArray array];
	NSMutableArray<FSItem*> *stack = [NSMutableArray arrayWithObject: root];

	while ( [stack count] > 0 )
	{
		FSItem *item = [stack lastObject];

		[stack removeLastObject];

		//the two synthetic cells are not files and have nothing to find
		if ( item != root && ![item isSpecialItem] )
			[everything addObject: item];

		NSUInteger i = [item childCount];

		while ( i-- )
			[stack addObject: [item childAtIndex: i]];
	}

	[index addItemsFromArray: everything];

	_searchIndex = index;

	return index;
}

- (void) _dropSearchIndex
{
	_searchIndex = nil;

	if ( _searchString != nil )
		[self _runSearch];
}

- (void) _runSearch
{
	if ( _searchString == nil )
	{
		_searchResults = nil;
	}
	else
	{
		FSItemIndex *index = [self _searchIndexBuildingIfNeeded];

		//An empty array rather than nil: "searched, found nothing" is a result,
		//and the list has to be able to say so.
		_searchResults = ( index != nil )
			? [index searchItems: _searchString inIndex: [self searchScope]]
			: @[];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName: SearchResultsChangedNotification
														object: self];
}

#pragma mark --------the focused pile-----------------

- (NSArray<FSItem*>*) focusedPile
{
	return _focusedPile;
}

- (void) setFocusedPile: (NSArray<FSItem*>*) items
{
	if ( items == _focusedPile || [items isEqualToArray: _focusedPile] )
		return;

	_focusedPile = [items count] > 0 ? [items copy] : nil;

	//The selection is very likely no longer on screen: the map is about to show
	//a different set of items. Cleared for the same reason -zoomIntoItem: clears
	//it, and with the same consequence if it is not - the treemap controller
	//asks for a path from the root down to the selection and there is none.
	[self setSelectedItem: nil];

	[[NSNotificationCenter defaultCenter] postNotificationName: FocusedPileChangedNotification
														object: self];
}

- (void) zoomOutOneStep
{
    if ( [_zoomStack count] > 0 )
    {
		FSItem *oldZoomedItem = [self zoomedItem];

		_focusedPile = nil;

        [_zoomStack removeLastObject];
        
        //the file kind statistic should only cover the currently visible part of the file system tree
        //(this depends on the zoomed item and whether package contents is shown or not)
        [self refreshFileKindStatistics];
		
		//there is no "other" space if a complete volume is shown 
		if ( [[self viewOptions] showOtherSpace] && [[[self zoomedItem] fileURL] isVolume] )
			[[self viewOptions] setShowOtherSpace: NO]; //don't use our set-method as we don't want any notifications posted

		[self postNotificationName: ZoomedItemChangedNotification oldItem: oldZoomedItem newItem: [self zoomedItem]];
    }
}

- (void) zoomOutToItem: (FSItem*) item
{
    NSAssert( [_zoomStack count] > 0, @"can't zoom out if zoom stack is empty" );
    
    NSParameterAssert( item == nil
                       || item == [self rootItem]
                       || [_zoomStack indexOfObjectIdenticalTo: item] != NSNotFound );
    
	FSItem *oldZoomedItem = [self zoomedItem];
	
    if ( item == nil || item == [self rootItem] )
    {
        [_zoomStack removeAllObjects];
    }
    else if ( [_zoomStack count] == 1 )
    {
        NSAssert( item == [_zoomStack lastObject], @"zoom error");
        [_zoomStack removeAllObjects];
    }
    else
    {
        NSUInteger itemIndex = [_zoomStack indexOfObjectIdenticalTo: item];
        if ( itemIndex != NSNotFound )
        {
            NSUInteger itemsToRemove = [_zoomStack count] - itemIndex - 1;
            for ( ; itemsToRemove > 0; itemsToRemove-- )
                [_zoomStack removeLastObject];
        }
        
    }
    
    //the file kind statistic should only cover the currently visible part of the file system tree
    //(this depends on the zoomed item and whether package contents is shown or not)
    [self refreshFileKindStatistics];

	//there is no "other" space if a complete volume is shown 
	if ( [[self viewOptions] showOtherSpace] && [[[self zoomedItem] fileURL] isVolume] )
		[[self viewOptions] setShowOtherSpace: NO]; //don't use our set-method as we don't want any notifications posted

	[self postNotificationName: ZoomedItemChangedNotification oldItem: oldZoomedItem newItem: [self zoomedItem]];
}

- (NSArray*) zoomStack
{
	return _zoomStack;
}

- (FSItem*) selectedItem
{
    return _selectedItem;
}

- (void) setSelectedItem: (FSItem*) item
{
    if ( _selectedItem == item )
        return;

	FSItem *oldSelectedItem = _selectedItem;
    
	_selectedItem = item;
		
    //post notification
	//
	//The document used to push the new selection at the floating Info window from
	//here, which was the one place a view was driven rather than notified. The
	//inspector reads the notification like every other view.
	[self postNotificationName: GlobalSelectionChangedNotification oldItem: oldSelectedItem newItem: _selectedItem];
}

#pragma mark --------what the summary strip reports-----------------

- (NSDate*) scanCompletedAt
{
	return _scanCompletedAt;
}

- (NSUInteger) fileCount
{
	[self _recountItemsIfNeeded];
	return _fileCount;
}

- (NSUInteger) folderCount
{
	[self _recountItemsIfNeeded];
	return _folderCount;
}

//Walks the tree the first time either count is asked for after a change. That
//is one traversal of something already in memory - over /usr/share, 20,179
//items, it is a rounding error next to the scan that built it - and it stays
//right after a refresh or a trash, which a figure snapshotted at scan time
//would not.
- (void) _recountItemsIfNeeded
{
	if ( _countsAreValid )
		return;

	NSUInteger files = 0, folders = 0;

	[self _countItemsUnder: _rootItem files: &files folders: &folders];

	_fileCount = files;
	_folderCount = folders;
	_countsAreValid = YES;
}

- (void) _countItemsUnder: (FSItem*) item files: (NSUInteger*) files folders: (NSUInteger*) folders
{
	if ( item == nil || [item isSpecialItem] )
		return;

	//The root is the folder being looked at, not something inside it, so it is
	//counted like any other folder - which is what makes the two figures add up
	//to the item count the progress estimate remembers.
	if ( [item isFolder] )
		(*folders)++;
	else
		(*files)++;

	for ( NSUInteger i = 0; i < [item childCount]; i++ )
		[self _countItemsUnder: [item childAtIndex: i] files: files folders: folders];
}

- (void) _invalidateItemCounts
{
	_countsAreValid = NO;
}

#pragma mark --------the kind filter-----------------

- (NSString*) kindFilter
{
	return _kindFilter;
}

- (void) setKindFilter: (NSString*) kindName
{
	if ( _kindFilter == kindName || [_kindFilter isEqualToString: kindName] )
		return;

	_kindFilter = [kindName copy];

	//A selection that the filter now hides would leave the inspector describing
	//something the user cannot see.
	if ( _selectedItem != nil && ![self itemPassesKindFilter: _selectedItem] )
		[self setSelectedItem: nil];

	[self postViewOptionChangedNotificationForOption: DIXKindFilterOption];
}

- (BOOL) itemPassesKindFilter: (FSItem*) item
{
	if ( _kindFilter == nil || item == nil )
		return YES;

	//Free and other space are not file kinds. Filtering them out would quietly
	//change what the map's total stands for, which is the one number the whole
	//window is built around.
	if ( [item isSpecialItem] )
		return YES;

	//A folder passes when anything inside it does, or the filter would empty
	//every branch and leave the map blank.
	if ( [self itemIsNode: item] )
		return YES;

	return [[item kindName] isEqualToString: _kindFilter];
}

#pragma mark --------the reclaim basket-----------------

- (NSSet<FSItem*>*) basketItems
{
	return ( _basketItems != nil ) ? [_basketItems copy] : [NSSet set];
}

- (BOOL) isItemInBasket: (FSItem*) item
{
	return item != nil && [_basketItems containsObject: item];
}

- (void) toggleBasketItem: (FSItem*) item
{
	if ( item == nil || [item isSpecialItem] )
		return;

	if ( _basketItems == nil )
		_basketItems = [[NSMutableSet alloc] init];

	if ( [_basketItems containsObject: item] )
		[_basketItems removeObject: item];
	else
		[_basketItems addObject: item];

	[self _recalculateBasketSize];

	[[NSNotificationCenter defaultCenter] postNotificationName: ReclaimBasketChangedNotification
														object: self];
}

//Used by the change view's "Review ..." button, which fills the basket in one
//go rather than a notification per row.
- (void) addItemsToBasket: (NSArray<FSItem*>*) items
{
	if ( [items count] == 0 )
		return;

	if ( _basketItems == nil )
		_basketItems = [[NSMutableSet alloc] init];

	for ( FSItem *item in items )
	{
		if ( ![item isSpecialItem] )
			[_basketItems addObject: item];
	}

	[self _recalculateBasketSize];

	[[NSNotificationCenter defaultCenter] postNotificationName: ReclaimBasketChangedNotification
														object: self];
}

- (void) clearBasket
{
	if ( [_basketItems count] == 0 )
		return;

	[_basketItems removeAllObjects];
	_basketSize = 0;

	[[NSNotificationCenter defaultCenter] postNotificationName: ReclaimBasketChangedNotification
														object: self];
}

- (NSUInteger) basketCount
{
	return [_basketItems count];
}

- (unsigned long long) basketSize
{
	return _basketSize;
}

- (void) _recalculateBasketSize
{
	//Summed rather than accumulated: an item's size can change under us when a
	//folder in the basket is refreshed, and a running total would drift.
	unsigned long long total = 0;

	for ( FSItem *item in _basketItems )
		total += [item sizeValue];

	_basketSize = total;
}

//Called wherever the tree is mutated, before the change is announced. An item
//that has been trashed or has gone with an ejected volume must not keep
//contributing to the reclaim total - and must not be handed to -moveItemToTrash:
//a second time.
- (void) _pruneReclaimBasket
{
	if ( [_basketItems count] == 0 )
		return;

	NSMutableSet<FSItem*> *gone = [NSMutableSet set];

	for ( FSItem *item in _basketItems )
	{
		if ( ![[item fileURL] stillExists] )
			[gone addObject: item];
	}

	if ( [gone count] == 0 )
	{
		//sizes may still have moved even when the membership has not
		[self _recalculateBasketSize];
		return;
	}

	[_basketItems minusSet: gone];
	[self _recalculateBasketSize];

	[[NSNotificationCenter defaultCenter] postNotificationName: ReclaimBasketChangedNotification
														object: self];
}

#pragma mark --------the view mode-----------------

- (NSArray<DIXScanChange*>*) changesSinceLastScan
{
	return _changesSinceLastScan;
}

- (unsigned long long) previousScanSize
{
	return _previousScanSize;
}

- (NSDate*) previousScanDate
{
	return _previousScanDate;
}

- (FSItem*) itemAtPath: (NSString*) path
{
	NSString *rootPath = [_rootItem path];

	if ( _rootItem == nil || [path length] == 0 || ![path hasPrefix: rootPath] )
		return nil;

	if ( [path isEqualToString: rootPath] )
		return _rootItem;

	//The remainder, split into names. A scan root of "/" ends in a slash and
	//every other one does not, so the prefix is trimmed by length and the
	//leading separator dropped by the empty-component skip below.
	NSArray<NSString*> *names = [[path substringFromIndex: [rootPath length]]
									 pathComponents];
	FSItem *item = _rootItem;

	for ( NSString *name in names )
	{
		if ( [name length] == 0 || [name isEqualToString: @"/"] )
			continue;

		FSItem *match = nil;

		for ( NSUInteger i = 0; i < [item childCount] && match == nil; i++ )
		{
			FSItem *child = [item childAtIndex: i];

			if ( [[child name] isEqualToString: name] )
				match = child;
		}

		if ( match == nil )
			return nil;

		item = match;
	}

	return item;
}

#pragma mark --------the change filter-----------------

- (BOOL) showsOnlyChanges
{
	return _showsOnlyChanges;
}

- (void) setShowsOnlyChanges: (BOOL) showsOnlyChanges
{
	if ( _showsOnlyChanges == showsOnlyChanges )
		return;

	_showsOnlyChanges = showsOnlyChanges;

	[self _resolveChangeFilter];
	[self postViewOptionChangedNotificationForOption: DIXChangeFilterOption];
}

//Run again whenever the tree changes, because a refresh replaces FSItems
//wholesale and trashing one removes it: the paths in the change list outlive
//both, and the resolved items do not. Re-resolving rather than dropping the
//filter is what lets it survive the trashing that reviewing a change leads to.
- (void) _resolveChangeFilter
{
	if ( !_showsOnlyChanges )
	{
		_changedItems = nil;
		_changeAncestors = nil;
		return;
	}

	NSMutableSet<FSItem*> *changed = [NSMutableSet set];
	NSMutableSet<FSItem*> *ancestors = [NSMutableSet set];

	for ( DIXScanChange *change in _changesSinceLastScan )
	{
		FSItem *item = [self itemAtPath: [change path]];

		//Something that shrank to nothing has no item left to point at. It is
		//still worth saying in the list, and there is nothing to light up.
		if ( item == nil )
			continue;

		[changed addObject: item];

		for ( FSItem *walk = [item parent]; walk != nil; walk = [walk parent] )
			[ancestors addObject: walk];
	}

	_changedItems = changed;
	_changeAncestors = ancestors;
}

- (BOOL) itemPassesChangeFilter: (FSItem*) item
{
	if ( !_showsOnlyChanges || item == nil )
		return YES;

	//Free and other space are not part of any change, and dimming them would
	//quietly change what the map's total stands for - the same reasoning as the
	//kind filter's.
	if ( [item isSpecialItem] )
		return YES;

	//a folder on the way down to something that changed
	if ( [_changeAncestors containsObject: item] )
		return YES;

	//or the thing itself, or anything inside it
	for ( FSItem *walk = item; walk != nil; walk = [walk parent] )
		if ( [_changedItems containsObject: walk] )
			return YES;

	return NO;
}

- (DIXViewMode) viewMode
{
	return _viewMode;
}

- (void) setViewMode: (DIXViewMode) mode
{
	if ( _viewMode == mode )
		return;

	_viewMode = mode;

	[self postViewOptionChangedNotificationForOption: DIXViewModeOption];
}

- (NSString *)fileName
{
    //we should override this method so the window controller will display
    //the icon of the currently zoomed item (or of the root item) in the window's title bar
    return [[self zoomedItem] path];
}

- (NSString *)displayName
{
    NSString *displayName = [[self zoomedItem] displayName];
	
	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

    displayName = [displayName stringByAppendingFormat: @" (%@)", [sizeFormatter stringForObjectValue: [[self zoomedItem] size]]];

    return displayName;
}

- (NSDictionary*) kindStatistics
{
    NSAssert( _fileKindStatistics != nil, @"kind statistics aren't collected yet" );

    return _fileKindStatistics;
}

- (FileKindStatistic*) kindStatisticForItem: (FSItem*) item
{
    return [self kindStatisticForKind: [item kindName]];
}

- (FileKindStatistic*) kindStatisticForKind: (NSString*) kindName
{
    return [[self kindStatistics] objectForKey: kindName];
}

- (FileTypeColors*) fileTypeColors
{
	if ( _kindColors == nil )
	{
		if ( [[NSUserDefaults standardUserDefaults] boolForKey: ShareKindColors] )
			_kindColors = [FileTypeColors instance];
		else
			_kindColors = [[FileTypeColors alloc] init];
	}

	return _kindColors;
}

- (void) refreshFileKindStatistics
{
	[self willChangeValueForKey: @"kindStatistics"];
	
	//collect sizes and file count of all file kinds 
	[self addItemToFileKindStatistic: nil includingChilds: YES];
	
	//reserve the predefined colors for the kinds with the biggest size sums of the appropriate files
	[self reserveColorsForLargestKinds];

	[self didChangeValueForKey: @"kindStatistics"];

	//The search index is built out of these, so it is stale the moment they are
	//rebuilt - after a scan, a refresh, or anything that moved items about. This
	//is the one place that knows, which is why it is the one that says so.
	[self _dropSearchIndex];
}

#pragma mark ----------------------running a scan off the main thread---------------

//Where the item count of each completed scan is remembered, so the next scan of
//the same path has a real number to divide by.
static NSString * const ScannedItemCountsKey = @"ScannedItemCounts";

//How many file system objects the walk is likely to visit under this URL, or 0
//if there is nothing to base a guess on.
+ (NSUInteger) _estimatedItemCountForURL: (NSURL*) url
{
	NSString *path = [url path];

	//What the walk actually found here last time is the best estimate available,
	//and it corrects itself on every scan.
	NSDictionary *counts = [[NSUserDefaults standardUserDefaults] dictionaryForKey: ScannedItemCountsKey];
	NSNumber *remembered = [counts objectForKey: path];

	if ( [remembered unsignedIntegerValue] > 0 )
		return [remembered unsignedIntegerValue];

	//Failing that, a whole volume can be estimated from the file system itself:
	//statfs reports how many inodes are in use, which is close to the number of
	//objects the walk will visit. It answers for the *volume* though, so it is
	//no use for a folder inside one — asked about /usr/share it reports the
	//boot volume's 458,726 against the 20,180 actually there.
	if ( [url isVolume] )
	{
		struct statfs fs;

		if ( statfs( [url fileSystemRepresentation], &fs ) == 0 && fs.f_files >= fs.f_ffree )
			return (NSUInteger) ( fs.f_files - fs.f_ffree );
	}

	return 0;
}

+ (void) _rememberItemCount: (NSUInteger) count forURL: (NSURL*) url
{
	if ( count == 0 || [url path] == nil )
		return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *counts = [[defaults dictionaryForKey: ScannedItemCountsKey] mutableCopy];

	if ( counts == nil )
		counts = [NSMutableDictionary dictionary];

	//Drop paths that are gone, so this cannot grow without bound over the years.
	//A handful of stat calls once per scan is nothing next to the scan itself.
	for ( NSString *knownPath in [counts allKeys] )
	{
		if ( ![[NSFileManager defaultManager] fileExistsAtPath: knownPath] )
			[counts removeObjectForKey: knownPath];
	}

	[counts setObject: [NSNumber numberWithUnsignedInteger: count] forKey: [url path]];

	[defaults setObject: counts forKey: ScannedItemCountsKey];
}

- (void) _beginScan
{
	if ( _scanLock == nil )
		_scanLock = [[NSLock alloc] init];

	[_scanLock lock];
	_scanCancelled = NO;
	_scanCurrentPath = nil;
	_scanItemsDone = 0;
	[_scanLock unlock];

	//read once, here, so the scan queue never touches the document's options
	_scanIgnoreCreatorCode   = [self ignoreCreatorCode];
	_scanLookIntoPackages    = [self showPackageContents];
	_scanUsePhysicalFileSize = [self showPhysicalFileSize];

	//Clamped rather than trusted: this is a number out of user defaults, and a
	//hand-edited or stale one must not turn into an unbounded number of queues.
	const NSInteger wanted = [[NSUserDefaults standardUserDefaults] integerForKey: ScanConcurrency];
	_scanConcurrency = (NSUInteger) MIN( MAX( wanted, ScanConcurrencyMinimum ), ScanConcurrencyMaximum );
}

- (void) _setScanCurrentPath: (NSString*) path
{
	[_scanLock lock];
	_scanCurrentPath = [path copy];
	[_scanLock unlock];
}

- (NSString*) _takeScanCurrentPath
{
	[_scanLock lock];
	NSString *path = _scanCurrentPath;
	_scanCurrentPath = nil;
	[_scanLock unlock];

	return path;
}

- (BOOL) _scanWasCancelled
{
	[_scanLock lock];
	const BOOL cancelled = _scanCancelled;
	[_scanLock unlock];

	return cancelled;
}

- (void) _cancelScan
{
	[_scanLock lock];
	_scanCancelled = YES;
	[_scanLock unlock];
}

//Runs "work" on a background queue and keeps the main thread in the progress
//panel until it finishes, returning whatever exception the work raised.
//
//The tree is built entirely on the queue and only reaches the main thread once
//this returns, so nothing is shared with the views while it is being built.
//What the main thread does meanwhile is run the panel: that is the whole point,
//since it used to be doing the file system walk and squeezing the interface in
//every 0.2 seconds.
//
//The exception has to be carried across by hand. Raising it on the queue and
//catching it on the main thread is not a thing that can happen, and this walk
//uses exceptions as ordinary control flow — cancelling raises one.
//Every scan in the application runs on this one queue, so two documents opening
//at once cannot be walking trees simultaneously. That matters because the walk
//touches process-wide state that is not guarded: FSItem's g_kindNameDictionary
//cache, and the g_fileCount/g_folderCount counters. Serialising also keeps the
//behaviour the old main-thread scan had, where a second scan simply waited.
+ (dispatch_queue_t) _scanQueue
{
	static dispatch_queue_t queue = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{
		queue = dispatch_queue_create( "io.github.xxderek.DiskInventoryNext.scan",
									   dispatch_queue_attr_make_with_qos_class(
										   DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0 ) );
	});

	return queue;
}

- (NSException*) _runScanBlockOffMainThread: (void (^)(void)) work
							 estimatingFrom: (NSURL*) rootURL
{
	NSAssert( [NSThread isMainThread], @"a scan must be started from the main thread" );

	[self _beginScan];

	_scanEstimatedTotal = ( rootURL != nil ) ? [[self class] _estimatedItemCountForURL: rootURL] : 0;
	[_progressController setProgressFraction: ( _scanEstimatedTotal > 0 ) ? 0.0 : -1.0];

	__block NSException *caught = nil;
	__block BOOL finished = NO;

	dispatch_async( [[self class] _scanQueue], ^{
		@autoreleasepool
		{
			@try
			{
				work();
			}
			@catch ( NSException *exception )
			{
				caught = exception;
			}

			//back on the main thread, so the flag is written where it is read
			dispatch_async( dispatch_get_main_queue(), ^{ finished = YES; } );
		}
	});

	//How often the path label is refreshed, as against how often the main thread
	//wakes. Waking often is what makes Cancel feel immediate; redrawing the
	//label that often is just work, and measurably slowed the scan when the two
	//were the same number.
	const NSTimeInterval messageInterval = 0.1;
	uint64_t lastMessageTime = 0;

	while ( !finished )
	{
		@autoreleasepool
		{
			uint64_t now = getTime();
			if ( lastMessageTime == 0 || subtractTime( now, lastMessageTime ) >= messageInterval )
			{
				NSString *path = [self _takeScanCurrentPath];
				if ( path != nil )
					[_progressController setMessageText: path];

				[_scanLock lock];
				const NSUInteger done = _scanItemsDone;
				[_scanLock unlock];

				[_progressController setProgressFraction:
					( _scanEstimatedTotal > 0 ) ? (double) done / (double) _scanEstimatedTotal : -1.0];

				lastMessageTime = now;
			}

			if ( ![_progressController runModalSessionForInterval: 0.05] )
			{
				//the session ended under us; stop the walk rather than waiting
				//out a scan whose panel has gone
				[self _cancelScan];
				break;
			}

			if ( [_progressController cancelPressed] )
				[self _cancelScan];
		}
	}

	//the queue may still be unwinding after a cancel; wait for it, or the tree
	//would be torn down underneath it
	while ( !finished )
	{
		@autoreleasepool
		{
			[[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
									 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]];
		}
	}

	return caught;
}

#pragma mark ----------------------FSItem delegates-----------------------------------

//Called for every folder, on the scan queue. It must not touch the progress
//panel or any other view: it records the path for the main thread to pick up
//and answers whether to keep going. This used to pump the event loop from here,
//which is what made the scan and the interface take turns on one thread.
- (BOOL) fsItemEnteringFolder: (FSItem*) item
{
	//if we don't show the progress panel, we don't need to do anything
	if ( _progressController == nil )
		return YES; //YES == continue loading
	
	//How deep this folder is used to be the height of a stack pushed here and
	//popped in -fsItemExittingFolder:, guarded by an assertion that the folder
	//arriving was a child of the one on top. That assertion was a fair statement
	//of the old walk: strictly depth-first, and on one thread. Subtrees are now
	//walked concurrently, so folders arrive interleaved and no single stack can
	//describe them.
	//
	//Counting the item's own parents needs no shared state, cannot disagree with
	//the item it describes, and costs a pointer chase per folder against a walk
	//that opens a directory. The old stack held this folder as well as its
	//ancestors, so its count was one more than the number of parents.
	NSUInteger depth = 0;
	for ( FSItem *ancestor = [item parent]; ancestor != nil && depth < 4; ancestor = [ancestor parent] )
		depth++;

	//we display only folders 4 levels deep and we don't go into packages
	if ( depth < 4 )
	{
		FSItem* parentItem = [item parent];
		while ( parentItem != nil && ![parentItem isPackage] )
			parentItem = [parentItem parent];

		if ( parentItem == nil )
			[self _setScanCurrentPath: [item displayPath]];
	}

	//g_fileCount and g_folderCount are atomic, and incremented as each FSItem is
	//created - on whichever queue created it. Reading them here is a snapshot
	//that may be a few items stale, which a progress bar does not care about.
	//Folder granularity is plenty: a 20,000-item scan passes through here ~900
	//times.
	[_scanLock lock];
	_scanItemsDone = g_fileCount + g_folderCount;
	[_scanLock unlock];

	return ![self _scanWasCancelled];
}

- (BOOL) fsItemExittingFolder: (FSItem*) item
{
	//if we don't show the progress panel, we don't need to do anything
	if ( _progressController == nil )
		return YES; //YES == continue loading
	
	//nothing to unwind: -fsItemEnteringFolder: counts an item's depth from its
	//own parents rather than from a stack kept here, so that concurrent subtree
	//walks cannot interleave into nonsense
	(void) item;

	return YES;
}

//These three are asked once per file, from the scan queue. They answer from a
//snapshot taken before the scan started rather than reading the document's view
//options live, so the queue never reads state the main thread could be writing.
- (BOOL) fsItemShouldIgnoreCreatorCode: (FSItem*) item
{
	return _scanIgnoreCreatorCode;
}

- (BOOL) fsItemShouldLookIntoPackages: (FSItem*) item
{
	return _scanLookIntoPackages;
}

- (BOOL) fsItemShouldUsePhysicalFileSize: (FSItem*) item
{
	return _scanUsePhysicalFileSize;
}

- (NSUInteger) fsItemMaxConcurrentSubtreeWalks: (FSItem*) item
{
	return _scanConcurrency;
}

#pragma mark --------KVO-----------------

- (void)observeValueForKeyPath:(NSString*)keyPath
					  ofObject:(id)object
						change:(NSDictionary*)change
					   context:(void*)context
{
	LOG( @"FileSystemDoc.observeValueForKeyPath: keyPath: %@, change dict:%@", keyPath, change );
	
	//this global preference option is cached in an instance variable for performance reasons
	if ( context == (__bridge void*) ShareKindColors )
	{
		//if "share colors" was enabled previously, reset the shared colors so we get "fresh" colors the next time it is turned on again
		[_kindColors reset];
		_kindColors = nil;
		
		[self reserveColorsForLargestKinds];
	}
}

@end

//================ implementation FileSystemDoc(Private) ======================================================

@implementation FileSystemDoc(Private)

- (NSMutableDictionary*) viewOptions
{
	return _viewOptions;
}

- (void) postViewOptionChangedNotificationForOption: (NSString*) optionName
{
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject: optionName forKey: ChangedViewOption];
	
	[[NSNotificationCenter defaultCenter] postNotificationName: ViewOptionChangedNotification
														object: self
													  userInfo: userInfo];
}

- (void) postNotificationName: (NSString*) name oldItem: (FSItem*) old newItem: (FSItem*) new
{
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys: old, OldItem, new, NewItem, nil];
	
	[[NSNotificationCenter defaultCenter] postNotificationName: name object: self userInfo: info];
}

- (void) recalculateTotalSize
{
	[[self rootItem] recalculateSize: [self showPhysicalFileSize] updateParent: NO];
}

- (void) addItemToFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds
{
    //if we are called with nil as item, we rebuild the statistic
    if ( item == nil )
    {
		_fileKindStatistics = [[NSMutableDictionary alloc] init];
        
        item = [self zoomedItem];
    }
	
    if ( ![self itemIsNode: item] )
    {
        //item is a file (or regarded as such if item is a package and "show package contents" is turned off),
        //so add it's informations to the appropriate statistic object
        if ( [item kindName] != nil )
        {
            FileKindStatistic* kindStatistic = [self kindStatisticForItem: item];
            if ( kindStatistic == nil )
            {
                //we don't have a statistic object for the item's kind yet, so create one
                kindStatistic = [[FileKindStatistic alloc] initWithItem: item];
                [_fileKindStatistics setObject: kindStatistic forKey: [item kindName]];
            }
            else
                [kindStatistic addItem: item];
        }
	}
	else if ( includingChilds )
	{
		//if the item is a folder, recurse through it's childs
        NSUInteger i = [item childCount];
        while ( i-- )
            [self addItemToFileKindStatistic: [item childAtIndex: i] includingChilds: YES];
    }
}

- (void) removeItemFromFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds
{
	NSParameterAssert( item != nil );
	
    if ( ![self itemIsNode: item] )
    {
        //item is a file (or regarded as such if item is a package and "show package contents" is turned off),
		//so remove it's information from the appropriate statistic object
        FileKindStatistic* kindStatistic = [self kindStatisticForItem: item];
        if ( kindStatistic != nil )
            [kindStatistic removeItem: item];
	}
	else if ( includingChilds )
	{
		//if the item is a folder, recurse through it's childs
        NSUInteger i = [item childCount];
        while ( i-- )
            [self removeItemFromFileKindStatistic: [item childAtIndex: i] includingChilds: YES];		
    }
}

- (void) recalculateFileKindStatisticSizes
{
	[self willChangeValueForKey: @"kindStatistics"];
	
	NSEnumerator *statisticEnum = [[self kindStatistics] objectEnumerator];
	FileKindStatistic *statistic = nil;
	while ( (statistic = [statisticEnum nextObject]) != nil )
		[statistic recalculateSize];
	
	[self didChangeValueForKey: @"kindStatistics"];
}

- (void) removePackagesFromFileKindStatistic: (FSItem*) item
{
	BOOL bDoKVO = NO;
	if ( item == nil )
	{
		bDoKVO = YES;
		[self willChangeValueForKey: @"kindStatistics"];
		item = [self zoomedItem];
	}
	
	if ( [self itemIsNode: item] )
	{
		//if the item is regarded as a folder, recurse through it's childs
		NSUInteger i = [item childCount];
		while ( i-- )
			[self removePackagesFromFileKindStatistic: [item childAtIndex: i]];
	}
	else
	{
		if ( [item isPackage] )
			[self removeItemFromFileKindStatistic: item includingChilds: YES];
	}
	
	if ( bDoKVO )
	{
		[self removeEmptyKindStatistics];
		[self didChangeValueForKey: @"kindStatistics"];
	}
}

// !! does not work correctly in all cases (see comment in "setShowPackageContents")
- (void) addPackagesToFileKindStatistic: (FSItem*) item
{
	BOOL bDoKVO = NO;
	if ( item == nil )
	{
		bDoKVO = YES;
		[self willChangeValueForKey: @"kindStatistics"];
		item = [self zoomedItem];
	}
	
	if ( [self itemIsNode: item] )
	{
		//if the item is regarded as a folder, recurse through it's childs
		NSUInteger i = [item childCount];
		while ( i-- )
			[self addPackagesToFileKindStatistic: [item childAtIndex: i]];
	}
	else
	{
		if ( [item isPackage] )
			[self addItemToFileKindStatistic: item includingChilds: YES];
	}
	
	if ( bDoKVO )
		[self didChangeValueForKey: @"kindStatistics"];
}

- (void) removeEmptyKindStatistics
{
	NSEnumerator *keyEnumerator = [[[self kindStatistics] allKeys] objectEnumerator];
	NSString *kindName;
	while ( (kindName = [keyEnumerator nextObject]) != nil )
	{
		FileKindStatistic *stat = [_fileKindStatistics objectForKey: kindName];
		if ( [stat fileCount] == 0 )
			[_fileKindStatistics removeObjectForKey: kindName];
	}
}

- (void) reserveColorsForLargestKinds
{
	//get a mutable copy of the keys
    NSMutableArray *kinds = [[[self kindStatistics] allValues] mutableCopy];

    //order Statistics descendantly by size
    [kinds sortUsingSelector: @selector(compareSizeDescendingly:)];

    NSEnumerator *kindNameEnum = [kinds objectEnumerator];
    FileKindStatistic *kindStat;
    while ( ( kindStat = [kindNameEnum nextObject] ) != nil )
    {
        [[self fileTypeColors] colorForKind: [kindStat kindName]];
    }
	
 //mutableCopy returns a retained object (not autoreleased)
}

- (void)checkForProtectedFolders:(NSString * _Nonnull)folder
{
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSArray<NSURL*> *protectedFolders = [fileMgr privacyProtectedFoldersInURL:[NSURL fileURLWithPath:folder]];
    if ( [protectedFolders count] > 0 )
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ( ![defaults boolForVersionDependantKey: DontShowPrivacyWarningMessage] )
        {
            NSAlert *alert = [[NSAlert alloc] init];
            
            alert.alertStyle = NSAlertStyleInformational;
            
            alert.messageText = NSLocalizedString(@"Some folders which will be scanned contain private files. The access is protected by the macOS privacy protection.\n\nUpon first access macOS will ask whether you allow Disk Inventory Next access to these folders and files.\n\nDisk Inventory Next does not read any data - just information like file sizes and types are collected.", @"");
            alert.informativeText = NSLocalizedString(@"You can change the access settings in the System Preferences (Security/Privacy).", @"");
            
            alert.showsSuppressionButton = YES;
            alert.suppressionButton.title = NSLocalizedString(@"Do not show this information again.", @"");
            
            [alert runModal];
            
            if (alert.suppressionButton.state == NSControlStateValueOn)
            {
                // Suppress this alert for the current version
                [defaults setBool: YES forVersionDependantKey: DontShowPrivacyWarningMessage];
            }
            
            // let the alert disappear before the consent dialogs pop up
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate date]];
        }
        
        [fileMgr triggerConsentDialogForPrivacyProtectedFolders:protectedFolders];
    }
}

//@@test
- (void)canCloseDocumentWithDelegate:(id)delegate
                 shouldCloseSelector:(nullable SEL)shouldCloseSelector
                         contextInfo:(nullable void *)contextInfo
{
    @try
    {
        [super canCloseDocumentWithDelegate:delegate
                        shouldCloseSelector:shouldCloseSelector
                                contextInfo:contextInfo];
    }
    @catch (NSException *exception)
    {
        NSString *msg = [exception reason];
        
        NSLog(@"%@ exception catched: %@", [exception className], msg);
        
        
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression
                                      regularExpressionWithPattern:@"0x([a-f]*\\d*)*(\\w|$)"
                                      options:NSRegularExpressionCaseInsensitive
                                      error:&error];
        
        [regex enumerateMatchesInString:msg
                                options:NSMatchingReportCompletion
                                  range:NSMakeRange(0, [msg length])
                             usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop)
         {
             for (NSUInteger i = 0; i < [match numberOfRanges]; i++)
             {
                 NSString *objAddress = [msg substringWithRange:[match rangeAtIndex:i]];

                 unsigned long long address = 0;
                 NSScanner* scanner = [NSScanner scannerWithString:objAddress];
                 if ( [scanner scanHexLongLong: &address] )
                 {
                     NSLog(@"address in exception message: %@ (0x%llx)", objAddress, address);
                 }
                 else
                 {
                     NSLog(@"'%@' could not be parsed as hex string", objAddress);
                 }
             }
         }];
        
        @throw exception;
    }
}


@end

