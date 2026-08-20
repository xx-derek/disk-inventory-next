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
#import "FSItem.h"
#import "Preferences.h"
#import "LoadingPanelController.h"
#import "FileTypeColors.h"

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

	//What the summary strip reports. The counts are derived from the tree and
	//cached, rather than read from FSItem's g_fileCount/g_folderCount: those are
	//process wide and reset by whichever document scanned last, so a window left
	//open would start quoting another window's figures.
	NSUInteger _fileCount;
	NSUInteger _folderCount;
	BOOL _countsAreValid;
	NSDate *_scanCompletedAt;

	//these variables are used during the initial directory scan
	LoadingPanelController *_progressController;

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

- (FSItem*) selectedItem;
- (void) setSelectedItem: (FSItem*) item; //will post a "GlobalSelectionChangedNotification"

- (FileKindStatistic*) kindStatisticForItem: (FSItem*) item;
- (FileKindStatistic*) kindStatisticForKind: (NSString*) kindName;
- (NSDictionary*) kindStatistics;

- (FileTypeColors*) fileTypeColors;

- (void) refreshFileKindStatistics;

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

//Option names carried by ViewOptionChangedNotification for the two settings
//that are not user defaults. The rest of the options are named by their
//defaults key, which is why these are spelled like keys but are not registered.
extern NSString *DIXKindFilterOption;
extern NSString *DIXViewModeOption;
