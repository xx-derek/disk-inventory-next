//
//  FileSystemDoc.h
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


#import <Cocoa/Cocoa.h>
#import "DIXScanHistory.h"
#import "FSItem.h"
#import "Preferences.h"
#import "FileTypeColors.h"

//Forward-declared rather than imported: the scanning screen is drawn from a
//DIXScanProgress, which is declared below, so importing its header here would
//be a cycle.
@class DIXScanningController;

//holds information about the count and size of the files of one kind (e.g. MP3 files)
@interface FileKindStatistic : NSObject
{
    NSString *_kindName;
	unsigned long long _size;
	NSMutableSet *_items;
}

- (id) initWithItem: (FSItem*) item;

- (void) addItem: (FSItem* )item;
- (void) removeItem: (FSItem* )item;

- (NSString*) kindName;
- (NSString*) description;

- (NSUInteger) fileCount;		//# of files of this kind
- (unsigned long long) size; //sum of sizes of files of this kind
- (void) recalculateSize;

- (NSSet*) items;
- (NSEnumerator*) itemEnumerator;

- (NSComparisonResult) compareSizeDescendingly: (FileKindStatistic*) other;

@end

//Which of the two views of the tree the window is showing. "Both" is the
//default whenever the window is wide enough to hold sidebar, list and a usable
//map; below that it falls back to Map. Map and List stay deliberate choices,
//remembered per document.
typedef NS_ENUM( NSInteger, DIXViewMode )
{
	DIXViewModeMap  = 0,
	DIXViewModeList = 1,
	DIXViewModeBoth = 2,
};

@interface FileSystemDoc : NSDocument
{
    FSItem *_rootItem;
    FSItem *_selectedItem;
    NSMutableArray *_zoomStack;
    NSArray<FSItem*> *_focusedPile;   //see -focusedPile; nil unless a merged cell was opened

    //What the toolbar is searching for and what it found. The index is built on
    //the first search of a scan and thrown away whenever the tree changes.
    NSString *_searchString;
    FSItemIndexType _searchScope;
    NSArray<FSItem*> *_searchResults;
    id _searchIndex;

    NSMutableDictionary *_fileKindStatistics;	//dictionary: kind name -> FileKindStatistic
	NSMutableDictionary *_viewOptions;
	FileTypeColors *_kindColors;

	//The kind the map and the lists are narrowed to, or nil for all kinds.
	NSString *_kindFilter;

	//The items ticked for reclaiming, and the sum of their sizes. The set is
	//the truth; the total is cached because the reclaim bar redraws far more
	//often than the set changes.
	NSMutableSet<FSItem*> *_basketItems;
	unsigned long long _basketSize;

	DIXViewMode _viewMode;

	//What the previous scan of this same folder came to, read before this one
	//overwrites it - see -previousScanSize.
	unsigned long long _previousScanSize;
	NSDate *_previousScanDate;
	NSArray *_changesSinceLastScan;

	//"Show only these on the map". The two sets are the change list resolved to
	//items once, when the filter is switched on, so the per-cell test is pointer
	//comparisons up the parent chain rather than building a path per cell.
	BOOL _showsOnlyChanges;
	NSSet<FSItem*> *_changedItems;
	NSSet<FSItem*> *_changeAncestors;

	//What the summary strip reports. The counts are derived from the tree and
	//cached, rather than read from FSItem's g_fileCount/g_folderCount: those are
	//process wide and reset by whichever document scanned last, so a window left
	//open would start quoting another window's figures.
	NSUInteger _fileCount;
	NSUInteger _folderCount;
	BOOL _countsAreValid;
	NSDate *_scanCompletedAt;

	//these variables are used during the initial directory scan
	DIXScanningController *_progressController;

	//Set when the scan was stopped by "Show partial results" rather than by
	//Cancel: the walk stops the same way for both, and this is what decides
	//whether the tree it leaves behind is kept or thrown away.
	BOOL _scanKeepPartialResults;

	//What the scan was asked for and could not read - see -skippedFolders.
	NSArray<NSURL*> *_skippedFolders;

	//Scan state. The walk runs on a background queue while the main thread
	//keeps the progress panel alive, so anything both touch is guarded by
	//_scanLock — except the three option snapshots, which are written before
	//the queue starts and only read after that.
	NSLock *_scanLock;
	NSString *_scanCurrentPath;
	NSUInteger _scanItemsDone;
	NSUInteger _scanEstimatedTotal;   //0 when there is nothing to estimate from
	BOOL _scanCancelled;
	BOOL _scanIgnoreCreatorCode;
	BOOL _scanLookIntoPackages;
	BOOL _scanUsePhysicalFileSize;
	NSUInteger _scanConcurrency;

	//The rate the scanning screen reports, worked out on the main thread between
	//pump ticks and smoothed - an instantaneous figure over a 0.1s window jumps
	//between hundreds and tens of thousands and is unreadable.
	uint64_t _scanStartedAt;
	uint64_t _scanRateAt;
	NSUInteger _scanRateItems;
	double _scanRate;
}

- (BOOL) showPhysicalFileSize;
- (void) setShowPhysicalFileSize: (BOOL) show;
- (BOOL) showPackageContents;
- (void) setShowPackageContents: (BOOL) show;
- (BOOL) showFreeSpace;
- (void) setShowFreeSpace: (BOOL) show;
- (BOOL) showOtherSpace;
- (void) setShowOtherSpace: (BOOL) show;
- (BOOL) ignoreCreatorCode;
- (void) setIgnoreCreatorCode: (BOOL) ignoreIt;

- (BOOL) itemIsNode: (FSItem*) item; //helper method; returns YES/NO for packages depending on the showPackageContents-Flag

- (FSItem*) rootItem;

- (BOOL) moveItemToTrash: (FSItem*) item error:(NSError **)error;//will post a "FSItemsChangedNotification"
- (void) refreshItem: (FSItem*) item;//will post a "FSItemsChangedNotification"

- (FSItem*) zoomedItem;
- (void) zoomIntoItem: (FSItem*) item; //will post a "ZoomedItemChangedNotification"
- (void) zoomOutToItem: (FSItem*) item;
- (void) zoomOutOneStep;
- (NSArray*) zoomStack;

//A merged cell stands for a run of items too small to be drawn beside their
//larger siblings. Zooming "into" one cannot go on the zoom stack, which holds
//FSItems, and a merged cell is not one - so it is held here instead: while this
//is set the map lays out these items as its whole content, which is what gives
//them room. Nil the rest of the time.
//
//It is one level deep on purpose. A pile inside a pile would need a stack and
//the zoom stack is already that; anything that changes what the map shows -
//zooming either way, reloading the tree - drops the focus rather than trying to
//keep it valid against a tree that moved underneath it.
- (NSArray<FSItem*>*) focusedPile;
- (void) setFocusedPile: (NSArray<FSItem*>*) items; //posts "FocusedPileChangedNotification"

- (FSItem*) selectedItem;
- (void) setSelectedItem: (FSItem*) item; //will post a "GlobalSelectionChangedNotification"

#pragma mark --------searching the scan-----------------

//What the toolbar's search field is asking for, and what the file list answers
//with. It lives here rather than on either of them for the usual reason: the
//field is in the title bar and the list is three panes away, and the two must
//not talk to each other.
//
//-searchResults is nil when nothing is being searched for, which is not the same
//as an empty array - that means "searched, found nothing" and the list says so.
//Both setters post "SearchResultsChangedNotification".
- (NSString*) searchString;
- (void) setSearchString: (NSString*) searchString;

//which of name, kind and path to look in; FSItemIndexAll by default
- (FSItemIndexType) searchScope;
- (void) setSearchScope: (FSItemIndexType) scope;

- (NSArray<FSItem*>*) searchResults;

- (FileKindStatistic*) kindStatisticForItem: (FSItem*) item;
- (FileKindStatistic*) kindStatisticForKind: (NSString*) kindName;
- (NSDictionary*) kindStatistics;

- (FileTypeColors*) fileTypeColors;

- (void) refreshFileKindStatistics;

#pragma mark --------what a running scan is doing-----------------

//Everything the scanning screen draws, in one reading. Main thread only, and
//only meaningful while a scan is running.
typedef struct
{
	unsigned long long bytes;
	unsigned files;
	unsigned folders;
	unsigned skipped;

	//0...1, or negative when there is no total to divide by - see the note on
	//estimating scan progress. The screen leaves the bar and the percentage
	//blank rather than inventing a number.
	double fraction;

	double itemsPerSecond;
	double secondsRemaining;        //negative when unknown
} DIXScanProgress;

- (DIXScanProgress) scanProgress;

//The privacy-protected folders inside this scan that could not be read, so the
//total below them is missing whatever they hold. Empty when everything asked
//for was readable, which is the ordinary case once access has been granted.
- (NSArray<NSURL*>*) skippedFolders;

//Asks macOS for access to them again, which is what puts the consent dialog up.
//Answers whether every one of them is readable afterwards.
- (BOOL) requestAccessToSkippedFolders;

#pragma mark --------what the summary strip reports-----------------

//Counted over the tree on first ask and cached until the items change.
- (NSUInteger) fileCount;
- (NSUInteger) folderCount;

//When the scan that built this tree finished, or nil if it never did.
- (NSDate*) scanCompletedAt;

#pragma mark --------the kind filter-----------------

//The kind name the map and the lists are narrowed to, or nil for all kinds.
//Setting it posts a "ViewOptionChangedNotification" naming DIXKindFilterOption.
- (NSString*) kindFilter;
- (void) setKindFilter: (NSString*) kindName;

//YES when "item" should be drawn under the current filter. Special items are
//always shown: free and other space are not file kinds, so filtering them out
//would silently change what the total means.
- (BOOL) itemPassesKindFilter: (FSItem*) item;

#pragma mark --------the reclaim basket-----------------

//The items ticked for reclaiming. Changes post a
//"ReclaimBasketChangedNotification"; the userInfo is nil, since the basket is
//read back through these accessors.
- (NSSet<FSItem*>*) basketItems;
- (BOOL) isItemInBasket: (FSItem*) item;
- (void) toggleBasketItem: (FSItem*) item;
- (void) addItemsToBasket: (NSArray<FSItem*>*) items;
- (void) clearBasket;

- (NSUInteger) basketCount;
- (unsigned long long) basketSize;

#pragma mark --------the view mode-----------------

//Posts a "ViewOptionChangedNotification" naming DIXViewModeOption.
//What the last scan of this folder found, and when, or zero and nil if this is
//the first. Read at the moment the tree completes, because recording this scan
//is what overwrites it.
//What is a different size than it was, biggest first; empty on a first scan.
- (NSArray<DIXScanChange*>*) changesSinceLastScan;

- (unsigned long long) previousScanSize;
- (NSDate*) previousScanDate;

//The item a change refers to, or nil when it has been deleted since - which a
//shrinkage of the whole of something is exactly what it means. Descends by path
//component from the root rather than walking the tree, so it costs the depth of
//the path and not the size of the scan.
- (FSItem*) itemAtPath: (NSString*) path;

#pragma mark --------the change filter-----------------

//"Show only these on the map": everything that is not part of what changed since
//the last scan dims back, the same way the kind filter dims what it excludes and
//for the same reason - removing cells would relayout the map and a cell's area
//would stop being its size. Setting it posts a "ViewOptionChangedNotification"
//naming DIXChangeFilterOption.
- (BOOL) showsOnlyChanges;
- (void) setShowsOnlyChanges: (BOOL) showsOnlyChanges;

- (BOOL) itemPassesChangeFilter: (FSItem*) item;

- (DIXViewMode) viewMode;
- (void) setViewMode: (DIXViewMode) mode;

@end

/* keys for Key Value Observing (KVO) */
extern NSString *DocKeySelectedItem;

/* FileSystemDoc Notifications */
extern NSString *GlobalSelectionChangedNotification; //userInfo contains new and old selection
extern NSString *ZoomedItemChangedNotification; //userInfo contains new and old zoomed item
extern NSString *FSItemsChangedNotification; //some items are modified, deleted or added; userInfo is nil
extern NSString *ViewOptionChangedNotification; //the name of the changed option is stored in userInfo for key ChangedViewOption (see next line)
extern NSString *ChangedViewOption;
extern NSString *NewItem;
extern NSString *OldItem;

//the reclaim basket gained or lost items, or was emptied; userInfo is nil
extern NSString *ReclaimBasketChangedNotification;

//the map is now showing a merged cell's contents, or has stopped; userInfo is nil
extern NSString *FocusedPileChangedNotification;

//the search string, the scope or the results changed; userInfo is nil
extern NSString *SearchResultsChangedNotification;

//Option names carried by ViewOptionChangedNotification for the two settings
//that are not user defaults. The rest of the options are named by their
//defaults key, which is why these are spelled like keys but are not registered.
extern NSString *DIXKindFilterOption;
extern NSString *DIXViewModeOption;
extern NSString *DIXChangeFilterOption;
