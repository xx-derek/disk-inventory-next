//
//  DrivesPanelController.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 15.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "DrivesPanelController.h"
#import "FileSizeFormatter.h"
#import "VolumeNameTransformer.h"
#import "VolumeUsageTransformer.h"
#import "VolumeUsageCell.h"
#import "NSURL-Extensions.h"

//NTStringShare is a private class in the CocoaFoundation framework; but as it is not fully thread safe,
//we need to declare it here to be accessible (see [DrivesPanelController init])
@interface NTStringShare : NSObject
+ (NTStringShare*)sharedInstance;
@end

//============ interface DrivesPanelController(Private) ==========================================================

@interface DrivesPanelController(Private)

- (void) rebuildVolumesArray;
- (void) refreshVolumeSizes;
- (void) onVolumesChanged: (NSNotification*) notification;
- (void) onPanelWillClose: (NSNotification*) notification;

@end

//How often the sizes are re-read while the panel is on screen. Free space moves
//as the machine is used, and mount/unmount are the only other things that would
//ever prompt a re-read — so without this the panel shows whatever was true when
//it was first opened, for as long as it stays open.
static const NSTimeInterval kSizeRefreshInterval = 5.0;

//the resource values that go stale; the name, icon and format do not
static NSArray<NSURLResourceKey> *VolumeSizeResourceKeys( void )
{
	static NSArray<NSURLResourceKey> *keys = nil;

	if ( keys == nil )
		keys = [NSArray arrayWithObjects: NSURLVolumeTotalCapacityKey
										, NSURLVolumeAvailableCapacityKey
										, NSURLVolumeSupportsVolumeSizesKey
										, nil];

	return keys;
}


@implementation DrivesPanelController

+ (DrivesPanelController*) sharedController
{
	static DrivesPanelController *controller = nil;
	
	if ( controller == nil )
		controller = [[DrivesPanelController alloc] init];
	
	return controller;
}

- (id) init
{
	self = [super init];

	//register volume transformers needed in the volume tableview (before Nib is loaded!)
	[NSValueTransformer setValueTransformer:[VolumeNameTransformer transformer] forName: @"volumeNameTransformer"];
	[NSValueTransformer setValueTransformer:[VolumeUsageTransformer transformer] forName: @"volumeUsageTransformer"];

    NSNotificationCenter *wsNotiCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsNotiCenter addObserver: self
                     selector: @selector(onVolumesChanged:)
                         name: NSWorkspaceDidMountNotification
                       object: nil];
    
    [wsNotiCenter addObserver: self
                     selector: @selector(onVolumesChanged:)
                         name: NSWorkspaceDidUnmountNotification
                       object: nil];
    
    [wsNotiCenter addObserver: self
                     selector: @selector(onVolumesChanged:)
                         name: NSWorkspaceDidRenameVolumeNotification
                       object: nil];

	
	[self rebuildVolumesArray];
	
	//load Nib with volume panel
	//Under the old +loadNibNamed:owner: the nib's top-level objects were
	//retained (and leaked) for us. The replacement hands them back
	//autoreleased, so they have to be held or the panel is deallocated on
	//the way out of this method.
    NSArray *topLevelObjects = nil;
    const BOOL loadedNib = [[NSBundle mainBundle] loadNibNamed: @"VolumesPanel" owner: self topLevelObjects: &topLevelObjects];
    _nibTopLevelObjects = topLevelObjects;
    //This panel's nib does not set "release when closed", so AppKit defaults it
    //to YES and releases the panel itself on -close. That used to be balanced
    //by +loadNibNamed:owner: leaking the nib's top-level objects. Now that
    //_nibTopLevelObjects owns them properly, AppKit's release is one too many
    //and the app crashes tearing the window down.
    [_volumesPanel setReleasedWhenClosed: NO];
    if ( !loadedNib )
	{
		self = nil;
	}
	else
	{
		//open volume on double clicked (can't be configured in IB?)
		[_volumesTableView setDoubleAction: @selector(openVolume:)];
		
		//set FileSizeFormatter for the columns displaying sizes (capacity, free)
		FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
		[[[_volumesTableView tableColumnWithIdentifier: @"totalSize"] dataCell] setFormatter: sizeFormatter];
		[[[_volumesTableView tableColumnWithIdentifier: @"freeBytes"] dataCell] setFormatter: sizeFormatter];

		//The usage column carries a capacity bar, not text. Swapping the cell here
		//rather than in Interface Builder keeps it out of the four localized
		//VolumesPanel nibs, which hold a placeholder NSTextFieldCell apiece.
		[[_volumesTableView tableColumnWithIdentifier: @"usagePercent"] setDataCell: [[VolumeUsageCell alloc] init]];

		//stops the refresh timer again when the panel goes away
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(onPanelWillClose:)
													 name: NSWindowWillCloseNotification
												   object: _volumesPanel];
	}
	
	[_volumesPanel makeFirstResponder: _volumesTableView];
	
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self];

	//NSTimer retains its target, so a running timer would keep this alive rather
	//than the other way round; it is stopped when the panel closes, and this is
	//only the backstop
	[_sizeRefreshTimer invalidate];
}

- (NSArray*) volumes
{
	return _volumes;
}

- (IBAction)openVolume:(id)sender
{
	NSIndexSet *selectedIndexes = [_volumesTableView selectedRowIndexes];
	NSUInteger index = [selectedIndexes firstIndex];
	
	//open volume in each of the selected rows
    while (index != NSNotFound)
    {
		NSURL *volume = [[_volumes objectAtIndex: index] objectForKey: @"volume"];
        if ( [volume stillExists] )
        {
            NSString *path = [volume path];
            
            //defer it till the next loop cycle (otherwise the "Open Volume" button stays in "pressed" mode during the loading)
            [[NSRunLoop currentRunLoop] performSelector: @selector(openDocumentWithContentsOfFile:)
                                                 target: [NSDocumentController sharedDocumentController]
                                               argument: path
                                                  order: 1
                                                  modes: [NSArray arrayWithObject: NSDefaultRunLoopMode]];
        }
        
        index = [selectedIndexes indexGreaterThanIndex: index];
    }	
}

- (BOOL) panelIsVisible
{
	return [[self panel] isVisible];
}

- (void) showPanel
{
	//the panel may have been sitting closed for hours, so start from fresh
	//numbers rather than showing the last ones and correcting them a tick later
	[self refreshVolumeSizes];

	[[self panel] orderFront: nil];

	if ( _sizeRefreshTimer == nil )
		_sizeRefreshTimer = [NSTimer scheduledTimerWithTimeInterval: kSizeRefreshInterval
															 target: self
														   selector: @selector(refreshVolumeSizes)
														   userInfo: nil
															repeats: YES];
}

- (NSWindow*) panel
{
	return _volumesPanel;
}


@end

//============ implementation DrivesPanelController(Private) ==========================================================

@implementation DrivesPanelController(Private)

//fill array "_volumes" with mounted volumes and their images
- (void) rebuildVolumesArray
{
    NSArray *volProps = [NSArray arrayWithObjects:NSURLLocalizedNameKey
                                                , NSURLVolumeTotalCapacityKey
                                                , NSURLVolumeAvailableCapacityKey
                                                , NSURLVolumeSupportsVolumeSizesKey
                                                , NSURLVolumeLocalizedFormatDescriptionKey
                                                , nil];
    
    NSArray<NSURL *> *vols = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys: volProps
                                                                                                     options: NSVolumeEnumerationSkipHiddenVolumes];
    
    [self willChangeValueForKey: @"volumes"];
    
    NS_DURING
    _volumes = [[NSMutableArray alloc] initWithCapacity: [vols count]];
    
    for ( NSURL *volumeURL in vols )
    {
        [volumeURL cacheResourcesInArray: volProps];
        
        //put NSURL object for key "volume" in the entry dictionary
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject: volumeURL forKey: @"volume"];
        
        //put volume icon for key "image" in the entry dictionary
        NSImage *volImage = [volumeURL icon];
        [volImage setSize: NSMakeSize(32,32)];
        
        [entry setObject: ( volImage == nil ? (id)[NSNull null] : volImage )
                  forKey: @"image"];
        
        [_volumes addObject: entry];
    }
    NS_HANDLER
    NS_ENDHANDLER

    [self didChangeValueForKey: @"volumes"];
}

//Re-reads the sizes of the volumes already listed, without rebuilding the list.
//
//Doing it this way rather than calling -rebuildVolumesArray is what keeps the
//selection: the entry dictionaries are mutated in place, so the array controller's
//arrangedObjects is the same set of objects it was and nothing it has selected
//goes away underneath it. A rebuild replaces every entry, and the user loses the
//row they were about to open.
- (void) refreshVolumeSizes
{
    for ( NSDictionary *entry in _volumes )
    {
        NSURL *volumeURL = [entry objectForKey: @"volume"];

        [volumeURL recacheResourcesInArray: VolumeSizeResourceKeys()];
        [volumeURL invalidateCachedVolumeSpaceUsed];
    }

    //The bars read the cache as they draw, so this is what puts the new numbers
    //on screen — for the capacity/used/free column too, which re-runs
    //volumeUsageTransformer over the same URLs when the table re-pulls its values.
    [_volumesTableView reloadData];
}

#pragma mark --------NTVolumeMgr notifications-----------------

- (void) onVolumesChanged: (NSNotification*) notification
{
    [self rebuildVolumesArray];
}

#pragma mark --------NSWindow notifications-----------------

- (void) onPanelWillClose: (NSNotification*) notification
{
    [_sizeRefreshTimer invalidate];
    _sizeRefreshTimer = nil;
}

#pragma mark --------NSTableView notifications-----------------

- (void) tableViewSelectionDidChange: (NSNotification*) notification
{
}

#pragma mark --------NSTableView delegates-----------------

- (void) tableView:(NSTableView *) tableView willDisplayCell:(id) cell forTableColumn:(NSTableColumn *) tableColumn row:(NSInteger) row
{
	if ( [[tableColumn identifier] isEqualToString: @"usagePercent"] )
	{
		//The cell does the drawing and the clipping; all that is needed here is
		//to tell it what this row's volume looks like. Nothing is added to the
		//view hierarchy, so nothing can be left behind on a scroll or a remount.
		VolumeUsageCell *usageCell = (VolumeUsageCell*)cell;

		NSURL *volURL = [[_volumes objectAtIndex: row] objectForKey : @"volume"];

		const BOOL hasSizeInfo = [volURL getCachedBoolValue: NSURLVolumeSupportsVolumeSizesKey];
		[usageCell setHasSizeInfo: hasSizeInfo];

		if ( hasSizeInfo )
		{
			const double totalBytes = [[volURL cachedVolumeTotalCapacity] doubleValue];
			const double freeBytes = [[volURL cachedVolumeAvailableCapacity] doubleValue];

			//Both of those answer for the whole APFS container, so their
			//difference is the same number for every volume sharing one.
			//-cachedVolumeSpaceUsed answers for this volume alone; whatever is
			//left over belongs to its siblings and is drawn muted. Where the file
			//system will not say, it all counts as this volume's and the bar is
			//exactly what it was before.
			const double containerUsedBytes = totalBytes - freeBytes;
			NSNumber *ownUsed = [volURL cachedVolumeSpaceUsed];

			const double ownUsedBytes = ( ownUsed != nil && [ownUsed doubleValue] <= containerUsedBytes )
										? [ownUsed doubleValue]
										: containerUsedBytes;

			//guarded because a volume can claim to support sizes and still report
			//a capacity of zero, which would divide to a NaN here
			[usageCell setUsedFraction: totalBytes > 0 ? ownUsedBytes / totalBytes : 0.0];
			[usageCell setSharedUsedFraction: totalBytes > 0 ? ( containerUsedBytes - ownUsedBytes ) / totalBytes : 0.0];
		}
	}
}


@end
