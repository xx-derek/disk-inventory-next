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
#import "DIXSourcesView.h"
#import "DIXKindsView.h"
#import "DIXVolumeList.h"
#import "DIXRecentScans.h"
#import "NSImage-Extensions.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "DIXChangesController.h"
#import "DIXPrivacyBannerView.h"
#import "DonationPanelController.h"


//Used the first time a pane is opened, when nothing has been remembered for it.
//The widths come from the design; DIXTheme holds them because the sidebar and
//the inspector are described there too.
#define kDefaultKindStatisticsWidth  ([DIXTheme sidebarWidth])
#define kDefaultFileListWidth        ([DIXTheme fileListWidth])

@interface MainWindowController() <DIXChangesDelegate>
- (void) setKindStatisticsVisible: (BOOL) visible animated: (BOOL) animated;
- (IBAction) showWhatChanged: (id) sender;
- (void) updatePrivacyBanner;
- (CGFloat) privacyBannerHeight;
- (void) installTrailingAccessory;
- (void) layoutTrailingAccessory;
- (NSSearchField*) buildSearchField;
- (IBAction) showSearchScopeMenu: (id) sender;
- (void) updateInspectorButtonState;
- (void) updateSearchScopeMenu;
- (void) installTitleAccessory;
- (void) colourTitleBar;
- (void) layoutTitleBarBand;
- (void) updateBreadcrumb;
- (void) layoutTitleAccessory;
- (void) updateViewModeControl;
- (void) applyViewMode;
- (CGFloat) preferredFileListWidth;
- (void) updateStatusBarHintForViewMode;
- (void) chooseInitialViewMode;
- (void) updateInspector;
- (void) placeSummaryStrip;
- (void) updateSummarySubtitle;
- (void) updateSummaryDelta;
- (void) startSummaryAgeClock;
- (CGFloat) minimumCentreColumnWidth;
- (void) setPaneWidthsSettled: (BOOL) settled;
- (void) placePaneDividers;
- (void) animateKindStatisticsDividerTo: (CGFloat) targetWidth completion: (void (^)(void)) completion;
- (void) animateInspectorToWidth: (CGFloat) targetWidth completion: (void (^)(void)) completion;
@end

@interface MainWindowController(Private)
- (void) moveItemToTrash: (FSItem*) selectedItem;
@end

//The caption under the file list. The design gives it 30pt, a hairline along
//its top and the chrome tone, and says what the coloured square in each row is
//for - which nothing else in the window explains.
@interface DIXListFooterView : NSView
@end

@implementation DIXListFooterView

- (void) drawRect: (NSRect) dirtyRect
{
	const NSRect bounds = [self bounds];

	[[DIXTheme chrome] set];
	NSRectFill( NSIntersectionRect( dirtyRect, bounds ) );

	//the lighter content weight, as everywhere a band meets a pane
	NSRect line = bounds;
	line.origin.y = NSMaxY( bounds ) - [DIXTheme hairlineThickness];
	line.size.height = [DIXTheme hairlineThickness];

	[[DIXTheme contentHairline] set];
	NSRectFill( NSIntersectionRect( line, dirtyRect ) );
}

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
	
	//The nib's split view carries AppKit's old 9pt divider, which put a band of
	//window background down the right-hand side of the file list. The design
	//separates the list from the map with a line, not a gap, and the sidebar's
	//split view is already thin.
	[_splitter setDividerStyle: NSSplitViewDividerStyleThin];

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
//SOURCES takes exactly the height its rows need and the statistics take the
//rest. Frames rather than constraints, like the rest of this window's chrome.
- (void) layoutSidebarPane
{
	//Between the two sections, at the design's margins: 16 above the rule and 8
	//below it, inset 14 either side. SOURCES already ends with 14 points of its
	//own padding, so 2 more here makes the 16.
	static const CGFloat kRuleInset    = 14.0;
	static const CGFloat kRuleGapAbove =  2.0;
	static const CGFloat kRuleGapBelow =  8.0;

	if ( _sidebarPane == nil || _sourcesView == nil )
		return;

	const NSRect bounds = [_sidebarPane bounds];
	const CGFloat ruleThickness = [DIXTheme ruleThickness];

	//What the section wants, and what it may have. Over about half the pane it
	//would leave the kinds legend a sliver, so past that the folder list inside
	//it scrolls - the volumes and Choose Folder do not, so the section is given
	//a height and lays itself out within it.
	const CGFloat wanted = [_sourcesView fittingHeight];
	const CGFloat allowed = MAX( 0.0, floor( NSHeight( bounds ) * 0.55 ) );
	const CGFloat sourcesHeight = MIN( wanted, allowed );

	[_sourcesView setFrame: NSMakeRect( 0.0, NSMaxY( bounds ) - sourcesHeight,
										NSWidth( bounds ), sourcesHeight )];

	const CGFloat ruleY = NSMaxY( bounds ) - sourcesHeight - kRuleGapAbove - ruleThickness;

	[_sectionRule setFrame: NSMakeRect( kRuleInset, ruleY,
										MAX( 0.0, NSWidth( bounds ) - kRuleInset * 2.0 ),
										ruleThickness )];

	[_kindsView setFrame: NSMakeRect( 0.0, 0.0,
									  NSWidth( bounds ),
									  MAX( 0.0, ruleY - kRuleGapBelow ) )];
}

- (void) onVolumeListChanged: (NSNotification*) notification
{
	[self layoutSidebarPane];
}

- (void) onSidebarPaneResized: (NSNotification*) notification
{
	[self layoutSidebarPane];
}

//Deferred one turn, and not for the usual reason. DIXSourcesView observes this
//notification too, to rebuild its rows; -layoutSidebarPane then asks it how
//tall it wants to be. NSNotificationCenter does not promise which of the two
//gets it first, so asking immediately can read the height the section had
//before the row went - which would leave exactly the gap this is fixing.
- (void) onRecentScansChanged: (NSNotification*) notification
{
	__weak MainWindowController *weakSelf = self;

	dispatch_async( dispatch_get_main_queue(), ^{ [weakSelf layoutSidebarPane]; } );
}
- (void) buildSidePanes
{
	NSView *contentView = [[self window] contentView];

	if ( _kindStatisticsPane == nil )
	{
		NSLog( @"side panes could not be built: the nib did not supply their views" );
		return;
	}

	//The selection list is retired: the inspector's sibling list answers "what
	//else is like this" and the toolbar's search field answers "where is it".
	//The nib still builds the pane and its controllers - taking those out is a
	//structural edit to four TreeMap.nibs, which belongs with the rest of the nib
	//work - so it is unparented here rather than left somewhere it might show.
	[_selectionListPane removeFromSuperview];

	//Take over exactly the space the outline/treemap splitter occupied, not the
	//whole content view: the treemap's name and size labels live below it, and
	//filling the content view would cover them.
	const NSRect paneFrame = [_splitter frame];
	const NSAutoresizingMaskOptions paneMask = [_splitter autoresizingMask];

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

	[_splitter removeFromSuperview];

	//The middle column of the three. The summary strip and the status bar belong
	//to it rather than to the window, which is what lets the sidebar and the
	//inspector run the full height beside them - in the design they start under
	//the title bar and finish at the window's bottom edge. The split view still
	//sees exactly one subview per column, so none of the divider logic changes.
	_centreColumn = [[NSView alloc] initWithFrame: paneFrame];
	[_centreColumn setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

	[_splitter setFrame: [_centreColumn bounds]];
	[_splitter setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
	[_centreColumn addSubview: _splitter];

	//A third column: statistics, the outline and map, then the inspector. The
	//inspector is a peer of the other two rather than a floating window, which
	//is the whole point - it describes the selection next to it instead of over
	//it, and cannot be left behind on another space.
	_inspectorView = [[DIXInspectorView alloc] initWithFrame: paneFrame];

	//SOURCES sits above the kind statistics in the same column. The nib's view
	//keeps its job and its outlet; it just no longer starts at the top.
	_sourcesView = [[DIXSourcesView alloc] initWithFrame: NSZeroRect];

	//The nib's kind-statistics view is left behind here rather than reparented:
	//it is a headered, cell-based NSTableView driven by two NSArrayControllers,
	//and the legend replacing it is neither. The nib still builds it - the nib
	//goes as a whole in the last step of this phase - it simply is not shown.
	_kindsView = [[DIXKindsView alloc] initWithFrame: NSZeroRect];

	//The 2pt rule between SOURCES and FILE KINDS. It belongs to neither view -
	//it is the boundary between them - so the pane that holds both draws it.
	_sectionRule = [DIXControls sectionRule];

	//Every other view in this pane carries a mask; without one the rule kept
	//whatever frame it was first given. -buildSidePanes runs while the pane is
	//still the nib's size, so the rule was laid out against that and then left
	//behind when the split view resized the pane - invisible until something
	//else called -layoutSidebarPane. What eventually did was DIXSourcesView's
	//five-second free-space timer, which is why it appeared seconds after the
	//window opened and lagged a divider drag by up to five more.
	[_sectionRule setAutoresizingMask: ( NSViewWidthSizable | NSViewMinYMargin )];

	_sidebarPane = [[NSView alloc] initWithFrame: [_kindStatisticsPane frame]];
	[_sidebarPane addSubview: _sourcesView];
	[_sidebarPane addSubview: _sectionRule];
	[_sidebarPane addSubview: _kindsView];

	[_sourcesView setAutoresizingMask: ( NSViewWidthSizable | NSViewMinYMargin )];
	[_kindsView setAutoresizingMask: ( NSViewWidthSizable | NSViewHeightSizable )];

	[_kindsView setDocument: (FileSystemDoc*) [self document]];

	//The mask keeps the rule in place through a resize; this keeps it correct
	//when the *contents* move under it - SOURCES grows a row and everything
	//below it shifts - and makes a drag track instead of settling afterwards.
	[_sidebarPane setPostsFrameChangedNotifications: YES];

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(onSidebarPaneResized:)
												 name: NSViewFrameDidChangeNotification
											   object: _sidebarPane];

	[self layoutSidebarPane];

	//mounting or unmounting changes how tall SOURCES needs to be, and the
	//statistics below it have to give up or take back the difference
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(onVolumeListChanged:)
												 name: DIXVolumeListChangedNotification
											   object: nil];

	//Forgetting a folder, or scanning a new one, changes how tall SOURCES needs
	//to be just as mounting a volume does. Without this the section kept its
	//old height until the next volume refresh - up to five seconds later, which
	//is what "takes some time before layout updates" was.
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(onRecentScansChanged:)
												 name: DIXRecentScansChangedNotification
											   object: nil];

	[_kindStatisticsSplitView addSubview: _sidebarPane];
	[_kindStatisticsSplitView addSubview: _centreColumn];
	[_kindStatisticsSplitView addSubview: _inspectorView];

	[_kindStatisticsSplitView setFrame: paneFrame];
	[_kindStatisticsSplitView setAutoresizingMask: paneMask];
	[contentView addSubview: _kindStatisticsSplitView];

	[self setKindStatisticsVisible: YES];

	[_inspectorView setDocument: (FileSystemDoc*) [self document]];

	[_inspectorView setTarget: self
				 revealAction: @selector(showInFinder:)
				   openAction: @selector(openFile:)
				  trashAction: @selector(moveToTrash:)];

	[_inspectorView setReclaimTarget: self action: @selector(reclaimBasket:)];

	[self setInspectorVisible: YES];

	[self buildWindowChrome];
}

//Installs the two code-built chrome views inside the middle column: summary
//strip across its top, status bar along its bottom, with the outline/treemap
//split squeezed between them. The sidebar and the inspector are unaffected and
//keep the window's full height, which is how the design draws all three.
- (void) buildWindowChrome
{
	NSView *contentView = [[self window] contentView];
	const NSRect contentBounds = [contentView bounds];

	//The status bar replaces the nib's two loose labels, which sat below the
	//splitter. They are not outlets on this controller - TreeMapViewController
	//owns them and no longer writes to them - so they are found by class: after
	//-buildSidePanes moved the splitter, the only NSTextFields left as direct
	//subviews are those two.
	//
	//Done before the split view is expanded over them, because that is what
	//makes the space they occupied safe to take.
	for ( NSView *subview in [contentView subviews] )
	{
		if ( [subview isKindOfClass: [NSTextField class]] )
			[subview setHidden: YES];
	}

	//The columns now run the whole content view. -buildSidePanes could only take
	//the splitter's own frame, because those two labels were still showing below
	//it; with them hidden the space is free, and the sidebar and inspector need
	//it to reach the bottom of the window.
	[_kindStatisticsSplitView setFrame: contentBounds];
	[_kindStatisticsSplitView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

	const NSRect columnBounds = [_centreColumn bounds];

	const CGFloat statusHeight = [DIXStatusBarView preferredHeight];
	const CGFloat stripHeight  = [DIXSummaryStripView preferredHeight];

	_statusBarView = [[DIXStatusBarView alloc] initWithFrame:
		NSMakeRect( NSMinX( columnBounds ), NSMinY( columnBounds ),
					NSWidth( columnBounds ), statusHeight )];
	[_statusBarView setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];

	_summaryStripView = [[DIXSummaryStripView alloc] initWithFrame:
		NSMakeRect( NSMinX( columnBounds ), NSMaxY( columnBounds ) - stripHeight,
					NSWidth( columnBounds ), stripHeight )];
	[_summaryStripView setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];

	//A column for the map, so the summary can sit above it rather than above
	//both panes. The design runs the file list from the top of the window - it
	//is a column of its own, headed by Name/Size/Share - while the total and
	//the buttons that act on the map belong over the map.
	//
	//The split view sees one subview per pane either way, so nothing about the
	//dividers changes; what was the treemap is now the column holding it.
	_mapColumn = [[NSView alloc] initWithFrame: [_treeMapView frame]];
	[_mapColumn setAutoresizingMask: [_treeMapView autoresizingMask]];

	[_splitter replaceSubview: _treeMapView with: _mapColumn];

	[_treeMapView setFrame: [_mapColumn bounds]];
	[_treeMapView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
	[_mapColumn addSubview: _treeMapView];

	//And the same for the list, which the design captions rather than leaves
	//bare: "Chip = the kind filling the row · click to find it on the map" is
	//the only thing that says what the coloured square in a row means.
	NSView *listScrollView = [_filesOutlineView enclosingScrollView];

	_listColumn = [[NSView alloc] initWithFrame: [listScrollView frame]];
	[_listColumn setAutoresizingMask: [listScrollView autoresizingMask]];

	[_splitter replaceSubview: listScrollView with: _listColumn];

	_listFooterView = [[DIXListFooterView alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, NSWidth( [_listColumn bounds] ), kListFooterHeight )];
	[_listFooterView setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];

	NSTextField *caption = [NSTextField labelWithString: NSLocalizedString(
		@"Chip = the kind filling the row · click to find it on the map",
		@"file list footer" )];

	[caption setFont: [NSFont systemFontOfSize: 11.0]];
	[caption setTextColor: [DIXTheme tertiaryText]];
	[caption sizeToFit];
	[caption setFrameOrigin: NSMakePoint( kListFooterPadding,
										  round( ( kListFooterHeight - NSHeight( [caption frame] ) ) / 2.0 ) )];
	[caption setAutoresizingMask: NSViewMaxXMargin];
	[_listFooterView addSubview: caption];

	[listScrollView setFrame: NSMakeRect( 0.0, kListFooterHeight,
										  NSWidth( [_listColumn bounds] ),
										  NSHeight( [_listColumn bounds] ) - kListFooterHeight )];
	[listScrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

	[_listColumn addSubview: listScrollView];
	[_listColumn addSubview: _listFooterView];

	//the outline/map split owns the whole column; the strip and the status bar
	//are inside it, over and under the map's half - see -placeSummaryStrip
	[_splitter setFrame: columnBounds];

	[self placeSummaryStrip];

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
	[notificationCenter addObserver: self
						   selector: @selector(documentChangedForSummaryStrip:)
							   name: FocusedPileChangedNotification
							 object: doc];

	[self updateSummaryStrip];
	[self startSummaryAgeClock];

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
	[self setInspectorVisible: visible animated: NO];
}

//Slid rather than switched, like the sidebar. The timer is the sidebar's story
//again: -setPosition:ofDividerAtIndex: is not animatable, and going through the
//-animator proxy sets it immediately.
- (void) animateInspectorToWidth: (CGFloat) targetWidth completion: (void (^)(void)) completion
{
	[_inspectorAnimationTimer invalidate];

	const CGFloat startWidth = NSWidth( [_inspectorView frame] );
	const NSTimeInterval duration = 0.18;
	NSDate *startedAt = [NSDate date];

	//held for the whole slide, so the pane's minimum width does not stop it
	//short of the edge
	_collapsingInspector = YES;

	__weak MainWindowController *weakSelf = self;

	_inspectorAnimationTimer =
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

		//smoothstep, the same easing the sidebar slides on
		const double eased = progress * progress * ( 3.0 - 2.0 * progress );
		const CGFloat paneWidth = startWidth + ( targetWidth - startWidth ) * eased;

		//divider 1 is measured from the leading edge, so the pane's width is
		//what is left of the split view behind it
		[strongSelf->_kindStatisticsSplitView
			setPosition: NSWidth( [strongSelf->_kindStatisticsSplitView bounds] ) - paneWidth
	   ofDividerAtIndex: 1];

		if ( progress >= 1.0 )
		{
			[timer invalidate];
			strongSelf->_inspectorAnimationTimer = nil;
			strongSelf->_collapsingInspector = NO;

			if ( completion != nil )
				completion();
		}
	}];
}

- (void) setInspectorVisible: (BOOL) visible animated: (BOOL) animated
{
	if ( _inspectorView == nil || visible == [self isInspectorVisible] )
		return;

	if ( animated && [[self window] isVisible] )
	{
		if ( !visible )
			_inspectorWidth = NSWidth( [_inspectorView frame] );

		const CGFloat targetWidth = visible
			? ( _inspectorWidth > 0.0 ? _inspectorWidth : [DIXInspectorView preferredWidth] )
			: 0.0;

		if ( visible )
		{
			//a zero-width starting point to grow from
			[_inspectorView setHidden: NO];
			_collapsingInspector = YES;
			[_kindStatisticsSplitView setPosition: NSWidth( [_kindStatisticsSplitView bounds] )
								 ofDividerAtIndex: 1];
			[self updateInspector];
		}

		[self updateInspectorButtonState];

		[self animateInspectorToWidth: targetWidth completion: ^
		{
			//Collapse for real at the end. Left at zero width the pane would
			//still count as visible, and its divider would still be draggable.
			if ( !visible )
				[self->_inspectorView setHidden: YES];

			[self updateInspectorButtonState];
		}];

		return;
	}

	//Remember the width so reopening restores it: the split view's own autosave
	//records only a position it has been left at, and collapsing writes zero.
	if ( !visible )
		_inspectorWidth = NSWidth( [_inspectorView frame] );

	if ( visible )
	{
		[_inspectorView setHidden: NO];
		[_kindStatisticsSplitView adjustSubviews];
		[self placePaneDividers];
		[self updateInspector];
	}
	else
	{
		//The divider first, the flag second, and in that order for two separate
		//reasons.
		//
		//Hiding the view is not enough on its own: the divider beside it stays
		//where it was and goes on being drawn there, a 1pt translucent line from
		//the top of the window to the bottom, over the summary strip, the map and
		//the status bar alike. The sidebar never showed it because its own path
		//drives its divider to the edge rather than only hiding the pane.
		//
		//And -setPosition:ofDividerAtIndex: *un-collapses* the subview it gives
		//width to, so setting the flag first left the pane counting as visible
		//again at zero width: the button then closed what was already closed and
		//the inspector could not be reopened at all.
		_collapsingInspector = YES;

		[_kindStatisticsSplitView setPosition: NSWidth( [_kindStatisticsSplitView bounds] )
							 ofDividerAtIndex: 1];

		_collapsingInspector = NO;

		[_inspectorView setHidden: YES];
	}

	[self updateInspectorButtonState];
}

//The design fills this one button while the pane it opens is showing, in the
//same raised tone as the switch's selected segment. The sidebar's button beside
//the breadcrumb is drawn plain either way, which is the design's own asymmetry
//and not an oversight here.
- (void) updateInspectorButtonState
{
	if ( ![_inspectorButton isKindOfClass: [DIXFlatButton class]] )
		return;

	DIXFlatButton *button = (DIXFlatButton*) _inspectorButton;

	[button setFillColor: [self isInspectorVisible] ? [DIXTheme toggleOn] : nil];
	[button setNeedsDisplay: YES];
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

	//The breadcrumb starts where the sidebar ends, so it moves with the divider.
	[self layoutTitleAccessory];

	//Nothing is worth saving until the opening widths have been applied. The
	//split view resizes several times while the window is being assembled, and
	//saving then meant -placePaneDividers read back the arbitrary widths it was
	//about to correct, and so never applied a default at all.
	if ( !_paneWidthsPlaced )
		return;

	if ( ![self isKindStatisticsVisible] || ![self isInspectorVisible] )
		return;

	//Nor part-way through a slide: every frame of it would be written, and the
	//last one before the pane closes is a width nobody chose.
	if ( _animatingKindStatistics || _collapsingInspector )
		return;

	//Nor while a pane is collapsed for Map or List mode. The file list's width
	//in List mode is the whole column, and saving that as the width it wants
	//beside the map is what left the map a sliver on the way back to Both.
	if ( [_listColumn isHidden] || [_mapColumn isHidden] )
		return;

	const CGFloat statistics = NSWidth( [_sidebarPane frame] );
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
		const CGFloat centreMinimum = kMinimumCentreWidth;

		if ( statistics + inspector + centreMinimum > total )
		{
			const CGFloat share = ( total - centreMinimum ) / ( statistics + inspector );

			statistics = floor( statistics * MAX( share, 0.0 ) );
			inspector  = floor( inspector  * MAX( share, 0.0 ) );
		}

		//A saved width under the minimum goes back to the *designed* width, not to
		//the minimum. Nobody chose 140pt for the sidebar - it is either a value
		//saved before these minimums existed, or one scaled down by the share
		//above - and answering it with the bare minimum honours a preference that
		//was never expressed. 244 is the design's, and the user narrowing it to
		//210 by hand still gets 210 back.
		if ( statistics < kMinimumSidebarWidth )
			statistics = [DIXTheme sidebarWidth];

		if ( inspector < kMinimumInspectorWidth )
			inspector = [DIXTheme inspectorWidth];

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
	if ( fileList < kMinimumFileListWidth )
		fileList = [DIXTheme fileListWidth];

	if ( [_splitter isVertical] && NSWidth( [_splitter bounds] ) > fileList * 2.0 )
		[_splitter setPosition: fileList ofDividerAtIndex: 0];


	//And then the view mode again, because -setPosition:ofDividerAtIndex:
	//*un-collapses* the subview it gives width to - which quietly undid Map and
	//List mode. This runs a run-loop turn after the window loads, so the order at
	//launch was: choose the mode, hide the pane it does not want, then hand that
	//pane its designed width straight back. A narrow window opened in Map mode
	//and showed the file list anyway, with the mode control still reading Map.
	[self applyViewMode];

	//from here on the widths are the user's, and worth remembering
	_paneWidthsPlaced = YES;
}

- (IBAction) toggleInspector: (id) sender
{
	[self setInspectorVisible: ![self isInspectorVisible] animated: YES];
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
	return [super toolbar: toolbar
	itemForItemIdentifier: identifier
willBeInsertedIntoToolbar: willInsert];
}

//172 x 26, the design's size, with the scope menu the old selection-list field
//carried. That menu used to come out of the nib; it is built here because the
//field is, and because a menu of four fixed choices is less code than a nib
//reference to one.
//The magnifier and the scope chevron, composed with a gap, for the search
//field's leading button - see kSearchChevronGap.
static NSImage *SearchButtonImage( NSString *label )
{
	NSImageSymbolConfiguration *glassConfig =
		[NSImageSymbolConfiguration configurationWithPointSize: 12.0
														weight: NSFontWeightRegular
														 scale: NSImageSymbolScaleMedium];
	NSImageSymbolConfiguration *chevronConfig =
		[NSImageSymbolConfiguration configurationWithPointSize: 7.0
														weight: NSFontWeightSemibold
														 scale: NSImageSymbolScaleSmall];

	NSImage *glass = [[NSImage imageForSymbolName: @"magnifyingglass"
						 accessibilityDescription: label] imageWithSymbolConfiguration: glassConfig];
	NSImage *chevron = [[NSImage imageForSymbolName: @"chevron.down"
						   accessibilityDescription: label] imageWithSymbolConfiguration: chevronConfig];

	if ( glass == nil || chevron == nil )
		return glass;

	const NSSize glassSize = [glass size];
	const NSSize chevronSize = [chevron size];
	const NSSize size = NSMakeSize( glassSize.width + kSearchChevronGap + chevronSize.width,
									MAX( glassSize.height, chevronSize.height ) );

	NSImage *composed = [NSImage imageWithSize: size flipped: NO drawingHandler:
		^BOOL ( NSRect destination )
	{
		[glass drawAtPoint: NSMakePoint( 0.0, round( ( size.height - glassSize.height ) / 2.0 ) )
				  fromRect: NSZeroRect
				 operation: NSCompositingOperationSourceOver
				  fraction: 1.0];

		[chevron drawAtPoint: NSMakePoint( glassSize.width + kSearchChevronGap,
										   round( ( size.height - chevronSize.height ) / 2.0 ) )
					fromRect: NSZeroRect
				   operation: NSCompositingOperationSourceOver
					fraction: 1.0];
		return YES;
	}];

	[composed setTemplate: YES];

	return composed;
}

- (NSSearchField*) buildSearchField
{
	_searchField = [[NSSearchField alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, kSearchBoxWidth, kSearchBoxHeight )];

	//Unbordered: the box around it draws the design's shape, which is a 6pt
	//rectangle with a hairline and not a bezel NSSearchField has.
	[_searchField setBordered: NO];
	[_searchField setBezeled: NO];
	[_searchField setDrawsBackground: NO];
	[_searchField setFocusRingType: NSFocusRingTypeNone];
	[_searchField setFont: [NSFont systemFontOfSize: 12.0]];

	[_searchField setPlaceholderString:
		NSLocalizedString( @"Search this scan", @"toolbar search field placeholder" )];
	[_searchField setTarget: self];
	[_searchField setAction: @selector(searchFieldChanged:)];
	[_searchField setSendsWholeSearchString: NO];
	[_searchField setSendsSearchStringImmediately: NO];

	NSMenu *scopes = [[NSMenu alloc] initWithTitle: @"Search scope"];

	//The tags are the FSItemIndexType values, so the action needs no mapping and
	//there is no second list to keep in step with this one.
	struct { NSString *title; FSItemIndexType scope; } choices[] = {
		{ NSLocalizedString( @"All",  @"search scope" ), FSItemIndexAll  },
		{ NSLocalizedString( @"Name", @"search scope" ), FSItemIndexName },
		{ NSLocalizedString( @"Kind", @"search scope" ), FSItemIndexKind },
		{ NSLocalizedString( @"Path", @"search scope" ), FSItemIndexPath },
	};

	for ( unsigned i = 0; i < sizeof( choices ) / sizeof( choices[0] ); i++ )
	{
		NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle: choices[i].title
														 action: @selector(changeSearchScope:)
												  keyEquivalent: @""];

		[menuItem setTarget: self];
		[menuItem setTag: (NSInteger) choices[i].scope];
		[scopes addItem: menuItem];
	}

	_searchScopeMenu = scopes;

	//The field's own search button is removed and replaced by one of ours.
	//
	//Unbezeled, the cell still *draws* that button but no longer tracks it - the
	//buttons are tracked within the bezel rect, which is empty - so the chevron
	//was there and clicking it did nothing at all. Ours is a plain button that
	//pops the menu up itself, which also puts its spacing under this file's
	//control rather than inside AppKit's composite glyph.
	[[_searchField cell] setSearchButtonCell: nil];

	NSString *label = NSLocalizedString( @"Search scope", @"search field menu title" );

	_scopeButton = [NSButton buttonWithImage: SearchButtonImage( label )
									  target: self
									  action: @selector(showSearchScopeMenu:)];

	[_scopeButton setBordered: NO];
	[_scopeButton setImagePosition: NSImageOnly];
	[_scopeButton setToolTip: label];
	[_scopeButton setContentTintColor: [DIXTheme tertiaryText]];

	[self updateSearchScopeMenu];

	return _searchField;
}

- (IBAction) searchFieldChanged: (id) sender
{
	FileSystemDoc *doc = [self document];
	const BOOL wasSearching = ( [doc searchString] != nil );

	[doc setSearchString: [sender stringValue]];

	//Results go to the file list, so a search started in Map mode has nowhere to
	//show them. Both if the window can hold three columns, List if it cannot -
	//the same test that chose the mode when the window opened.
	if ( !wasSearching && [doc searchString] != nil && [doc viewMode] == DIXViewModeMap )
	{
		const CGFloat contentWidth = NSWidth( [[[self window] contentView] bounds] );

		[doc setViewMode: ( contentWidth >= [DIXTheme bothModeMinimumContentWidth] )
						  ? DIXViewModeBoth : DIXViewModeList];

		[self updateViewModeControl];
		[self applyViewMode];
	}
}

- (IBAction) changeSearchScope: (id) sender
{
	[[self document] setSearchScope: (FSItemIndexType) [sender tag]];

	[self updateSearchScopeMenu];
}

//NSSearchField rebuilds its menu from the template every time it is shown, so
//the tick has to go on the template rather than on the menu the user saw.
//The menu is ours and is shown as it stands, so ticking an item here is what
//appears. It used to be handed to the field as a search menu *template*, which
//the field copies - so the tick went on an object nothing was showing, and
//choosing a scope worked while looking as though it had not.
- (void) updateSearchScopeMenu
{
	const FSItemIndexType scope = [[self document] searchScope];

	for ( NSMenuItem *menuItem in [_searchScopeMenu itemArray] )
	{
		[menuItem setState: ( (FSItemIndexType) [menuItem tag] == scope )
							? NSControlStateValueOn : NSControlStateValueOff];
	}
}

- (IBAction) showSearchScopeMenu: (id) sender
{
	[self updateSearchScopeMenu];

	//Below the button: the accessory is not flipped, so a negative y is down.
	[_searchScopeMenu popUpMenuPositioningItem: nil
									atLocation: NSMakePoint( 0.0, -4.0 )
										inView: _scopeButton];
}

#pragma mark -----------------the title bar's leading accessory-----------------------

//The breadcrumb and the sidebar button sit in a title bar accessory rather than
//in the toolbar, and that is not a stylistic preference.
//
//The app is built against the macOS 26 SDK, so it opts into Liquid Glass, and on
//26 a toolbar draws each of its items inside a glass capsule: the item's view
//goes into an NSToolbarItemViewer inside an NSGlassContainerView. That is right
//for the view-mode control and the inspector button, which are controls and are
//drawn with a background in the design too. It is wrong for the breadcrumb,
//which is a title - it came out looking like text inside a button.
//
//Nothing supported turns the capsule off. NSToolbarItemViewer has -glassBehavior
//and -setTransparentBackground:, and both are private. A title bar accessory
//goes into an NSTitlebarAccessoryClipView instead, never entering the toolbar's
//glass container, so it is the supported way to put plain text up there.
//
//The sidebar button comes along because a leading accessory is laid out *before*
//the toolbar's own items - measured: the accessory at x=88, the first toolbar
//item at x=274. Leaving NSToolbarToggleSidebarItem in the toolbar would have put
//it to the right of the breadcrumb, where the design has it to the left.
- (void) installTitleAccessory
{
	if ( _titleAccessoryView != nil )
		return;

	NSString *label = NSLocalizedString( @"Sidebar", @"toolbar item label" );

	_sidebarButton = [NSButton buttonWithImage: [NSImage imageForSymbolName: @"sidebar.left"
													  accessibilityDescription: label]
										target: self
										action: @selector(toggleSidebar:)];

	[_sidebarButton setBordered: NO];
	[_sidebarButton setToolTip: NSLocalizedString( @"Show or hide the sidebar",
												   @"toolbar item tooltip" )];

	_breadcrumbView = [[DIXBreadcrumbView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, 240.0, 22.0 )];
	[_breadcrumbView setTarget: self action: @selector(zoomOutTo:)];

	//AppKit stretches the accessory to the full height of the title bar, which is
	//taller than either child. Both margins flexible keeps them centred through
	//that, and -layoutTitleAccessory centres them again whenever the path changes.
	[_sidebarButton setAutoresizingMask: NSViewMinYMargin | NSViewMaxYMargin];
	[_breadcrumbView setAutoresizingMask: NSViewMinYMargin | NSViewMaxYMargin];

	_titleAccessoryView = [[NSView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, 300.0, 22.0 )];
	[_titleAccessoryView addSubview: _sidebarButton];
	[_titleAccessoryView addSubview: _breadcrumbView];

	NSTitlebarAccessoryViewController *accessory =
		[[NSTitlebarAccessoryViewController alloc] init];

	[accessory setView: _titleAccessoryView];
	[accessory setLayoutAttribute: NSLayoutAttributeLeading];

	[[self window] addTitlebarAccessoryViewController: accessory];

	[self updateBreadcrumb];
	[self installTrailingAccessory];
}

//The design's metrics for the right-hand end of the title bar: a 172x26 search
//box, a 28pt inspector button, 10pt between the three and 14pt at the edge.
static const CGFloat kTrailingGap         =  10.0;
static const CGFloat kTrailingEdgeInset   =  14.0;
static const CGFloat kSearchBoxWidth      = 240.0;   //the design's 172, widened on request
static const CGFloat kSearchBoxHeight     =  26.0;
static const CGFloat kInspectorButtonWidth  = 28.0;
static const CGFloat kInspectorButtonHeight = 24.0;

//The caption under the file list: the design's 30pt band with 10pt of padding.
static const CGFloat kListFooterHeight  = 30.0;
static const CGFloat kListFooterPadding = 10.0;

//The design's "padding: 0 8px" inside the search box.
static const CGFloat kSearchBoxPadding    =   8.0;

//Inside the scope button, between the magnifier and the chevron. AppKit's own
//glyph for a search field with a menu puts them rim to rim, where they read as
//one broken symbol rather than as two things.
static const CGFloat kSearchChevronGap    =   4.0;

//And between that button and the text, which wants more air than the chevron's
//own gap: at 4pt the chevron read as belonging to the first letter.
static const CGFloat kSearchTextGap       =   8.0;

//The mode switch, the search field and the inspector button, in a trailing
//accessory rather than in the toolbar - the same move the breadcrumb needed, for
//the same reason.
//
//On macOS 26 a toolbar puts every item inside a Liquid Glass capsule and nothing
//supported switches it off: -setBordered:NO on the item changes nothing,
//measured. Over this window's flat title band the capsule blurs to a near-white
//blob a few points bigger than the control it holds, which is the pale outline
//that showed around the switch. An accessory goes into an
//NSTitlebarAccessoryClipView and never enters the glass container.
//
//The cost is that these three can no longer be dragged out in Customize
//Toolbar. They are gone from the toolbar's item lists as well as its defaults,
//so a saved layout cannot bring back a second copy beside the accessory's own.
- (void) installTrailingAccessory
{
	if ( _trailingAccessoryView != nil )
		return;

	//Drawn rather than an NSSegmentedControl: the design's switch is a flat
	//track with one raised segment on it, and the platform's bezel is neither.
	_viewModeControl = [DIXSegmentedControl switchWithLabels:
		@[ NSLocalizedString( @"Map",  @"view mode" ),
		   NSLocalizedString( @"List", @"view mode" ),
		   NSLocalizedString( @"Both", @"view mode" ) ]
													 target: self
													 action: @selector(changeViewMode:)];

	NSBox *box = FilledBox( [DIXTheme controlFill] );

	[box setBorderWidth: 0.5];
	[box setBorderColor: [DIXTheme controlBorder]];
	[box setCornerRadius: [DIXTheme cornerRadius]];
	//A background only. The scope button and the field are laid out over it as
	//siblings rather than put inside it: NSBox resizes its content view to fill,
	//and one line of text centred in a 26pt box is not that.
	_searchBox = box;

	NSString *inspectorLabel = NSLocalizedString( @"Inspector", @"toolbar item label" );

	//A DIXFlatButton so it can carry the design's "on" fill; see
	//-updateInspectorButtonState.
	DIXFlatButton *inspector = [[DIXFlatButton alloc] initWithFrame: NSZeroRect];

	//NSButton's default title is the word "Button", and -initWithFrame: keeps it
	//where +buttonWithImage: would have cleared it - it drew straight over the
	//symbol.
	[inspector setTitle: @""];
	[inspector setImage: [NSImage imageForSymbolName: @"sidebar.right"
							accessibilityDescription: inspectorLabel]];
	[inspector setImagePosition: NSImageOnly];
	[inspector setTarget: self];
	[inspector setAction: @selector(toggleInspector:)];
	[inspector setTitleColor: [DIXTheme ink]];
	[inspector setToolTip: NSLocalizedString( @"Show or hide the inspector",
											  @"toolbar item tooltip" )];
	_inspectorButton = inspector;

	//AppKit stretches the accessory to the full height of the title bar, so both
	//margins stay flexible and the three stay centred through it.
	[self buildSearchField];

	for ( NSView *view in @[ _viewModeControl, _searchBox, _scopeButton,
							 _searchField, _inspectorButton ] )
	{
		[view setAutoresizingMask: NSViewMinYMargin | NSViewMaxYMargin];
		[view setTranslatesAutoresizingMaskIntoConstraints: YES];
	}

	_trailingAccessoryView = [[NSView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, 460.0, 28.0 )];
	[_trailingAccessoryView addSubview: _viewModeControl];
	[_trailingAccessoryView addSubview: _searchBox];
	[_trailingAccessoryView addSubview: _scopeButton];
	[_trailingAccessoryView addSubview: _searchField];
	[_trailingAccessoryView addSubview: _inspectorButton];

	NSTitlebarAccessoryViewController *accessory =
		[[NSTitlebarAccessoryViewController alloc] init];

	[accessory setView: _trailingAccessoryView];
	[accessory setLayoutAttribute: NSLayoutAttributeTrailing];

	[[self window] addTitlebarAccessoryViewController: accessory];

	[self layoutTrailingAccessory];
	[self updateViewModeControl];
	[self updateInspectorButtonState];
}

//Laid out from the trailing edge inwards, which is the order the design reads
//them in: inspector, search, switch.
- (void) layoutTrailingAccessory
{
	if ( _trailingAccessoryView == nil )
		return;

	[_viewModeControl sizeToFit];

	const CGFloat switchWidth = NSWidth( [_viewModeControl frame] );
	const CGFloat width = kTrailingEdgeInset
						  + kInspectorButtonWidth + kTrailingGap
						  + kSearchBoxWidth + kTrailingGap
						  + switchWidth;

	NSRect frame = [_trailingAccessoryView frame];
	frame.size.width = width;
	[_trailingAccessoryView setFrame: frame];

	const CGFloat midY = NSMidY( [_trailingAccessoryView bounds] );
	CGFloat right = width - kTrailingEdgeInset;

	[_inspectorButton setFrame: NSMakeRect( right - kInspectorButtonWidth,
											midY - kInspectorButtonHeight / 2.0,
											kInspectorButtonWidth, kInspectorButtonHeight )];
	right = NSMinX( [_inspectorButton frame] ) - kTrailingGap;

	[_searchBox setFrame: NSMakeRect( right - kSearchBoxWidth, midY - kSearchBoxHeight / 2.0,
									  kSearchBoxWidth, kSearchBoxHeight )];

	//the design's "padding: 0 8px; gap: 6px", laid out inside the box
	const NSRect box = [_searchBox frame];
	const NSSize scopeSize = [[_scopeButton image] size];

	[_scopeButton setFrame: NSMakeRect( NSMinX( box ) + kSearchBoxPadding,
										midY - scopeSize.height / 2.0,
										scopeSize.width, scopeSize.height )];

	const CGFloat fieldX = NSMaxX( [_scopeButton frame] ) + kSearchTextGap;
	const CGFloat fieldHeight = ceil( [[_searchField font] boundingRectForFont].size.height );

	[_searchField setFrame: NSMakeRect( fieldX, midY - fieldHeight / 2.0,
										NSMaxX( box ) - kSearchBoxPadding - fieldX,
										fieldHeight )];

	right = NSMinX( box ) - kTrailingGap;

	[_viewModeControl setFrame: NSMakeRect( right - switchWidth,
											midY - NSHeight( [_viewModeControl frame] ) / 2.0,
											switchWidth,
											NSHeight( [_viewModeControl frame] ) )];

	//the clip view lays the accessory out from its frame and does not watch it
	[[_trailingAccessoryView superview] setNeedsLayout: YES];
}

//"Macintosh HD › Users › derek › Movies". The zoom stack holds what has been
//zoomed into; the root is not on it, and is prepended here because it is where
//the scan began and the one place you always want to be able to get back to.
- (void) updateBreadcrumb
{
	FileSystemDoc *doc = [self document];
	FSItem *rootItem = [doc rootItem];

	if ( _breadcrumbView == nil || rootItem == nil )
		return;

	NSMutableArray<NSString*> *titles = [NSMutableArray array];
	NSMutableArray *items = [NSMutableArray array];

	//The path down to the scan root, before the root itself. The design's
	//breadcrumb reads "Macintosh HD › Users › derek › Movies" - it starts at the
	//volume, not at whatever was scanned - and without these a scan of
	///usr/share showed a single segment saying "share", which locates nothing.
	//
	//They are outside the scanned tree - there is no item for them and they
	//cannot be zoom targets - so they carry NSNull and the breadcrumb draws
	//them as context rather than as buttons; see below.
	NSURL *rootURL = [rootItem fileURL];

	if ( rootURL != nil )
	{
		//Built from the path's own components, and deliberately not by deleting
		//the last one over and over. -URLByDeletingLastPathComponent does not
		//stop at the volume root: asked about "/" it answers "/..", then
		//"/../..", and on for as long as anything keeps asking. The loop that
		//used to be here broke when it saw "/", which a scan of a volume root
		//never produces - it starts at "/.." - so opening a volume span the main
		//thread at a full core inside -windowDidLoad, allocating a URL and two
		//strings a turn, until the process was killed for memory with its
		//progress panel still on screen.
		//
		//-pathComponents is bounded by the depth of the path and answers exactly
		//["/"] for a volume root, so the ancestor list there is simply empty.
		NSArray<NSString*> *components = [rootURL pathComponents];
		NSMutableArray<NSURL*> *ancestors = [NSMutableArray array];

		//from the volume root up to, but not including, the scan root itself,
		//which is appended below
		for ( NSUInteger i = 1; i < [components count]; i++ )
		{
			[ancestors addObject: [NSURL fileURLWithPathComponents:
				[components subarrayWithRange: NSMakeRange( 0, i )]]];
		}

		for ( NSURL *url in ancestors )
		{
			NSString *name = nil;

			//the volume's own name for "/" and for a mount point, the folder's
			//otherwise - which is what the Finder shows and what the design draws
			if ( ![url getResourceValue: &name forKey: NSURLLocalizedNameKey error: NULL]
				 || [name length] == 0 )
				name = [url lastPathComponent];

			//Context, not a destination. There is no item in this document's
			//tree for a folder above the scan root, so there is nothing to zoom
			//to; it used to open a new scan, which is a lot to happen by
			//accident on the way to clicking the folder next to it.
			[titles addObject: name];
			[items addObject: [NSNull null]];
		}
	}

	[titles addObject: [rootItem displayName]];
	[items addObject: rootItem];

	for ( FSItem *item in [doc zoomStack] )
	{
		[titles addObject: [item displayName]];
		[items addObject: item];
	}

	//An open merged cell is the innermost thing on screen, so it ends the trail.
	//It carries no represented object: there is no item to go back to, and it is
	//the last segment, which the breadcrumb draws as a statement rather than a
	//button in any case.
	if ( [doc focusedPile] != nil )
	{
		NSNumberFormatter *countFormatter = [[NSNumberFormatter alloc] init];
		[countFormatter setNumberStyle: NSNumberFormatterDecimalStyle];

		//The same figure the cell showed before it was opened, and for the same
		//reason: a pile can hold a folder that was packed in whole, so counting
		//the pile's entries would make the number shrink on the way in.
		NSUInteger pileCount = 0;

		for ( FSItem *item in [doc focusedPile] )
			pileCount += [item representedFileCount];

		[titles addObject: [NSString stringWithFormat:
			NSLocalizedString( @"%@ smaller items", @"treemap, a merged remainder cell" ),
			[countFormatter stringFromNumber: @(pileCount)]]];
		[items addObject: [NSNull null]];
	}

	[_breadcrumbView setSegmentTitles: titles representedObjects: items];

	[self layoutTitleAccessory];
}

//The accessory has no layout of its own, and its width has to follow the path or
//a deep breadcrumb is clipped to whatever width it was built at.
- (void) layoutTitleAccessory
{
	const CGFloat kLeadingInset  =  6.0;
	const CGFloat kButtonWidth   = 28.0;
	const CGFloat kGap           = 12.0;
	const CGFloat kContentHeight = 22.0;

	if ( _titleAccessoryView == nil )
		return;

	const CGFloat height = NSHeight( [_titleAccessoryView frame] );
	const CGFloat y = floor( (height - kContentHeight) / 2.0 );

	[_sidebarButton setFrame: NSMakeRect( kLeadingInset, y, kButtonWidth, kContentHeight )];

	//The design starts the breadcrumb just past the sidebar, at the same x as the
	//file list below it, so it reads as a heading for the content rather than for
	//the window. That edge moves: the divider is draggable and the sidebar
	//collapses, so it is measured rather than assumed, and the button's own width
	//is the floor for when the sidebar is closed.
	CGFloat x = kLeadingInset + kButtonWidth + kGap;

	if ( [self isKindStatisticsVisible] )
	{
		//Both in the window's own coordinates: the accessory is in the title bar
		//and the pane is in the content view, so neither one's bounds will do.
		NSView *frameView = [[[self window] contentView] superview];

		const CGFloat paneEdge = NSMaxX( [_sidebarPane convertRect: [_sidebarPane bounds]
															toView: frameView] );
		const CGFloat originX  = NSMinX( [_titleAccessoryView convertRect: [_titleAccessoryView bounds]
																   toView: frameView] );

		//14 points past the sidebar's edge, which is the design's own padding
		//inside the content area, so the breadcrumb sits over the file list's
		//left margin rather than merely after the divider.
		x = MAX( x, paneEdge - originX + 14.0 );
	}

	const CGFloat width = [_breadcrumbView fittingWidth];

	[_breadcrumbView setFrame: NSMakeRect( x, y, width, kContentHeight )];

	NSRect box = [_titleAccessoryView frame];
	box.size.width = x + width + kGap;
	[_titleAccessoryView setFrame: box];

	//The title bar lays accessories out from their frames, and does not watch
	//them for changes: without this a zoom that lengthens the path leaves the
	//clip view at the old width and the last segment is cut off.
	[[_titleAccessoryView superview] setNeedsLayout: YES];

	//The sidebar's band in the title bar ends where the breadcrumb's own inset is
	//measured from, so the two are always answering the same divider.
	[self layoutTitleBarBand];
}

//The title bar carries the breadcrumb, which is a title, so the window's own
//title is turned off rather than repeated beside it. Icon-only is the design's
//toolbar: glyphs with no captions, which is also what leaves the breadcrumb
//room to grow.
- (void) windowDidLoad
{
	[super windowDidLoad];

	//After -super, which is what builds the toolbar: the accessory has to be the
	//leading thing in the title bar, and it is added to the window rather than
	//to the toolbar, so the two do not race.
	[self installTitleAccessory];

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

		//And from here a resize is a resize. Until this point the split view is
		//still being built and sized - the widths above are applied by moving
		//dividers, and the window is still growing into its autosaved frame -
		//and holding the side columns still through all of that left the file
		//list wider than the pane it sits in, with Size and Share off the end.
		[weakSelf setPaneWidthsSettled: YES];
	});

	[[self window] setTitleVisibility: NSWindowTitleHidden];
	[[[self window] toolbar] setDisplayMode: NSToolbarDisplayModeIconOnly];

	[self colourTitleBar];
}

//A plain filled box, since three of them are wanted here and NSBox insets
//anything added as a subview by five points on every side - which is how the
//sidebar band's trailing edge first came out five points into the map.
static NSBox *FilledBox( NSColor *color )
{
	NSBox *box = [[NSBox alloc] initWithFrame: NSZeroRect];

	[box setBoxType: NSBoxCustom];
	[box setBorderWidth: 0.0];
	[box setFillColor: color];

	return box;
}

//The title bar is one of the design's surfaces, with a value of its own -
//#f6f5f4 over #2a2827 - and AppKit's is neither. Left alone it draws the
//system's material, which measured #2A353A above a sidebar of #2F2C2B: a cold
//slate band over a window that is warm everywhere else, which is the one thing
//in the chrome that reads as belonging to a different application.
//
//-setTitlebarAppearsTransparent: is what makes the band available to draw in. It
//does not touch the toolbar's items, which keep their glass capsules - right for
//them, since the design draws the view-mode control and the inspector button
//with a background too.
//
//It does take AppKit's separator with it, so the line under the band is ours.
//That is a gain rather than a replacement: the system drew a neutral #2F2F2F
//there, and the design's border under the top bar is -hairline, the same line
//that divides the panes underneath it.
//
//The design also does not stop the sidebar at the title bar - it runs the
//sidebar's fill and its trailing border the full height of the window, so the
//column reads as one thing with the traffic lights sitting on it. Both
//appearances agree, and every value is a token already here: #efedec / #232120
//beside #f6f5f4 / #2a2827, divided by #d9d6d4 / #3a3836.
//
//None of this can be an accessory. A leading accessory is laid out after the
//traffic lights, so it can never reach x=0, and NSTitlebarAccessoryClipView
//clips it besides. The bands go into the theme frame instead, below every
//sibling so the traffic lights and the toolbar stay above them - verified, not
//assumed: a probe read the close button as its own colour through them.
//
//The window's own background is -ground and not -toolbar, though painting the
//band with it would have been one line fewer. The background reaches every part
//of the window nothing else covers - measured, a 9pt strip between the file list
//and the map - and the toolbar's colour has no business down there.
- (void) colourTitleBar
{
	NSWindow *window = [self window];

	[window setTitlebarAppearsTransparent: YES];
	[window setBackgroundColor: [DIXTheme ground]];

	if ( _titleBarSeparator != nil )
		return;

	NSView *contentView = [window contentView];
	const NSRect contentBounds = [contentView bounds];
	const CGFloat thickness = [DIXTheme hairlineThickness];

	_titleBarSeparator = FilledBox( [DIXTheme hairline] );

	[_titleBarSeparator setFrame: NSMakeRect( 0.0, NSMaxY( contentBounds ) - thickness,
											  NSWidth( contentBounds ), thickness )];
	[_titleBarSeparator setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];

	//last, so it is not covered by the columns it lies across
	[contentView addSubview: _titleBarSeparator
				 positioned: NSWindowAbove
				 relativeTo: nil];

	_titleBarBand        = FilledBox( [DIXTheme toolbar] );
	_titleBarSidebarBand = FilledBox( [DIXTheme sidebar] );
	_titleBarSidebarEdge = FilledBox( [DIXTheme hairline] );

	//The theme frame is not flipped, so staying at the top of the window is a
	//flexible bottom margin. -layoutTitleBarBand sets the frames again whenever
	//the divider moves; this covers a resize that does not move it.
	[_titleBarBand setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
	[_titleBarSidebarBand setAutoresizingMask: NSViewMinYMargin];
	[_titleBarSidebarEdge setAutoresizingMask: NSViewMinYMargin];

	NSView *frameView = [contentView superview];

	//Below everything, so nothing AppKit puts in the title bar is covered; and
	//each above the one before, because relativeTo:nil would otherwise bury the
	//edge under the band it is the edge of - which is exactly what it did.
	[frameView addSubview: _titleBarBand positioned: NSWindowBelow relativeTo: nil];
	[frameView addSubview: _titleBarSidebarBand positioned: NSWindowAbove relativeTo: _titleBarBand];
	[frameView addSubview: _titleBarSidebarEdge positioned: NSWindowAbove relativeTo: _titleBarSidebarBand];

	[self layoutTitleBarBand];
}

//Both the width and the height are measured rather than assumed. The width
//because the divider is draggable and the pane collapses, exactly as the
//breadcrumb's own x is; the height because in full screen there is no title bar
//and the content view fills the frame, which leaves all three zero-height and
//out of the way without anything here having to know that it happened.
- (void) layoutTitleBarBand
{
	if ( _titleBarBand == nil )
		return;

	NSView *contentView = [[self window] contentView];
	NSView *frameView   = [contentView superview];

	const NSRect frameBounds = [frameView bounds];
	const CGFloat titleHeight = NSHeight( frameBounds ) - NSHeight( [contentView frame] );

	CGFloat sidebarEdge = 0.0;

	if ( titleHeight > 0.0 && [self isKindStatisticsVisible] )
		sidebarEdge = NSMaxX( [_sidebarPane convertRect: [_sidebarPane bounds] toView: frameView] );

	const CGFloat thickness = [DIXTheme hairlineThickness];
	const CGFloat y = NSMaxY( frameBounds ) - titleHeight;

	[_titleBarBand setFrame: NSMakeRect( 0.0, y, NSWidth( frameBounds ), titleHeight )];
	[_titleBarSidebarBand setFrame: NSMakeRect( 0.0, y, sidebarEdge, titleHeight )];
	[_titleBarSidebarEdge setFrame: NSMakeRect( MAX( 0.0, sidebarEdge - thickness ), y,
												sidebarEdge > 0.0 ? thickness : 0.0, titleHeight )];
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
	if ( _listColumn == nil || _mapColumn == nil )
		return;

	const DIXViewMode mode = [[self document] viewMode];

	[_listColumn setHidden: ( mode == DIXViewModeMap )];

	//The column, not the map inside it: hiding a subview is how NSSplitView
	//collapses a pane, and the pane is the column now.
	[_mapColumn setHidden: ( mode == DIXViewModeList )];

	[_splitter adjustSubviews];

	//A pane coming back from Map or List mode has no width, and -adjustSubviews
	//shares a change out in *proportion* - so a zero-width subview stays at zero
	//however much room there is. Going Both, List, Both left the map collapsed
	//and the file list holding the whole column.
	//
	//So the divider is placed rather than left to be redistributed. Divider 0
	//gives its width to the file list, and un-collapses it as a side effect,
	//which is right here and only here: in Both both panes are meant to show.
	if ( mode == DIXViewModeBoth )
	{
		const CGFloat fileList = [self preferredFileListWidth];

		if ( [_splitter isVertical] && NSWidth( [_splitter bounds] ) > fileList * 2.0 )
			[_splitter setPosition: fileList ofDividerAtIndex: 0];
	}

	[self placeSummaryStrip];

	[self updateViewModeControl];
	[self updateStatusBarHintForViewMode];
}

//What the file list should be beside the map: the width it was last left at,
//or the design's. Shared by -placePaneDividers and the mode switch, which both
//have to put the divider somewhere when the panes have no widths of their own.
- (CGFloat) preferredFileListWidth
{
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey: kPaneWidthsKey];

	CGFloat fileList = ( [saved count] == 3 ) ? [[saved objectAtIndex: 1] doubleValue]
											  : kDefaultFileListWidth;

	//A saved width under the minimum goes back to the designed one rather than
	//to the bare minimum - see -placePaneDividers for why.
	if ( fileList < kMinimumFileListWidth )
		fileList = [DIXTheme fileListWidth];

	return fileList;
}

//Where the summary belongs, which depends on whether there is a map for it to
//sit above. In Both and Map mode it is the map column's heading and the file
//list runs to the top of the window beside it, as the design draws it. In List
//mode there is no map - and the total, Rescan and the zoom buttons are not the
//map's to take away with it - so it goes back across the whole column.
- (void) placeSummaryStrip
{
	if ( _summaryStripView == nil || _mapColumn == nil || _centreColumn == nil )
		return;

	//The design scopes both bands to the map: the summary above it, the status
	//bar below it, with the file list a column of its own carrying nothing but
	//its own caption. In Map or List mode one of the two panes is collapsed, and
	//in List mode the bands would go with the map - so they move back across the
	//whole column instead, where the total, Rescan and the hover readout are
	//still worth having.
	const BOOL mapShowing = ![_mapColumn isHidden];
	NSView *host = mapShowing ? _mapColumn : _centreColumn;

	for ( NSView *band in @[ _summaryStripView, _statusBarView ] )
	{
		if ( band != nil && [band superview] != host )
		{
			[band removeFromSuperview];
			[host addSubview: band];
		}
	}

	const CGFloat stripHeight  = [DIXSummaryStripView preferredHeight];
	const CGFloat statusHeight = [DIXStatusBarView preferredHeight];
	const CGFloat bannerHeight = [self privacyBannerHeight];

	//The split view takes the whole column when the bands are inside it, and
	//stops short of them when they are not. Its margins are fixed and its height
	//sizable, so this is the one place that has to know the difference.
	NSRect squeezed = [_centreColumn bounds];

	//The banner is above everything in the column, including the summary strip:
	//it is about the total, and has to be read before it.
	squeezed.size.height -= bannerHeight;

	if ( bannerHeight > 0.0 )
	{
		[_privacyBannerView setFrame: NSMakeRect( 0.0,
												  NSMaxY( [_centreColumn bounds] ) - bannerHeight,
												  NSWidth( [_centreColumn bounds] ), bannerHeight )];
	}

	if ( !mapShowing )
	{
		squeezed.origin.y = statusHeight;
		squeezed.size.height = NSHeight( squeezed ) - statusHeight - stripHeight;
	}

	[_splitter setFrame: squeezed];

	const NSRect hostBounds = [host bounds];

	//In List mode the strip is in the column itself, where the banner is too, so
	//it starts under it rather than at the top.
	const CGFloat hostTop = NSMaxY( hostBounds ) - ( host == _centreColumn ? bannerHeight : 0.0 );

	[_summaryStripView setFrame: NSMakeRect( 0.0, hostTop - stripHeight,
											 NSWidth( hostBounds ), stripHeight )];

	[_statusBarView setFrame: NSMakeRect( 0.0, 0.0, NSWidth( hostBounds ), statusHeight )];

	//the map fills what is left of its column between the two
	NSRect mapFrame = [_mapColumn bounds];

	if ( mapShowing )
	{
		mapFrame.origin.y = statusHeight;
		mapFrame.size.height -= stripHeight + statusHeight;
	}

	[_treeMapView setFrame: mapFrame];
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

	//Exactly one row in SOURCES is the thing this window is showing, and it is
	//whatever was scanned: a volume when a volume was scanned, the folder's own
	//row when a folder was.
	//
	//The volume used to be marked whenever the scan was anywhere *on* it, which
	//is true but is not what the highlight means - scanning /usr/share lit both
	//Macintosh HD and the share row, and two current rows is one too many.
	//
	//Identity rather than equal URLs: the scan root's URL and the volume's arrive
	//from different sources and need not be spelled the same, and a file
	//reference identifier is the comparison the walk already trusts for "is this
	//the same directory".
	NSURL *rootURL = [rootItem fileURL];
	NSURL *volumeURL = nil;

	if ( ![rootURL getResourceValue: &volumeURL forKey: NSURLVolumeURLKey error: NULL] )
		volumeURL = nil;

	id rootIdentifier = nil, volumeIdentifier = nil;

	[rootURL getResourceValue: &rootIdentifier
					   forKey: NSURLFileResourceIdentifierKey error: NULL];
	[volumeURL getResourceValue: &volumeIdentifier
						 forKey: NSURLFileResourceIdentifierKey error: NULL];

	const BOOL scannedAVolume = ( rootIdentifier != nil && volumeIdentifier != nil
								  && [rootIdentifier isEqual: volumeIdentifier] );

	[_sourcesView setCurrentVolumeURL: scannedAVolume ? volumeURL : nil];
	[_sourcesView setCurrentRootURL: rootURL];

	[self updateSummarySubtitle];

	[self updateSummaryDelta];

	//What the total above is missing, said next to it. Placed after, because
	//the banner's height is what the rest of the column is laid out around.
	[self updatePrivacyBanner];
	[self placeSummaryStrip];

	//the same conditions -validateMenuItem: applies to the zoom menu items
	FSItem *selectedItem = [doc selectedItem];
	[_summaryStripView setZoomInEnabled: selectedItem != nil && [selectedItem isFolder]
						 zoomOutEnabled: [doc rootItem] != [doc zoomedItem]];
}

//"+2.81 GB / since 8 Aug" - what this folder has gained or lost since the last
//time it was scanned. Nothing is said on a first scan, or when the two totals
//are equal: a delta of zero is noise, not news.
- (void) updateSummaryDelta
{
	FileSystemDoc *doc = [self document];
	NSDate *previousDate = [doc previousScanDate];

	if ( _summaryStripView == nil || previousDate == nil )
	{
		[_summaryStripView setDelta: nil caption: nil isGrowth: YES];
		return;
	}

	const unsigned long long now = [[[doc rootItem] size] unsignedLongLongValue];
	const unsigned long long before = [doc previousScanSize];

	if ( now == before )
	{
		[_summaryStripView setDelta: nil caption: nil isGrowth: YES];
		return;
	}

	//"what grew" beside the caption, which is where the design puts the way in
	//to the change window. Offered only when there is a list behind it: a link
	//to six rows of nothing is worse than no link.
	const BOOL hasRows = ( [[doc changesSinceLastScan] count] > 0 );

	const BOOL growth = ( now > before );
	const unsigned long long difference = growth ? ( now - before ) : ( before - now );

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	//"since 8 Aug", not "since Aug 21, 2026": the year is noise on a comparison
	//with the last scan, and the order of day and month is the locale's.
	NSDateFormatter *when = [[NSDateFormatter alloc] init];
	[when setDateFormat: [NSDateFormatter dateFormatFromTemplate: @"dMMM"
														 options: 0
														  locale: [NSLocale currentLocale]]];

	[_summaryStripView
		 setDelta: [NSString stringWithFormat: @"%@%@", growth ? @"+" : @"−",
					[sizeFormatter stringForObjectValue: @(difference)]]
		  caption: [NSString stringWithFormat:
					NSLocalizedString( @"since %@", @"summary strip, when the last scan was" ),
					[when stringFromDate: previousDate]]
		 isGrowth: growth];

	[_summaryStripView setChangesLinkTitle:
		hasRows ? ( [doc showsOnlyChanges]
					? NSLocalizedString( @"showing what grew", @"summary strip link, filter on" )
					: NSLocalizedString( @"what grew", @"summary strip link" ) )
				: nil
									target: self
									action: @selector(showWhatChanged:)];
}

#pragma mark --------what the scan could not read-----------------

- (CGFloat) privacyBannerHeight
{
	if ( _privacyBannerView == nil || [_privacyBannerView isHidden] )
		return 0.0;

	return [_privacyBannerView preferredHeightForWidth: NSWidth( [_centreColumn bounds] )];
}

//Built the first time there is something to say and never again: dismissing it
//is meant to be final for this window, and a banner that came back on the next
//redraw would be a nag rather than a notice.
- (void) updatePrivacyBanner
{
	FileSystemDoc *doc = [self document];

	const BOOL wanted = [[NSUserDefaults standardUserDefaults] boolForKey: ShowSkippedFoldersBanner]
						&& [[doc skippedFolders] count] > 0;

	if ( !wanted )
	{
		[_privacyBannerView setHidden: YES];
		return;
	}

	if ( _privacyBannerView == nil )
	{
		_privacyBannerView = [[DIXPrivacyBannerView alloc] initWithFrame: NSZeroRect];

		[_privacyBannerView setTarget: self
					   settingsAction: @selector(openPrivacySettings:)
						   scanAction: @selector(scanSkippedFoldersAnyway:)
						dismissAction: @selector(dismissPrivacyBanner:)];

		[_centreColumn addSubview: _privacyBannerView];
	}

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	[_privacyBannerView setHidden: NO];
	[_privacyBannerView setSkippedFolders: [doc skippedFolders]
							   totalShown: [sizeFormatter stringForObjectValue: [[doc rootItem] size]]];
}

- (IBAction) openPrivacySettings: (id) sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:
		@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]];
}

//Asks macOS again rather than assuming: if the permission has since been given,
//the folders become readable and a rescan will count them. If it has not, the
//consent dialog is what appears, and nothing is rescanned for nothing.
- (IBAction) scanSkippedFoldersAnyway: (id) sender
{
	if ( ![[self document] requestAccessToSkippedFolders] )
	{
		[self updatePrivacyBanner];
		[self placeSummaryStrip];
		return;
	}

	[self refreshAll: sender];
}

- (IBAction) dismissPrivacyBanner: (id) sender
{
	[_privacyBannerView setHidden: YES];
	[self placeSummaryStrip];
}

#pragma mark --------what changed since the last scan-----------------

- (IBAction) showWhatChanged: (id) sender
{
	if ( _changesController == nil )
	{
		_changesController = [[DIXChangesController alloc]
								 initWithDocument: [self document]];
		[_changesController setChangesDelegate: self];
	}

	[_changesController showChanges];
}

- (void) changesControllerSetShowsOnlyChanges: (BOOL) showsOnlyChanges
{
	[[self document] setShowsOnlyChanges: showsOnlyChanges];

	//the caption says which of the two states the map is in
	[self updateSummaryDelta];

	[[self window] makeKeyAndOrderFront: nil];
}

- (void) changesControllerReviewItem: (FSItem*) item
{
	//Straight to the document, which posts GlobalSelectionChangedNotification;
	//the outline expands to the row and the map outlines the cell off the back
	//of that, rather than this reaching into either of them.
	[[self document] setSelectedItem: item];

	[[self window] makeKeyAndOrderFront: nil];
}

//The total and the two counts do not change while a document is open; "scanned
//8 seconds ago" does, which is why this is on a clock of its own rather than
//riding -updateSummaryStrip, whose first half reads resource values off the
//scan root.
- (void) updateSummarySubtitle
{
	FileSystemDoc *doc = [self document];
	FSItem *rootItem = [doc rootItem];

	if ( _summaryStripView == nil || rootItem == nil )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	NSNumberFormatter *countFormatter = [[NSNumberFormatter alloc] init];
	[countFormatter setNumberStyle: NSNumberFormatterDecimalStyle];

	NSString *subtitle = [NSString stringWithFormat:
		NSLocalizedString( @"%@ files · %@ folders · scanned %@", @"summary strip subtitle" ),
		[countFormatter stringFromNumber: @( [doc fileCount] )],
		[countFormatter stringFromNumber: @( [doc folderCount] )],
		[DIXRecentScan relativeTimeStringForDate: [doc scanCompletedAt]]];

	[_summaryStripView setTotal: [sizeFormatter stringForObjectValue: [rootItem size]]
					   subtitle: subtitle];
}

//The sidebar redraws its rows on the same period, so the strip and the row for
//the same scan never disagree by more than one tick. It follows the window, so
//a closed document stops waking the machine to restate how long ago something
//happened.
static const NSTimeInterval kSummaryAgeRefreshInterval = 5.0;

- (void) startSummaryAgeClock
{
	[_summaryAgeTimer invalidate];

	__weak MainWindowController *weakSelf = self;

	_summaryAgeTimer = [NSTimer scheduledTimerWithTimeInterval: kSummaryAgeRefreshInterval
													   repeats: YES
														 block: ^( NSTimer *timer )
	{
		[weakSelf updateSummarySubtitle];
	}];
}

//A hidden subview is how NSSplitView collapses a pane: it keeps the subview and
//its constraints but gives it no space, which is what the drawers did visually.
- (BOOL) isKindStatisticsVisible
{
	//The sidebar pane, not the nib's statistics view inside it: NSSplitView
	//collapses by hiding *its own* subview, and since SOURCES moved in above the
	//statistics that subview is the container. Asking the inner view would have
	//answered YES for a collapsed sidebar.
	return _sidebarPane != nil && ![_sidebarPane isHidden];
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
	if ( _sidebarPane == nil || visible == [self isKindStatisticsVisible] )
		return;

	if ( !animated || ![[self window] isVisible] )
	{
		[_sidebarPane setHidden: !visible];
		[_kindStatisticsSplitView adjustSubviews];
		return;
	}

	//Remember the width so reopening restores it. The split view's own autosave
	//only records a position it has been left at, and collapsing writes zero.
	if ( !visible )
		_kindStatisticsWidth = NSWidth( [_sidebarPane frame] );

	const CGFloat targetWidth = visible ? ( _kindStatisticsWidth > 0.0 ? _kindStatisticsWidth
																	  : kDefaultKindStatisticsWidth )
										: 0.0;

	if ( visible )
	{
		//give it a zero-width starting point to grow from
		[_sidebarPane setHidden: NO];
		_animatingKindStatistics = YES;
		[_kindStatisticsSplitView setPosition: 0.0 ofDividerAtIndex: 0];
	}

	[self animateKindStatisticsDividerTo: targetWidth completion: ^
	{
		//Collapse for real at the end. Leaving the pane at zero width would keep
		//the divider draggable and -isKindStatisticsVisible would still say YES.
		if ( !visible )
		{
			[self->_sidebarPane setHidden: YES];
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

	const CGFloat startWidth = NSWidth( [_sidebarPane frame] );
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

#pragma mark -----------------NSSplitView delegate-----------------------

//What each pane needs before it stops being worth having.
//
//The sidebar's was 120pt, from when it held nothing but a statistics table. It
//now carries volume names beside their free space and a legend of kind names,
//and at 120 both truncate to a couple of characters - which is what made the
//capacity figure look unplaceable when it was really the pane being too narrow.
//200 keeps "Macintosh HD" and "MacBinary archive" whole; the design opens it at
//244.
//
//The file list had no minimum at all: its divider fell through to whatever
//NSSplitView proposed, so it could be dragged down to a sliver of truncated
//names. 260 is the Size and Share columns (74 + 46) plus the indentation and
//enough left for a name to be recognisable.
static const CGFloat kMinimumSidebarWidth  = 200.0;
static const CGFloat kMinimumFileListWidth = 260.0;
static const CGFloat kMinimumTreeMapWidth  = 260.0;

//Below this the inspector's two-column attribute grid stops being readable and
//its three header buttons start truncating their titles.
static const CGFloat kMinimumInspectorWidth = 220.0;

//What the centre column keeps against the side panes: the floor
//-placePaneDividers protects at load, and the two outer dividers enforce
//while being dragged.
static const CGFloat kMinimumCentreWidth = 320.0;

//What the middle column has to hold: whichever of the list and the map is
//showing. In Map or List mode one of them is collapsed and the column needs
//only the other's minimum, the same test the constrain methods make.
- (CGFloat) minimumCentreColumnWidth
{
	CGFloat minimum = 0.0;

	if ( ![_listColumn isHidden] )
		minimum += kMinimumFileListWidth;

	if ( ![_mapColumn isHidden] )
		minimum += kMinimumTreeMapWidth;

	return minimum;
}

- (BOOL) splitView: (NSSplitView*) splitView canCollapseSubview: (NSView*) subview
{
	return subview == _sidebarPane || subview == _selectionListPane;
}

//A closed side pane's divider sits on the window's own resize edge, where it is
//in the way rather than useful: dragging the window wider from the right border
//opened the inspector instead of resizing anything. While a pane is closed its
//divider is not a handle - the button in the title bar is how it opens - so the
//draggable area is taken away and the window edge gets its hit test back.
- (NSRect) splitView: (NSSplitView*) splitView
	   effectiveRect: (NSRect) proposedEffectiveRect
		forDrawnRect: (NSRect) drawnRect
	ofDividerAtIndex: (NSInteger) dividerIndex
{
	if ( splitView == _kindStatisticsSplitView )
	{
		if ( dividerIndex == 0 && [_sidebarPane isHidden] )
			return NSZeroRect;

		if ( dividerIndex == 1 && [_inspectorView isHidden] )
			return NSZeroRect;
	}

	//And the outline/map divider while a view mode has one of them collapsed:
	//it parks at the column's leading edge in Map mode and at its trailing edge
	//in List mode - the window's own resize edge once the inspector is closed -
	//and dragging it would pull a pane out from under the mode control, which
	//would still name the mode the drag had just undone.
	if ( splitView == _splitter
		 && ( [_listColumn isHidden] || [_mapColumn isHidden] ) )
		return NSZeroRect;

	return proposedEffectiveRect;
}

//A window resize belongs to the middle column. The sidebar and the inspector
//were set to a width by whoever dragged them there and have no reason to move
//because the window did; NSSplitView's default is to share the change out in
//proportion, so widening the window by 400 points quietly widened all three.
//
//The middle keeps a floor of its own. Below that everything gives way again,
//because a subview AppKit is not allowed to shrink is one it will shrink to
//nothing instead - the flexible one goes to zero first and takes the file list
//and the map with it.
- (BOOL) splitView: (NSSplitView*) splitView shouldAdjustSizeOfSubview: (NSView*) view
{
	if ( !_paneWidthsSettled )
		return YES;

	//The map takes what the middle column gains or loses, and the file list keeps
	//the width it was dragged to. That covers both ways the column changes size:
	//the window being resized, and the inspector closing beside it.
	if ( splitView == _splitter )
	{
		//In Map or List mode one of the two is collapsed, and a collapse needs
		//both free to move.
		if ( [_listColumn isHidden] || [_mapColumn isHidden] )
			return YES;

		//and below the map's own minimum the list gives way rather than the map
		//disappearing
		if ( NSWidth( [_mapColumn frame] ) <= kMinimumTreeMapWidth )
			return YES;

		return view == _mapColumn;
	}

	if ( splitView != _kindStatisticsSplitView )
		return YES;

	if ( NSWidth( [_centreColumn frame] ) <= [self minimumCentreColumnWidth] )
		return YES;

	return view == _centreColumn;
}

- (void) setPaneWidthsSettled: (BOOL) settled
{
	_paneWidthsSettled = settled;
}

- (CGFloat) splitView: (NSSplitView*) splitView
constrainMinCoordinate: (CGFloat) proposedMin
		  ofSubviewAt: (NSInteger) dividerIndex
{
	//The outline against the map. Only while both are showing: in Map or List
	//mode one of them is collapsed, and holding a minimum against a pane that is
	//meant to have no width at all would stop the mode taking effect.
	if ( splitView == _splitter )
	{
		if ( [_listColumn isHidden] || [_mapColumn isHidden] )
			return proposedMin;

		return MAX( proposedMin, kMinimumFileListWidth );
	}

	if ( splitView != _kindStatisticsSplitView )
		return proposedMin;

	//Divider 1 is the one before the inspector; dragging it left is what makes
	//the inspector wider, so its minimum is what keeps the centre usable.
	if ( dividerIndex == 1 )
		return MAX( proposedMin, NSMinX( [_centreColumn frame] ) + kMinimumCentreWidth );

	//The minimum keeps the pane usable rather than letting it be dragged to a
	//sliver, but it has to be lifted while collapsing or the slide would stop
	//dead at 120 points instead of reaching zero.
	if ( !_animatingKindStatistics )
		return MAX( proposedMin, kMinimumSidebarWidth );

	return proposedMin;
}

- (CGFloat) splitView: (NSSplitView*) splitView
constrainMaxCoordinate: (CGFloat) proposedMax
		  ofSubviewAt: (NSInteger) dividerIndex
{
	if ( splitView == _splitter )
	{
		if ( [_listColumn isHidden] || [_mapColumn isHidden] )
			return proposedMax;

		return MIN( proposedMax, NSWidth([splitView bounds]) - kMinimumTreeMapWidth );
	}

	if ( splitView != _kindStatisticsSplitView )
		return proposedMax;

	//Not while it is being closed. A minimum held against a pane that is meant
	//to have no width at all would stop the divider short of the edge, which is
	//the same reason the sidebar's minimum is lifted while it slides shut.
	if ( dividerIndex == 1 )
		return _collapsingInspector
			   ? proposedMax
			   : MIN( proposedMax, NSWidth([splitView bounds]) - kMinimumInspectorWidth );

	//And leave room for the outline and treemap. Measured from the centre
	//column's own trailing edge, not from the split view's: with the inspector
	//open, AppKit's proposed maximum is the centre being crushed to nothing -
	//measured, a hard drag left the file list and the map at zero width - and a
	//cap of the split view's width less a margin sits beyond it, binding never.
	return MIN( proposedMax, NSMaxX( [_centreColumn frame] ) - kMinimumCentreWidth );
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

	//An open merged cell is the innermost thing the map is showing, so it is the
	//first thing zooming out closes - before any step of the zoom stack, which
	//is where it visually sits.
	if ( [doc focusedPile] != nil )
	{
		[doc setFocusedPile: nil];
		return;
	}

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
	id represented = [sender representedObject];

	//Segments that stand for no item - the folders above the scan root, and the
	//open pile - are labels rather than buttons and cannot send this, but a
	//menu item could.
	if ( represented == nil || represented == [NSNull null] )
		return;

	FSItem *item = represented;

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

//The basket, rather than the selection. Confirmation names both figures,
//because this is several files at once and the count alone does not say how
//much of the disk is about to go.
- (IBAction) reclaimBasket: (id) sender
{
	FileSystemDoc *doc = (FileSystemDoc*) [self document];

	if ( [doc basketCount] == 0 )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
	const unsigned long long freed = [doc basketSize];
	NSString *total = [sizeFormatter stringForObjectValue: @(freed)];

	NSAlert *alert = [[NSAlert alloc] init];

	[alert setMessageText:
		[NSString stringWithFormat: NSLocalizedString( @"Move %lu items to the Trash?",
													   @"reclaim confirmation" ),
									(unsigned long) [doc basketCount] ]];
	[alert setInformativeText:
		[NSString stringWithFormat: NSLocalizedString( @"This frees %@.", @"reclaim confirmation" ),
									total]];

	[alert addButtonWithTitle: NSLocalizedString( @"Move to Trash", @"reclaim confirmation" )];
	[alert addButtonWithTitle: NSLocalizedString( @"Cancel", @"reclaim confirmation" )];

	if ( [alert runModal] != NSAlertFirstButtonReturn )
		return;

	//A copy, because trashing posts FSItemsChangedNotification and the basket
	//prunes itself against the tree as it goes
	for ( FSItem *item in [[doc basketItems] copy] )
		[self moveItemToTrash: item];

	[doc clearBasket];

	[_statusBarView flashMessage:
		[NSString stringWithFormat: NSLocalizedString( @"Freed %@", @"status bar, after reclaiming" ),
									total]];

	//And the one moment there is anything to be thanked for. Freed is read from
	//the basket before it is emptied, above.
	[[DonationPanelController sharedController] showPanelAfterReclaiming: freed];
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

//The floating Info window is gone: the inspector shows the same rows against
//the same selection, without a second window to keep in step with the first.
//
//The selector keeps its old name because the main menu nib names it, which is
//the same reason -toggleFileKindsDrawer: and -toggleSelectionListDrawer: keep
//theirs. The menu item's *title* is not stale - it now reads "Inspector".
- (IBAction) showInformationPanel:(id)sender
{
	[self toggleInspector: sender];
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
			return NO;

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
    else if ( menuAction == @selector(selectParentItem:) )
    {
        return selectedItem != nil && selectedItem != [doc zoomedItem];
    }   
    else if ( menuAction == @selector(showInformationPanel:) )
    {
        SET_TITLE_AND_IMAGE( [self isInspectorVisible],
							 @"Hide Inspector", @"Show Inspector" );
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
//
//And again when the breadcrumb and the sidebar button left the toolbar for the
//title bar accessory: a saved layout still names both, and would draw a second
//sidebar button beside the accessory's own.
- (NSString *)toolbarAutosaveIdentifier
{
    return @"MainWindowToolbar-7";
}

#pragma mark -----------------NSWindow delegates-----------------------

//Nothing to do any more. This existed to point the one floating Info window at
//whichever document had just come forward; the inspector belongs to its own
//window and follows its own document's selection.
- (void)windowDidBecomeMain:(NSNotification *)aNotification
{
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

	[_summaryAgeTimer invalidate];
	_summaryAgeTimer = nil;

	[_inspectorAnimationTimer invalidate];
	_inspectorAnimationTimer = nil;
	_collapsingInspector = NO;

	//the summary strip observers registered in -buildWindowChrome
	[[NSNotificationCenter defaultCenter] removeObserver: self];
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
