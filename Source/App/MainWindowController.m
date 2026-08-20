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
#import "NSAlert-Extensions.h"
#import "InfoPanelController.h"
#import "Timing.h"
#import <TreeMapView/TreeMapView.h>
#import "FSItem-Utilities.h"
#import "FileSizeTransformer.h"
#import "AppsForItem.h"
#import "NSURL-Extensions.h"
#import "DIXSummaryStripView.h"
#import "DIXStatusBarView.h"
#import "DIXBreadcrumbView.h"
#import "DIXInspectorView.h"
#import "NSImage-Extensions.h"
#import "DIXTheme.h"

NSString *SelectionListVisibilityChangedNotification = @"SelectionListVisibilityChanged";

//Used the first time a pane is opened, when nothing has been remembered for it.
//The widths come from the design; DIXTheme holds them because the sidebar and
//the inspector are described there too.
#define kDefaultKindStatisticsWidth  ([DIXTheme sidebarWidth])
#define kDefaultFileListWidth        ([DIXTheme fileListWidth])

@interface MainWindowController()
- (void) setKindStatisticsVisible: (BOOL) visible animated: (BOOL) animated;
- (NSToolbarItem*) buildBreadcrumbItem;
- (NSToolbarItem*) buildViewModeItem;
- (NSToolbarItem*) buildInspectorToggleItem;
- (void) updateBreadcrumb;
- (void) updateBreadcrumbSizingItem: (NSToolbarItem*) item;
- (void) updateViewModeControl;
- (void) applyViewMode;
- (void) updateStatusBarHintForViewMode;
- (void) chooseInitialViewMode;
- (void) updateInspector;
- (void) placePaneDividers;
- (NSToolbarItem*) toolbarItemWithIdentifier: (NSString*) identifier;
- (void) animateKindStatisticsDividerTo: (CGFloat) targetWidth completion: (void (^)(void)) completion;
@end

@interface MainWindowController(Private)
- (void) moveItemToTrash: (FSItem*) selectedItem;
@end

@implementation MainWindowController

+ (void)initialize
{
    /* Make sure code only gets executed once. */
    static BOOL initialized = NO;
    if ( initialized )
		return;
    initialized = YES;
	
	//Initialise support for the service menu. NSPasteboardTypeFileURL has to be
	//here: registering only the legacy type meant no service that wants a file
	//URL ever offered itself, the same way dragging and copying used to fail.
    NSArray *sendTypes = @[ NSPasteboardTypeFileURL, FSItemLegacyFilenamesPasteboardType() ];
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
	poofEffectPoint = [[view window] convertPointToScreen: poofEffectPoint];
	
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
	//see -buildSidePanes: the widths are this window's to remember, not the
	//split view's, because the frame changes that follow would undo a restore
	[_splitter setDelegate: self];

	[self buildSidePanes];
}

#pragma mark -----------------side panes-----------------------

//Installs the two loose views the nib supplies as collapsible split-view panes:
//statistics to the left of the outline and treemap, selection list below them,
//which is where the drawers they replaced used to slide out from. The split
//views are built here rather than in the nib because four localized copies of a
//nested split layout would be four chances to get it subtly different.
- (void) buildSidePanes
{
	NSView *contentView = [[self window] contentView];

	if ( _kindStatisticsPane == nil || _selectionListPane == nil )
	{
		NSLog( @"side panes could not be built: the nib did not supply their views" );
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
	//No autosave name on this one, deliberately. NSSplitView restores its saved
	//positions when it is named, but this window then sets the split view's
	//frame twice - once to take over the splitter's space, once to squeeze it
	//between the summary strip and the status bar - and every frame change
	//redistributes the subviews in proportion, which overwrote what had just
	//been restored. The widths are kept in a default of this window's own
	//instead, and applied once the window has its real size.
	[_kindStatisticsSplitView setDelegate: self];

	[_splitter removeFromSuperview];

	[_selectionListSplitView addSubview: _splitter];
	[_selectionListSplitView addSubview: _selectionListPane];

	//A third column: statistics, the outline and map, then the inspector. The
	//inspector is a peer of the other two rather than a floating window, which
	//is the whole point - it describes the selection next to it instead of over
	//it, and cannot be left behind on another space.
	_inspectorView = [[DIXInspectorView alloc] initWithFrame: paneFrame];

	[_kindStatisticsSplitView addSubview: _kindStatisticsPane];
	[_kindStatisticsSplitView addSubview: _selectionListSplitView];
	[_kindStatisticsSplitView addSubview: _inspectorView];

	[_kindStatisticsSplitView setFrame: paneFrame];
	[_kindStatisticsSplitView setAutoresizingMask: paneMask];
	[contentView addSubview: _kindStatisticsSplitView];

	//the statistics drawer was opened at launch; the selection list was not
	[self setKindStatisticsVisible: YES];
	[self setSelectionListVisible: NO];

	[_inspectorView setTarget: self
				 revealAction: @selector(showInFinder:)
				   openAction: @selector(openFile:)
				  trashAction: @selector(moveToTrash:)];

	[self setInspectorVisible: YES];

	[self buildWindowChrome];
}

//Installs the two code-built chrome views as siblings of the nib's views:
//summary strip across the top of the content area, status bar along the bottom,
//with the split view squeezed between them.
- (void) buildWindowChrome
{
	NSView *contentView = [[self window] contentView];
	const NSRect contentBounds = [contentView bounds];

	const CGFloat statusHeight = [DIXStatusBarView preferredHeight];
	const CGFloat stripHeight  = [DIXSummaryStripView preferredHeight];

	_statusBarView = [[DIXStatusBarView alloc] initWithFrame:
		NSMakeRect( NSMinX( contentBounds ), NSMinY( contentBounds ),
					NSWidth( contentBounds ), statusHeight )];
	[_statusBarView setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
	[contentView addSubview: _statusBarView];

	_summaryStripView = [[DIXSummaryStripView alloc] initWithFrame:
		NSMakeRect( NSMinX( contentBounds ), NSMaxY( contentBounds ) - stripHeight,
					NSWidth( contentBounds ), stripHeight )];
	[_summaryStripView setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
	[contentView addSubview: _summaryStripView];

	//the split view now owns only the band between the two chrome views
	NSRect squeezed = contentBounds;
	squeezed.origin.y = statusHeight;
	squeezed.size.height = NSHeight( contentBounds ) - statusHeight - stripHeight;
	[_kindStatisticsSplitView setFrame: squeezed];

	//The status bar replaces the nib's two loose labels, which sat where it now
	//stands. They are not outlets on this controller - TreeMapViewController
	//owns them and no longer writes to them - so they are found by class: after
	//-buildSidePanes moved the splitter, the only NSTextFields left as direct
	//subviews are those two.
	for ( NSView *subview in [contentView subviews] )
	{
		if ( [subview isKindOfClass: [NSTextField class]] )
			[subview setHidden: YES];
	}

	//the strip's buttons drive the actions the menu already validates
	[_summaryStripView setTarget: self
					rescanAction: @selector(refreshAll:)
					zoomInAction: @selector(zoomIn:)
				   zoomOutAction: @selector(zoomOut:)];

	[_statusBarView setHint: NSLocalizedString( @"Click a block to select it", @"status bar hint" )];

	//Resynchronize the strip whenever the document changes underneath it. The
	//document can be nil here only if this controller was created without one;
	//object:nil would then observe every document, which the update tolerates
	//by re-reading its own.
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	FileSystemDoc *doc = [self document];

	[notificationCenter addObserver: self
						   selector: @selector(documentChangedForSummaryStrip:)
							   name: FSItemsChangedNotification
							 object: doc];
	[notificationCenter addObserver: self
						   selector: @selector(documentChangedForSummaryStrip:)
							   name: ZoomedItemChangedNotification
							 object: doc];
	[notificationCenter addObserver: self
						   selector: @selector(documentChangedForSummaryStrip:)
							   name: GlobalSelectionChangedNotification
							 object: doc];

	[self updateSummaryStrip];

	[self chooseInitialViewMode];
}

- (DIXStatusBarView*) statusBarView
{
	return _statusBarView;
}

#pragma mark -----------------the inspector-----------------------

//A hidden subview is how NSSplitView collapses a pane - it keeps the subview and
//gives it no space - which is the same mechanism the statistics pane uses.
- (BOOL) isInspectorVisible
{
	return _inspectorView != nil && ![_inspectorView isHidden];
}

- (void) setInspectorVisible: (BOOL) visible
{
	if ( _inspectorView == nil || visible == [self isInspectorVisible] )
		return;

	//Remember the width so reopening restores it: the split view's own autosave
	//records only a position it has been left at, and collapsing writes zero.
	if ( !visible )
		_inspectorWidth = NSWidth( [_inspectorView frame] );

	[_inspectorView setHidden: !visible];
	[_kindStatisticsSplitView adjustSubviews];

	if ( visible )
	{
		[self placePaneDividers];
		[self updateInspector];
	}
}

//Divider 0 sits after the statistics pane, divider 1 before the inspector. Both
//are placed rather than left to -adjustSubviews, which shares the width out in
//proportion and so gave the statistics pane less than its own column headers
//needed once there were three panes instead of two.
//Where the three column widths are remembered. One key rather than three, so a
//layout is written and read as a unit and a half-updated one cannot exist.
static NSString * const kPaneWidthsKey = @"MainWindowPaneWidths";

//Written whenever a divider settles. NSSplitView sends this during window
//resizes too, so widths are only recorded when every pane is showing and the
//figures are plausible - otherwise a collapsed pane would be remembered as
//zero and reopen at nothing.
- (void) splitViewDidResizeSubviews: (NSNotification*) notification
{
	id splitView = [notification object];

	if ( splitView != _kindStatisticsSplitView && splitView != _splitter )
		return;

	//Nothing is worth saving until the opening widths have been applied. The
	//split view resizes several times while the window is being assembled, and
	//saving then meant -placePaneDividers read back the arbitrary widths it was
	//about to correct, and so never applied a default at all.
	if ( !_paneWidthsPlaced )
		return;

	if ( ![self isKindStatisticsVisible] || ![self isInspectorVisible] )
		return;

	const CGFloat statistics = NSWidth( [_kindStatisticsPane frame] );
	const CGFloat fileList   = NSWidth( [[_filesOutlineView enclosingScrollView] frame] );
	const CGFloat inspector  = NSWidth( [_inspectorView frame] );

	if ( statistics < 1.0 || inspector < 1.0 )
		return;

	[[NSUserDefaults standardUserDefaults] setObject: @[ @(statistics), @(fileList), @(inspector) ]
											  forKey: kPaneWidthsKey];
}

- (void) placePaneDividers
{
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey: kPaneWidthsKey];
	const BOOL haveSaved = [saved count] == 3;

	CGFloat statistics = haveSaved ? [[saved objectAtIndex: 0] doubleValue]
								   : kDefaultKindStatisticsWidth;
	CGFloat fileList   = haveSaved ? [[saved objectAtIndex: 1] doubleValue]
								   : kDefaultFileListWidth;
	CGFloat inspector  = haveSaved ? [[saved objectAtIndex: 2] doubleValue]
								   : [DIXInspectorView preferredWidth];

	const CGFloat total = NSWidth( [_kindStatisticsSplitView bounds] );

	if ( total > 0.0 )
	{
		//A window narrower than the sum would otherwise leave the map with
		//nothing; the two side columns give way rather than the thing the
		//window is for.
		const CGFloat centreMinimum = 320.0;

		if ( statistics + inspector + centreMinimum > total )
		{
			const CGFloat share = ( total - centreMinimum ) / ( statistics + inspector );

			statistics = floor( statistics * MAX( share, 0.0 ) );
			inspector  = floor( inspector  * MAX( share, 0.0 ) );
		}

		//The inspector first: it is measured from the trailing edge, so placing
		//the statistics divider first would only move it again.
		if ( [self isInspectorVisible] )
			[_kindStatisticsSplitView setPosition: total - inspector ofDividerAtIndex: 1];

		if ( [self isKindStatisticsVisible] )
			[_kindStatisticsSplitView setPosition: statistics ofDividerAtIndex: 0];
	}

	//The outline against the map. Left to itself the split gave the outline
	//whatever was left after the treemap, which at the window's opening width
	//truncated every file name to an ellipsis.
	if ( [_splitter isVertical] && NSWidth( [_splitter bounds] ) > fileList * 2.0 )
		[_splitter setPosition: fileList ofDividerAtIndex: 0];

	//from here on the widths are the user's, and worth remembering
	_paneWidthsPlaced = YES;
}

- (IBAction) toggleInspector: (id) sender
{
	[self setInspectorVisible: ![self isInspectorVisible]];
}

- (void) updateInspector
{
	if ( ![self isInspectorVisible] )
		return;

	FileSystemDoc *doc = [self document];
	FSItem *item = [doc selectedItem];

	[_inspectorView setItem: item];

	//The same conditions -validateMenuItem: applies to the menu items these
	//buttons stand in for, so a button is never live when its menu item is not.
	const BOOL real = item != nil && ![item isSpecialItem];

	[_inspectorView setRevealEnabled: item != nil
						 openEnabled: real && [item exists]
						trashEnabled: real && item != [doc zoomedItem]];
}

#pragma mark -----------------toolbar items with custom views-----------------------

//Two of the toolbar's items are views rather than buttons, and the plist has no
//vocabulary for that - it describes an image, a label and an action. They are
//built here and everything else is left to ToolbarWindowController, which is
//also what keeps the generic class free of anything about this window.
- (NSToolbarItem*) toolbar: (NSToolbar*) toolbar
	 itemForItemIdentifier: (NSString*) identifier
 willBeInsertedIntoToolbar: (BOOL) willInsert
{
	if ( [identifier isEqualToString: @"Breadcrumb"] )
		return [self buildBreadcrumbItem];

	if ( [identifier isEqualToString: @"ViewMode"] )
		return [self buildViewModeItem];

	if ( [identifier isEqualToString: @"ToggleInspector"] )
		return [self buildInspectorToggleItem];

	return [super toolbar: toolbar
	itemForItemIdentifier: identifier
willBeInsertedIntoToolbar: willInsert];
}

- (NSToolbarItem*) buildBreadcrumbItem
{
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: @"Breadcrumb"];

	_breadcrumbView = [[DIXBreadcrumbView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, 240.0, 22.0 )];
	[_breadcrumbView setTarget: self action: @selector(zoomOutTo:)];

	[item setView: _breadcrumbView];

	//No label under it. The breadcrumb stands where the window title would be
	//and reads as a title; captioning it "Location" would be labelling the
	//title bar. The palette label is still set, since the customization sheet
	//has to call it something.
	[item setLabel: @""];
	[item setPaletteLabel: NSLocalizedString( @"Location", @"toolbar item label" )];

	//The breadcrumb stands in for the window title, so it should not also be
	//removable from the toolbar - a window with neither would say nowhere.
	[item setVisibilityPriority: NSToolbarItemVisibilityPriorityHigh];

	//Sized against the item in hand: -updateBreadcrumb looks the item up in the
	//toolbar, and at this point it has not been inserted yet.
	[self updateBreadcrumbSizingItem: item];

	return item;
}

//The right-hand counterpart of NSToolbarToggleSidebarItem. AppKit has no
//standard item for an inspector on macOS 11, so this is an ordinary one.
- (NSToolbarItem*) buildInspectorToggleItem
{
	ToolbarItem *item = [[ToolbarItem alloc] initWithItemIdentifier: @"ToggleInspector"];

	[item setLabel: NSLocalizedString( @"Inspector", @"toolbar item label" )];
	[item setPaletteLabel: [item label]];
	[item setToolTip: NSLocalizedString( @"Show or hide the inspector", @"toolbar item tooltip" )];
	[item setImage: [NSImage imageForSymbolName: @"sidebar.right"
					   accessibilityDescription: [item label]]];
	[item setTarget: self];
	[item setAction: @selector(toggleInspector:)];
	[item setDelegate: self];

	return item;
}

- (NSToolbarItem*) buildViewModeItem
{
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: @"ViewMode"];

	_viewModeControl = [NSSegmentedControl segmentedControlWithLabels:
		@[ NSLocalizedString( @"Map",  @"view mode" ),
		   NSLocalizedString( @"List", @"view mode" ),
		   NSLocalizedString( @"Both", @"view mode" ) ]
								   trackingMode: NSSegmentSwitchTrackingSelectOne
										 target: self
										 action: @selector(changeViewMode:)];

	[_viewModeControl setTranslatesAutoresizingMaskIntoConstraints: YES];
	[_viewModeControl sizeToFit];

	[item setView: _viewModeControl];
	[item setLabel: NSLocalizedString( @"View", @"toolbar item label" )];
	[item setPaletteLabel: [item label]];

	[self updateViewModeControl];

	return item;
}

//"Macintosh HD › Users › derek › Movies". The zoom stack holds what has been
//zoomed into; the root is not on it, and is prepended here because it is where
//the scan began and the one place you always want to be able to get back to.
- (void) updateBreadcrumb
{
	[self updateBreadcrumbSizingItem: nil];
}

//"item" is the toolbar item to resize, or nil to find it in the toolbar.
- (void) updateBreadcrumbSizingItem: (NSToolbarItem*) item
{
	FileSystemDoc *doc = [self document];
	FSItem *rootItem = [doc rootItem];

	if ( _breadcrumbView == nil || rootItem == nil )
		return;

	NSMutableArray<NSString*> *titles = [NSMutableArray array];
	NSMutableArray *items = [NSMutableArray array];

	[titles addObject: [rootItem displayName]];
	[items addObject: rootItem];

	for ( FSItem *item in [doc zoomStack] )
	{
		[titles addObject: [item displayName]];
		[items addObject: item];
	}

	[_breadcrumbView setSegmentTitles: titles representedObjects: items];

	//The item's own width has to follow the path, or a deep breadcrumb is
	//clipped to whatever width it was built at.
	const CGFloat width = [_breadcrumbView fittingWidth];
	const NSSize size = NSMakeSize( width, 22.0 );

	NSRect frame = [_breadcrumbView frame];
	frame.size = size;
	[_breadcrumbView setFrame: frame];

	//A view-based toolbar item does not measure its own view. -minSize/-maxSize
	//are formally deprecated in favour of Auto Layout, but they are what works
	//against a hand-laid-out view on the macOS 11 deployment target, and the
	//alternative would put constraints in this window for one label's width.
	if ( item == nil )
		item = [self toolbarItemWithIdentifier: @"Breadcrumb"];

	[item setMinSize: size];
	[item setMaxSize: size];
}

- (NSToolbarItem*) toolbarItemWithIdentifier: (NSString*) identifier
{
	for ( NSToolbarItem *item in [[[self window] toolbar] items] )
	{
		if ( [[item itemIdentifier] isEqualToString: identifier] )
			return item;
	}

	return nil;
}

//The toolbar carries the breadcrumb, which is a title, so the window's own
//title is turned off rather than repeated beside it. Icon-only is the design's
//toolbar: glyphs with no captions, which is also what leaves the breadcrumb
//room to grow.
- (void) windowDidLoad
{
	[super windowDidLoad];

	//Deferred one turn of the run loop. The panes are built during
	//-awakeFromNib, when the window is still the nib's 572 points wide, and
	//even here it has not finished taking up its autosaved frame - measured,
	//the split view was 530 points across at this point and 1430 by the time
	//the window was on screen. A divider placed against the smaller figure is
	//then redistributed in proportion, which put a 300pt inspector at 640.
	//
	//Once only: after this the split views' own autosave owns the layout, and
	//placing the dividers again would undo a width the user had dragged to.
	__weak MainWindowController *weakSelf = self;

	dispatch_async( dispatch_get_main_queue(), ^{
		[weakSelf placePaneDividers];
	});

	[[self window] setTitleVisibility: NSWindowTitleHidden];
	[[[self window] toolbar] setDisplayMode: NSToolbarDisplayModeIconOnly];
}

#pragma mark -----------------view modes-----------------------

- (IBAction) changeViewMode: (id) sender
{
	const NSInteger selected = [sender selectedSegment];

	if ( selected < 0 )
		return;

	[[self document] setViewMode: (DIXViewMode) selected];

	[self applyViewMode];
}

- (void) updateViewModeControl
{
	[_viewModeControl setSelectedSegment: (NSInteger) [[self document] viewMode]];
}

//The window has held the outline and the treemap side by side in one split view
//since 2003 - that arrangement is already "Both". A mode is therefore not a new
//layout but which of the two gets space, and NSSplitView gives a hidden subview
//none, exactly as it does for the collapsible side panes.
- (void) applyViewMode
{
	NSView *outlineView = [_filesOutlineView enclosingScrollView];

	if ( outlineView == nil || _treeMapView == nil )
		return;

	const DIXViewMode mode = [[self document] viewMode];

	[outlineView setHidden: ( mode == DIXViewModeMap )];
	[_treeMapView setHidden: ( mode == DIXViewModeList )];

	[_splitter adjustSubviews];

	[self updateViewModeControl];
	[self updateStatusBarHintForViewMode];
}

- (void) updateStatusBarHintForViewMode
{
	if ( _statusBarView == nil )
		return;

	//The hint describes what is actually on screen. It does not promise the
	//design's area-drag or Quick Look, neither of which exists yet.
	NSString *hint = ( [[self document] viewMode] == DIXViewModeList )
		? NSLocalizedString( @"Select a row to see what it holds", @"status bar hint" )
		: NSLocalizedString( @"Click a block to select it", @"status bar hint" );

	[_statusBarView setHint: hint];
}

//Both is the default when the window is wide enough to hold the outline and a
//usable map; below that it falls back to Map, because two cramped columns are
//worse than one good one. Only chosen at load - once the mode has been set from
//the toolbar it is the document's and is left alone.
- (void) chooseInitialViewMode
{
	const CGFloat contentWidth = NSWidth( [[[self window] contentView] bounds] );

	[[self document] setViewMode: ( contentWidth >= [DIXTheme bothModeMinimumContentWidth] )
								  ? DIXViewModeBoth : DIXViewModeMap];

	[self applyViewMode];
}

- (void) documentChangedForSummaryStrip: (NSNotification*) notification
{
	[self updateSummaryStrip];

	//the breadcrumb is the zoom stack, so it follows the same notifications
	[self updateBreadcrumb];

	[self updateInspector];
}

//Feeds the summary strip from the document: the total, what it is made of and
//how fresh it is, plus the enabled state of the two zoom buttons. Called once
//after load and again whenever the items, the zoom or the selection change.
- (void) updateSummaryStrip
{
	FileSystemDoc *doc = [self document];
	FSItem *rootItem = [doc rootItem];

	if ( _summaryStripView == nil || rootItem == nil )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	NSNumberFormatter *countFormatter = [[NSNumberFormatter alloc] init];
	[countFormatter setNumberStyle: NSNumberFormatterDecimalStyle];

	//"scanned 2 minutes ago"; anything under a minute is simply "now", because
	//"37 seconds ago" is more precision than the statement carries
	NSRelativeDateTimeFormatter *whenFormatter = [[NSRelativeDateTimeFormatter alloc] init];
	[whenFormatter setDateTimeStyle: NSRelativeDateTimeFormatterStyleNamed];

	NSDate *scannedAt = [doc scanCompletedAt];
	NSTimeInterval age = scannedAt != nil ? -[scannedAt timeIntervalSinceNow] : 0;

	NSString *scanned = [whenFormatter localizedStringFromTimeInterval: age < 60 ? 0 : -age];

	NSString *subtitle = [NSString stringWithFormat:
		NSLocalizedString( @"%@ files · %@ folders · scanned %@", @"summary strip subtitle" ),
		[countFormatter stringFromNumber: @( [doc fileCount] )],
		[countFormatter stringFromNumber: @( [doc folderCount] )],
		scanned];

	[_summaryStripView setTotal: [sizeFormatter stringForObjectValue: [rootItem size]]
					   subtitle: subtitle];

	//no scan history yet, so there is nothing truthful to say about growth
	[_summaryStripView setDelta: nil caption: nil isGrowth: YES];

	//the same conditions -validateMenuItem: applies to the zoom menu items
	FSItem *selectedItem = [doc selectedItem];
	[_summaryStripView setZoomInEnabled: selectedItem != nil && [selectedItem isFolder]
						 zoomOutEnabled: [doc rootItem] != [doc zoomedItem]];
}

//A hidden subview is how NSSplitView collapses a pane: it keeps the subview and
//its constraints but gives it no space, which is what the drawers did visually.
- (BOOL) isKindStatisticsVisible
{
	return _kindStatisticsPane != nil && ![_kindStatisticsPane isHidden];
}

- (void) setKindStatisticsVisible: (BOOL) visible
{
	[self setKindStatisticsVisible: visible animated: NO];
}

//NSSplitView collapses a pane by hiding the subview: it keeps the subview and
//its constraints but gives it no space. That is instantaneous, so the animated
//path slides the divider first and only then hides the pane, since a hidden
//subview has no width to animate from.
- (void) setKindStatisticsVisible: (BOOL) visible animated: (BOOL) animated
{
	if ( _kindStatisticsPane == nil || visible == [self isKindStatisticsVisible] )
		return;

	if ( !animated || ![[self window] isVisible] )
	{
		[_kindStatisticsPane setHidden: !visible];
		[_kindStatisticsSplitView adjustSubviews];
		return;
	}

	//Remember the width so reopening restores it. The split view's own autosave
	//only records a position it has been left at, and collapsing writes zero.
	if ( !visible )
		_kindStatisticsWidth = NSWidth( [_kindStatisticsPane frame] );

	const CGFloat targetWidth = visible ? ( _kindStatisticsWidth > 0.0 ? _kindStatisticsWidth
																	  : kDefaultKindStatisticsWidth )
										: 0.0;

	if ( visible )
	{
		//give it a zero-width starting point to grow from
		[_kindStatisticsPane setHidden: NO];
		_animatingKindStatistics = YES;
		[_kindStatisticsSplitView setPosition: 0.0 ofDividerAtIndex: 0];
	}

	[self animateKindStatisticsDividerTo: targetWidth completion: ^
	{
		//Collapse for real at the end. Leaving the pane at zero width would keep
		//the divider draggable and -isKindStatisticsVisible would still say YES.
		if ( !visible )
		{
			[self->_kindStatisticsPane setHidden: YES];
			[self->_kindStatisticsSplitView adjustSubviews];
		}
	}];
}

//NSSplitView's -setPosition:ofDividerAtIndex: is not animatable: going through
//the -animator proxy sets it immediately, which a probe caught by sampling the
//pane width midway and finding it already at the target. So the divider is
//stepped by a timer instead.
//
//The timer is held so it can be stopped if the window goes away mid-slide -
//NSTimer retains its target, and a repeating one that is never invalidated
//would keep this controller alive.
- (void) animateKindStatisticsDividerTo: (CGFloat) targetWidth completion: (void (^)(void)) completion
{
	[_kindStatisticsAnimationTimer invalidate];

	const CGFloat startWidth = NSWidth( [_kindStatisticsPane frame] );
	const NSTimeInterval duration = 0.18;
	NSDate *startedAt = [NSDate date];

	_animatingKindStatistics = YES;

	__weak MainWindowController *weakSelf = self;

	_kindStatisticsAnimationTimer =
		[NSTimer scheduledTimerWithTimeInterval: 1.0 / 60.0
										repeats: YES
										  block: ^( NSTimer *timer )
	{
		MainWindowController *strongSelf = weakSelf;
		if ( strongSelf == nil )
		{
			[timer invalidate];
			return;
		}

		double progress = -[startedAt timeIntervalSinceNow] / duration;
		if ( progress > 1.0 )
			progress = 1.0;

		//smoothstep, so it eases in and out without needing CAMediaTimingFunction
		const double eased = progress * progress * ( 3.0 - 2.0 * progress );

		[strongSelf->_kindStatisticsSplitView setPosition: startWidth + ( targetWidth - startWidth ) * eased
										 ofDividerAtIndex: 0];

		if ( progress >= 1.0 )
		{
			[timer invalidate];
			strongSelf->_kindStatisticsAnimationTimer = nil;
			strongSelf->_animatingKindStatistics = NO;

			if ( completion != nil )
				completion();
		}
	}];
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
	if ( splitView != _kindStatisticsSplitView )
		return proposedMin;

	//Divider 1 is the one before the inspector; dragging it left is what makes
	//the inspector wider, so its minimum is what keeps the centre usable.
	if ( dividerIndex == 1 )
		return MAX( proposedMin, NSMinX( [_selectionListSplitView frame] ) + 320.0 );

	//The minimum keeps the pane usable rather than letting it be dragged to a
	//sliver, but it has to be lifted while collapsing or the slide would stop
	//dead at 120 points instead of reaching zero.
	if ( !_animatingKindStatistics )
		return MAX( proposedMin, 120.0 );

	return proposedMin;
}

- (CGFloat) splitView: (NSSplitView*) splitView
constrainMaxCoordinate: (CGFloat) proposedMax
		  ofSubviewAt: (NSInteger) dividerIndex
{
	if ( splitView != _kindStatisticsSplitView )
		return MIN( proposedMax, NSHeight([splitView bounds]) - 150.0 );

	//Below this the inspector's two-column attribute grid stops being readable,
	//and its three header buttons start truncating their titles.
	if ( dividerIndex == 1 )
		return MIN( proposedMax, NSWidth([splitView bounds]) - 220.0 );

	//and leave room for the outline and treemap
	return MIN( proposedMax, NSWidth([splitView bounds]) - 250.0 );
}

#pragma mark -----------------menu and toolbar actions-----------------------

//named for the drawers they used to toggle, because the main menu nib and
//MainWindowToolbar.toolbar refer to these selectors by name
- (IBAction)toggleFileKindsDrawer:(id)sender
{
    [self setKindStatisticsVisible: ![self isKindStatisticsVisible] animated: YES];
}

//NSToolbarToggleSidebarItemIdentifier sends -toggleSidebar: to the first
//responder, so the window controller picks it up off the responder chain. The
//statistics pane is the leading subview of the outer split view, which is what
//the platform means by a sidebar.
- (IBAction) toggleSidebar:(id)sender
{
	[self setKindStatisticsVisible: ![self isKindStatisticsVisible] animated: YES];
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

	//The root is a legitimate destination and is deliberately not on the zoom
	//stack, which holds only what has been zoomed *into*. -zoomOutToItem: has
	//always accepted it; this assertion did not, so zooming all the way out
	//tripped it in debug builds - reachable from the zoom-stack menu, whose
	//first entry is the root, and now from the breadcrumb's first segment.
	NSAssert( item == [doc rootItem]
			  || [[doc zoomStack] indexOfObjectIdenticalTo: item] != NSNotFound,
			  @"item is neither the root nor on the zoom stack" );
	
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

		NSAlert *alert = [[NSAlert alloc] init];

		[alert setMessageText: msg];
		[alert setInformativeText: NSLocalizedString(@"Would you like to delete it immediately?",@"")];

		//"No" is added first, so it is the rightmost and default button: this
		//sheet guards deleting a file outright, and the return key must not do
		//that. NSBeginAlertSheet's first button title had the same role, and its
		//"Yes" was the alternate button the old callback tested for.
		[alert addButtonWithTitle: NSLocalizedString(@"No",@"")];
		[alert addButtonWithTitle: NSLocalizedString(@"Yes",@"")];

		[alert beginSheetModalForWindow: [self window]
					  completionHandler: ^( NSModalResponse returnCode )
		{
			if ( returnCode == NSAlertSecondButtonReturn )
				[self moveItemToTrash: selectedItem];
		}];
	}
	else
	{
		[self moveItemToTrash: selectedItem];
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
	[NSAlert showInformationalSheetWithMessage: msg explanation: nil forWindow: [_splitter window]];
}

- (IBAction) performLayoutBenchmark:(id)sender
{
	uint64_t startTime = getTime();
	
	unsigned count = 100;
	
	[_treeMapView benchmarkLayoutCalculationWithImageSize: NSMakeSize( 1024, 768 ) count: count];
	
	uint64_t doneTime = getTime();
	
	NSString *msg = [NSString stringWithFormat: @"layout calculation %u times took %.2f seconds", count, subtractTime(doneTime, startTime)];
	[NSAlert showInformationalSheetWithMessage: msg explanation: nil forWindow: [_splitter window]];
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
		 [menuItem setState: (condition) ? NSControlStateValueOff : NSControlStateValueOn];
	
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

//Bumped when the drawer toggle gave way to the standard sidebar item and every
//icon became an SF Symbol: a layout saved before that refers to items which no
//longer exist, and would come back missing the sidebar button entirely.
//
//Bumped again for the breadcrumb and the view-mode control. An existing user's
//saved layout has neither, and since the breadcrumb stands in for the window
//title they would otherwise be left with a window that never says where it is.
- (NSString *)toolbarAutosaveIdentifier
{
    return @"MainWindowToolbar-3";
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
	//A repeating NSTimer retains its target, so a slide still in flight would
	//keep this controller — and the document behind it — alive.
	[_kindStatisticsAnimationTimer invalidate];
	_kindStatisticsAnimationTimer = nil;
	_animatingKindStatistics = NO;

	//the summary strip observers registered in -buildWindowChrome
	[[NSNotificationCenter defaultCenter] removeObserver: self];

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
	NSUInteger removeMenuItemsFromIndex = ([apps defaultAppURL] != nil) ? [[apps additionalAppURLs] count] +2 : 0;
	
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

//Was -moveToTrashSheetDidDismiss:returnCode:contextInfo:. The confirmation is
//now an NSAlert completion handler, which can capture the item directly, so the
//return code and the bridged void* context are both gone.
- (void) moveItemToTrash: (FSItem*) selectedItem
{
	FileSystemDoc *doc = [self document];

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
        
        [NSAlert showInformationalSheetWithMessage: msg explanation: subMsg forWindow: [self window]];
 	}
}

@end
