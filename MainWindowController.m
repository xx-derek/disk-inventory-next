//
//  MainWindowController.m
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

#import "MainWindowController.h"

NSString *SelectionListVisibilityChangedNotification = @"SelectionListVisibilityChanged";
#import "InfoPanelController.h"
#import "Timing.h"
#import <TreeMapView/TreeMapView.h>
#import "FSItem-Utilities.h"
#import "FileSizeTransformer.h"
#import "AppsForItem.h"
#import "NSURL-Extensions.h"

@interface MainWindowController(Private)
- (void) moveToTrashSheetDidDismiss: (NSWindow*) sheet returnCode: (int) returnCode contextInfo: (void*) contextInfo;
@end

@implementation MainWindowController

+ (void)initialize
{
    /* Make sure code only gets executed once. */
    static BOOL initialized = NO;
    if ( initialized )
		return;
    initialized = YES;
	
	//initalize support for the service menu
    NSArray *sendTypes = [NSArray arrayWithObjects: NSFilenamesPboardType, nil];
    NSArray *returnTypes = [NSArray array];
	
	[NSApp registerServicesMenuSendTypes: sendTypes returnTypes: returnTypes];
}

- (id) initWithWindowNibName:(NSString *)windowNibName
{
	self = [super initWithWindowNibName: windowNibName];
	
	if ( self != nil )
	{
		//register volume transformers needed by various controls
		[NSValueTransformer setValueTransformer:[FileSizeTransformer transformer] forName: @"fileSizeTransformer"];
	}
	
	return self;
}

+ (FileSystemDoc*) documentForView: (NSView*) view
{
    FileSystemDoc* doc = nil;

    NSWindow *window = [view window];
    
    id delegate = [window delegate];
    NSAssert( delegate != nil, @"expecting to retrieve the document from the window controller, which should be the window's delegate; but the window has no delegte" );
    NSAssert( [delegate respondsToSelector: @selector(document)], @"window's delegate has no method 'document' to retrieve document object" );

	doc = [delegate document];
	NSAssert( [doc isKindOfClass: [FileSystemDoc class]], @"document object is not of expected kind 'FileSystemDoc'" );

    return doc;
}

+ (void) poofEffectInView: (NSView*)view inRect: (NSRect) rect //rect in view coords
{
	//center poof antimation in the rect
	NSPoint poofEffectPoint = NSMakePoint( NSMinX(rect) + NSWidth(rect)/2,
										   NSMinY(rect) + NSHeight(rect)/2);
	
	//coordinates for the poof effect must be in screen coordidates, so...
	//convert view to window coords
	poofEffectPoint = [view convertPoint: poofEffectPoint toView: nil];
	
	//convert window to screen coords
	poofEffectPoint = [[view window] convertBaseToScreen: poofEffectPoint];
	
	NSSize size = NSMakeSize(NSWidth(rect), NSHeight(rect));
	
	//make sure the rect is not too small nor too large
	if ( fminf(size.width, size.height) <= 25 || ( size.width + size.height ) <= 80 )
		size = NSZeroSize;	//default size
	
	size.width = fminf( size.width, 200 );
	size.height = fminf( size.height, 200 );
	
	NSShowAnimationEffect(NSAnimationEffectPoof, poofEffectPoint, size, nil, (SEL)0, nil);
}

- (void) awakeFromNib
{
	//split window horizontally?
	if ( [[NSUserDefaults standardUserDefaults] boolForKey: SplitWindowHorizontally] )
	{
		[_splitter setVertical: NO];		
	}
	
	//NSSplitView remembers the divider position itself
	[_splitter setAutosaveName: @"MainWindowSplitter"];

	[self buildSidePanes];
}

#pragma mark -----------------side panes-----------------------

//Takes the two views the nib built inside the drawers and installs them as
//collapsible split-view panes instead: statistics to the left of the outline and
//treemap, selection list below them, which is where the drawers used to slide
//out from. Done here rather than in the nib so the four localized nibs do not
//have to be restructured.
- (void) buildSidePanes
{
	NSView *contentView = [[self window] contentView];

	_kindStatisticsPane = [_kindsDrawer contentView];
	_selectionListPane = [_selectionListDrawer contentView];

	//the drawers keep their content views alive, so take them away first
	[_kindsDrawer setContentView: nil];
	[_selectionListDrawer setContentView: nil];

	if ( _kindStatisticsPane == nil || _selectionListPane == nil )
	{
		NSLog( @"side panes could not be built: the nib did not supply their content views" );
		return;
	}

	//Take over exactly the space the outline/treemap splitter occupied, not the
	//whole content view: the treemap's name and size labels live below it, and
	//filling the content view would cover them.
	const NSRect paneFrame = [_splitter frame];
	const NSAutoresizingMaskOptions paneMask = [_splitter autoresizingMask];

	//selection list goes underneath the outline/treemap splitter
	_selectionListSplitView = [[NSSplitView alloc] initWithFrame: paneFrame];
	[_selectionListSplitView setVertical: NO];
	[_selectionListSplitView setDividerStyle: NSSplitViewDividerStyleThin];
	[_selectionListSplitView setDelegate: self];
	[_selectionListSplitView setAutosaveName: @"MainWindowSelectionListSplit"];

	//statistics go to the left of everything else
	_kindStatisticsSplitView = [[NSSplitView alloc] initWithFrame: paneFrame];
	[_kindStatisticsSplitView setVertical: YES];
	[_kindStatisticsSplitView setDividerStyle: NSSplitViewDividerStyleThin];
	[_kindStatisticsSplitView setDelegate: self];
	[_kindStatisticsSplitView setAutosaveName: @"MainWindowKindStatisticsSplit"];

	[_splitter removeFromSuperview];

	[_selectionListSplitView addSubview: _splitter];
	[_selectionListSplitView addSubview: _selectionListPane];

	[_kindStatisticsSplitView addSubview: _kindStatisticsPane];
	[_kindStatisticsSplitView addSubview: _selectionListSplitView];

	[_kindStatisticsSplitView setFrame: paneFrame];
	[_kindStatisticsSplitView setAutoresizingMask: paneMask];
	[contentView addSubview: _kindStatisticsSplitView];

	//the statistics drawer was opened at launch; the selection list was not
	[self setKindStatisticsVisible: YES];
	[self setSelectionListVisible: NO];
}

//A hidden subview is how NSSplitView collapses a pane: it keeps the subview and
//its constraints but gives it no space, which is what the drawers did visually.
- (BOOL) isKindStatisticsVisible
{
	return _kindStatisticsPane != nil && ![_kindStatisticsPane isHidden];
}

- (void) setKindStatisticsVisible: (BOOL) visible
{
	if ( _kindStatisticsPane == nil || visible == [self isKindStatisticsVisible] )
		return;

	[_kindStatisticsPane setHidden: !visible];
	[_kindStatisticsSplitView adjustSubviews];
}

- (BOOL) isSelectionListVisible
{
	return _selectionListPane != nil && ![_selectionListPane isHidden];
}

- (void) setSelectionListVisible: (BOOL) visible
{
	if ( _selectionListPane == nil || visible == [self isSelectionListVisible] )
		return;

	[_selectionListPane setHidden: !visible];
	[_selectionListSplitView adjustSubviews];

	//the list suspends its own updates while it is off screen
	[[NSNotificationCenter defaultCenter] postNotificationName: SelectionListVisibilityChangedNotification
														object: self];
}

#pragma mark -----------------NSSplitView delegate-----------------------

- (BOOL) splitView: (NSSplitView*) splitView canCollapseSubview: (NSView*) subview
{
	return subview == _kindStatisticsPane || subview == _selectionListPane;
}

- (CGFloat) splitView: (NSSplitView*) splitView
constrainMinCoordinate: (CGFloat) proposedMin
		  ofSubviewAt: (NSInteger) dividerIndex
{
	//keep the statistics pane usable rather than letting it be dragged to a sliver
	return ( splitView == _kindStatisticsSplitView ) ? MAX( proposedMin, 120.0 ) : proposedMin;
}

- (CGFloat) splitView: (NSSplitView*) splitView
constrainMaxCoordinate: (CGFloat) proposedMax
		  ofSubviewAt: (NSInteger) dividerIndex
{
	//and leave room for the outline and treemap
	return ( splitView == _kindStatisticsSplitView ) ? MIN( proposedMax, NSWidth([splitView bounds]) - 250.0 )
													 : MIN( proposedMax, NSHeight([splitView bounds]) - 150.0 );
}

#pragma mark -----------------menu and toolbar actions-----------------------

//named for the drawers they used to toggle, because the main menu nib and
//MainWindowToolbar.toolbar refer to these selectors by name
- (IBAction)toggleFileKindsDrawer:(id)sender
{
    [self setKindStatisticsVisible: ![self isKindStatisticsVisible]];
}

- (IBAction) toggleSelectionListDrawer:(id)sender
{
	[self setSelectionListVisible: ![self isSelectionListVisible]];
}

- (IBAction) openFile:(id)sender
{
	NSAssert( [sender isKindOfClass: [NSMenuItem class]], @"sender is not a menu item" );
	NSMenuItem *menuItem = (NSMenuItem*) sender;
	
	FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];
	NSURL *appURL = [menuItem representedObject];
	
	if ( appURL == nil )
		appURL = [[AppsForItem appsForItemURL: [selectedItem fileURL]] defaultAppURL];
	
	[AppsForItem openItemURL: [selectedItem fileURL] withAppURL: appURL];
}

- (IBAction) zoomIn:(id)sender
{
    FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];

    if ( selectedItem != nil && [selectedItem isFolder] )
    {
        [[self document] zoomIntoItem: selectedItem];

        [self synchronizeWindowTitleWithDocumentName];
    }
}

- (IBAction) zoomOut:(id)sender
{
    FileSystemDoc *doc = [self document];
    
    FSItem *currentZoomedItem = [doc zoomedItem];

    if ( currentZoomedItem != [doc rootItem] )
    {
        [doc zoomOutOneStep];

        [doc setSelectedItem: currentZoomedItem];

        [self synchronizeWindowTitleWithDocumentName];
    }
}

- (IBAction) zoomOutTo:(id)sender
{
    FileSystemDoc *doc = [self document];
	FSItem *item = [sender representedObject];
	
	NSAssert( [doc rootItem] == [item root], @"item belongs to a different document" );
	NSAssert( [[doc zoomStack] indexOfObjectIdenticalTo: item] != NSNotFound, @"item is not on the zoom stack" );
	
    FSItem *currentZoomedItem = [doc zoomedItem];
		
	[doc zoomOutToItem: item];
	
	[doc setSelectedItem: currentZoomedItem];
	
	[self synchronizeWindowTitleWithDocumentName];
}

- (IBAction) showInFinder:(id)sender
{
    FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];

    if ( selectedItem != nil && [selectedItem exists] )
        [[NSWorkspace sharedWorkspace] selectFile: [selectedItem path] inFileViewerRootedAtPath: @""];
}

- (IBAction) refresh:(id)sender
{
	FileSystemDoc *doc = [self document];
    FSItem *selectedItem = [doc selectedItem];
	
	if ( selectedItem == nil )
		return;
	
	[doc refreshItem: selectedItem];
	
	//the zoomed item might have changed
	[self synchronizeWindowTitleWithDocumentName];
}	

- (IBAction) refreshAll:(id)sender
{
	[[self document] refreshItem: nil];
	
	//the zoomed item might have changed
	[self synchronizeWindowTitleWithDocumentName];
}	

- (IBAction) moveToTrash:(id)sender
{
	FileSystemDoc *doc = [self document];
    FSItem *selectedItem = [doc selectedItem];
	
	if ( selectedItem == nil || selectedItem == [doc zoomedItem] || [selectedItem isSpecialItem] )
		return;
	
	//if file/folder lies on a network volume, it will be deleted!
	//So warn the user and ask to proceed.
	//(only local items can be moved to trash)
	if ( ![[selectedItem fileURL] isLocalVolume] )
	{
		NSString *msg = [NSString stringWithFormat: NSLocalizedString(@"The item \"%@\" could not be moved to the trash.",@""),
													[selectedItem displayName]];

		NSBeginAlertSheet( msg,
                          NSLocalizedString(@"No",@""),
                          NSLocalizedString(@"Yes",@""),
						  nil,
						  [self window],
						  self,
						  nil,
						  @selector(moveToTrashSheetDidDismiss: returnCode: contextInfo:),
						  //unowned: the document holds the selection for as long as the
						  //sheet is up, so nothing else has to keep it alive
						  (__bridge void*) selectedItem,
						  @"%@", NSLocalizedString(@"Would you like to delete it immediately?",@""));
	}
	else
	{
		[self moveToTrashSheetDidDismiss: nil
							  returnCode: NSAlertAlternateReturn
							 contextInfo: (__bridge void*) selectedItem];
	}
}

- (IBAction) showPackageContents:(id)sender
{
    FileSystemDoc *doc = [self document];
	
    [doc setShowPackageContents: ![doc showPackageContents]];
}

- (IBAction) showFreeSpace:(id)sender
{
    FileSystemDoc *doc = [self document];
	
    [doc setShowFreeSpace: ![doc showFreeSpace]];
}

- (IBAction) showOtherSpace:(id)sender
{
    FileSystemDoc *doc = [self document];
	
    [doc setShowOtherSpace: ![doc showOtherSpace]];
}

- (IBAction) selectParentItem:(id)sender
{
    FileSystemDoc *doc = [self document];
    
    FSItem *selectedItem = [doc selectedItem];

	//don't set selection to parent if selected item is zoomed item or one of it's direct childs
    if ( selectedItem != [doc zoomedItem] && [selectedItem parent] != [doc zoomedItem] )
    {
        [doc setSelectedItem: [selectedItem parent]];
    }
}

- (IBAction) changeSplitting:(id)sender
{
	[_splitter setVertical: ![_splitter isVertical]];
	
	[[[self window] contentView] setNeedsDisplay: TRUE];
}

- (IBAction) showInformationPanel:(id)sender
{
	InfoPanelController *infoController = [InfoPanelController sharedController];
	
	if ( [infoController panelIsVisible] )
		[infoController hidePanel];
	else
	{
		FSItem *item = [(FileSystemDoc*)[self document] selectedItem];
		[infoController showPanelWithFSItem: item];
	}
}

- (IBAction) showPhysicalSizes:(id) sender
{
	FileSystemDoc *doc = [self document];
	
	[doc setShowPhysicalFileSize: ![doc showPhysicalFileSize]];
	
	[self synchronizeWindowTitleWithDocumentName];
}

- (IBAction) ignoreCreatorCode:(id) sender
{
	FileSystemDoc *doc = [self document];
	
	[doc setIgnoreCreatorCode: ![doc ignoreCreatorCode]];
}

- (IBAction) performRenderBenchmark:(id)sender
{
	uint64_t startTime = getTime();
	
	unsigned count = 20;
	
	[_treeMapView benchmarkRenderingWithImageSize: NSMakeSize( 1024, 768 ) count: count];
	
	uint64_t doneTime = getTime();
	
	NSString *msg = [NSString stringWithFormat: @"rendering %u times took %.2f seconds", count, subtractTime(doneTime, startTime)];
	NSBeginInformationalAlertSheet( msg, nil, nil, nil, [_splitter window], nil, nil, nil, nil, @"" );
}

- (IBAction) performLayoutBenchmark:(id)sender
{
	uint64_t startTime = getTime();
	
	unsigned count = 100;
	
	[_treeMapView benchmarkLayoutCalculationWithImageSize: NSMakeSize( 1024, 768 ) count: count];
	
	uint64_t doneTime = getTime();
	
	NSString *msg = [NSString stringWithFormat: @"layout calculation %u times took %.2f seconds", count, subtractTime(doneTime, startTime)];
	NSBeginInformationalAlertSheet( msg, nil, nil, nil, [_splitter window], nil, nil, nil, nil, @"" );
}

#pragma mark -----------------edit menu-----------------------

//The Edit menu's Copy item has always sent -copy: down the responder chain, but
//nothing implemented it, so it did nothing. The pasteboard support was only ever
//reachable through the Services menu and drag & drop, both of which go through
//the same -writeToPasteboard: below.
- (IBAction) copy: (id) sender
{
	FSItem *item = [(FileSystemDoc*)[self document] selectedItem];

	if ( item == nil || [item isSpecialItem] || ![item exists] )
		return;

	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];

	[item writeToPasteboard: pboard];
}

#pragma mark -----------------UI elment validation-----------------------

- (BOOL) validateMenuItem: (NSMenuItem*) menuItem
{
    FileSystemDoc *doc = [self document];
    FSItem *selectedItem = [doc selectedItem];
	SEL menuAction = [menuItem action];

#define SET_TITLE( condition, string1, string2 ) \
	[menuItem setTitle: NSLocalizedString( (condition) ? string1 : string2, @"")]
		
#define SET_TITLE_AND_IMAGE( condition, string1, string2 )	\
	SET_TITLE( (condition), string1, string2 );				\
	if ( [menuItem isKindOfClass: [NSToolbarItemValidationAdapter class]] )\
		 [menuItem setState: (condition) ? NSOffState : NSOnState];
	
    if ( menuAction == @selector(openFile:)
		 || menuAction == @selector(openFileWith:) )
    {
        if ( selectedItem == nil )
			NO;
		
		AppsForItem *apps = [AppsForItem appsForItemURL: [selectedItem fileURL]];
		return [apps defaultAppURL] != nil;
    }
    else if ( menuAction == @selector(zoomIn:) )
    {
        return selectedItem != nil && [selectedItem isFolder] && ![_treeMapView zoomingInProgress];
    }
    else if ( menuAction == @selector(zoomOut:) )
    {
        return [doc rootItem] != [doc zoomedItem] && ![_treeMapView zoomingInProgress];
    }
    else if ( menuAction == @selector(showInFinder:)
			  || menuAction == @selector(refresh:))
    {
        return selectedItem != nil;
    }
    else if ( menuAction == @selector(copy:) )
    {
        return selectedItem != nil && ![selectedItem isSpecialItem] && [selectedItem exists];
    }
    else if ( menuAction == @selector(moveToTrash:) )
    {
		//the trash folder and items residing in it can't be moved to trash
		BOOL selectItemResidesInTrash = NO;
		if ( selectedItem != nil )
		{
            NSURL *selectedURL = [selectedItem fileURL];

            NSURL *trashURL = [[NSFileManager defaultManager] URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:selectedURL create:NO error:nil];
            
			if ( trashURL != nil )
			{
                selectItemResidesInTrash = [selectedURL isEqualToURL: trashURL] || [selectedURL residesInDirectoryURL:trashURL];
			}
		}
        return !selectItemResidesInTrash && selectedItem != nil && selectedItem != [doc zoomedItem] && ![selectedItem isSpecialItem];
    }
    else if ( menuAction == @selector(showPackageContents:) )
    {
        SET_TITLE_AND_IMAGE( [doc showPackageContents], @"Hide Package Contents", @"Show Package Contents" );
    }
    else if ( menuAction == @selector(showFreeSpace:) )
    {
        SET_TITLE_AND_IMAGE( [doc showFreeSpace], @"Hide Free Space", @"Show Free Space" );
    }
    else if ( menuAction == @selector(showOtherSpace:) )
    {
        SET_TITLE_AND_IMAGE( [doc showOtherSpace], @"Hide Other Space", @"Show Other Space" );
		if ( [[[doc zoomedItem] fileURL] isVolume] )
			return NO;
    }
    else if ( menuAction == @selector(showPhysicalSizes:) )
    {
        SET_TITLE_AND_IMAGE( [doc showPhysicalFileSize], @"Show Logical File Size", @"Show Physical File Size" );
    }
    else if ( menuAction == @selector(ignoreCreatorCode:) )
    {
        SET_TITLE_AND_IMAGE( [doc ignoreCreatorCode], @"Respect Creator Code", @"Ignore Creator Code" );
    }
    else if ( menuAction == @selector(toggleFileKindsDrawer:) )
    {
        SET_TITLE_AND_IMAGE( ![self isKindStatisticsVisible],
							 @"Show File Kind Statistics", @"Hide File Kind Statistics" );
    }
    else if ( menuAction == @selector(toggleSelectionListDrawer:) )
    {
        SET_TITLE( ![self isSelectionListVisible],
							 @"Show Selection List", @"Hide Selection List" );
    }
    else if ( menuAction == @selector(selectParentItem:) )
    {
        return selectedItem != nil && selectedItem != [doc zoomedItem];
    }   
    else if ( menuAction == @selector(showInformationPanel:) )
    {
        SET_TITLE_AND_IMAGE( [[InfoPanelController sharedController] panelIsVisible],
							 @"Hide Information", @"Show Information" );
    }   
    else if ( menuAction == @selector(changeSplitting:) )
    {
        SET_TITLE( [_splitter isVertical], @"Split Horizontally", @"Split Vertically" );
    }   
    
#undef SET_TITLE
#undef SET_TITLE_AND_IMAGE
	
    return YES;
}

#pragma mark -----------------Toolbar support---------------------

//used by ToolbarWindowController to load the toolbar configuration file (.toolbar)
- (NSString *)toolbarConfigurationName;
{
    return @"MainWindowToolbar";
}

#pragma mark -----------------NSWindow delegates-----------------------

- (void)windowDidBecomeMain:(NSNotification *)aNotification
{
	if ( [[InfoPanelController sharedController] panelIsVisible] )
	{
		FSItem *item = [(FileSystemDoc*)[self document] selectedItem];
		[[InfoPanelController sharedController] showPanelWithFSItem: item];
	}
}

- (void)windowDidResignMain:(NSNotification *)notification;
{
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	if ( [[aNotification object] isMainWindow]
		&& [[InfoPanelController sharedController] panelIsVisible] )
	{
		[[InfoPanelController sharedController] showPanelWithFSItem: nil];
	}
}

#pragma mark -----------------NSMenu delegates-----------------------

//populates the "Open With" sub menu which the default and additional applications which can open the selected file
- (void) menuNeedsUpdate: (NSMenu*) menu
{	
	NSAssert( _openWithSubMenu == menu, @"asked to update a menu that is not the Open With submenu" );
	
    FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];
	if ( selectedItem == nil )
		return;
	
	AppsForItem *apps = [AppsForItem appsForItemURL: [selectedItem fileURL]];
	
	NSMenuItem *menuItem = nil;
	NSURL *appURL = [apps defaultAppURL];
	
	if ( appURL != nil )
	{
		//the first and second menu item is the default app and a serperator item
		if ( [_openWithSubMenu numberOfItems] == 0 )
		{
			[_openWithSubMenu addItem: [[NSMenuItem alloc] init]];
			[_openWithSubMenu addItem: [NSMenuItem separatorItem]];
		}

		menuItem = [_openWithSubMenu itemAtIndex: 0];
		
		[menuItem setTitle:             [appURL displayName]];
		[menuItem setToolTip:           [appURL displayPath]];
		[menuItem setRepresentedObject: appURL];
		[menuItem setTarget:            self];
		[menuItem setAction:            @selector(openFile:)];
        // set icon
        {
            NSImage *icon = [appURL icon];
            [icon setSize:NSMakeSize(16,16)];
            [menuItem setImage: icon];
        }
        
		NSArray<NSURL*> *appURLs = [apps additionalAppURLs];
		for ( unsigned i = 0; i < [appURLs count]; i++ )
		{
			unsigned menuItemIndex = i+2;
			if ( menuItemIndex >= ((unsigned) [_openWithSubMenu numberOfItems]) )
				[_openWithSubMenu addItem: [[NSMenuItem alloc] init]];
			
			menuItem = [_openWithSubMenu itemAtIndex: menuItemIndex];
			appURL = [appURLs objectAtIndex: i];
			
			[menuItem setTitle:             [appURL displayName]];
			[menuItem setToolTip:           [appURL displayPath]];
			[menuItem setRepresentedObject: appURL];
			[menuItem setTarget:            self];
			[menuItem setAction:            @selector(openFile:)];
            
            NSImage *icon = [appURL icon];
            [icon setSize:NSMakeSize(16,16)];
            [menuItem setImage: icon];
		}
	}
	
	//remove any supernumerary menu items (removed all items if is there is no app which can open this file)
	unsigned removeMenuItemsFromIndex = ([apps defaultAppURL] != nil) ? [[apps additionalAppURLs] count] +2 : 0;
	
	while ( ((unsigned) [_openWithSubMenu numberOfItems]) > removeMenuItemsFromIndex )
		[_openWithSubMenu removeItemAtIndex: [_openWithSubMenu numberOfItems] -1];
}

#pragma mark -----------------service menu support-----------------------

- (id)validRequestorForSendType: (NSString *) sendType
					 returnType: (NSString *) returnType
{
	FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];
	
    if ( selectedItem != nil
		 && ![selectedItem isSpecialItem]
		 && [returnType length] == 0 //we don't accept any input, so returnType must be empty
		 && [selectedItem exists]
		 && [selectedItem supportsPasteboardType: sendType] )
	{
		return self;
    }
	
    return [super validRequestorForSendType: sendType returnType: returnType];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
							 types:(NSArray *)types
{
	FSItem *item = [(FileSystemDoc*)[self document] selectedItem];
	
	if ( item != nil && ![item isSpecialItem] )
	{
		[item writeToPasteboard: pboard withTypes: types];
		return YES;
	}
	else
		return NO;
}

@end

@implementation MainWindowController(Private)

- (void) moveToTrashSheetDidDismiss: (NSWindow *) sheet
						 returnCode: (int) returnCode
						contextInfo: (void*) contextInfo
{
	if ( returnCode != NSAlertAlternateReturn )
		return;
	
	FileSystemDoc *doc = [self document];
	FSItem *selectedItem = (__bridge FSItem*) contextInfo;
	
	NSParameterAssert(	selectedItem != nil
						&& selectedItem != [doc zoomedItem] 
						&& ![selectedItem isSpecialItem] );
	
	//before we move the file/folder to trash, we need to calculate the position of the poof effect
	NSRect cellRect;
	NSView *view = nil;
	if ( [[self window] firstResponder] == _filesOutlineView )
	{
		view = _filesOutlineView;
		cellRect = [_filesOutlineView frameOfCellAtColumn: 0 row: [_filesOutlineView selectedRow]];
	}
	else
	{
		view = _treeMapView;
		cellRect = [_treeMapView itemRectByPathToItem: [selectedItem fsItemPathFromAncestor: [doc zoomedItem]]];
	}
	
	//now we can do it
    NSError *error = nil;
    if ( [doc moveItemToTrash: selectedItem error:&error] )
	{
		[[self class] poofEffectInView: view inRect: cellRect];
		
        [self synchronizeWindowTitleWithDocumentName];
	}
	else
	{
		//failed
        NSString *msg = [NSString stringWithFormat: NSLocalizedString(@"\"%@\" cannot be moved to the trash by Disk Inventory Next.",@""), [selectedItem displayName] ];
        NSString *subMsg = error.localizedFailureReason; //NSLocalizedString( @"Maybe you do not have sufficient access privileges.", @"" );
        
        NSBeginInformationalAlertSheet( msg,
                                       NSLocalizedString(@"OK",@""),
                                       nil, nil,
                                       [self window],
                                       nil, NULL, NULL, nil,
                                       @"%@",
                                       subMsg );
 	}
}

@end
