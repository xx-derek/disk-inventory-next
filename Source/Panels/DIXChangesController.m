//
//  DIXChangesController.m
//  Disk Inventory Next
//
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "DIXChangesController.h"
#import "DIXScanHistory.h"
#import "FileSystemDoc.h"
#import "FSItem.h"
#import "FileTypeColors.h"
#import "FileSizeFormatter.h"
#import "DIXTheme.h"
#import "DIXControls.h"

//The design's own numbers for this screen.
static const CGFloat kWindowWidth      = 460.0;
static const CGFloat kEdgeInset        =  22.0;
static const CGFloat kTopInset         =  20.0;
static const CGFloat kHeadlineSize     =  30.0;
static const CGFloat kHeadlineGap      =  10.0;   //headline to the totals beside it
static const CGFloat kHeadlineGapBot   =  14.0;   //headline to the 2pt rule

static const CGFloat kRowPaddingY      =   9.0;
static const CGFloat kRowColumnGap     =  10.0;
static const CGFloat kRowDeltaGap      =  12.0;   //name column to the figure

static const CGFloat kFooterGapTop     =  16.0;
static const CGFloat kFooterButtonH    =  30.0;

//Six is what the design draws and about what anyone reads before scrolling;
//past that the list scrolls rather than the window growing off the screen.
static const NSUInteger kRowsBeforeScrolling = 6;

//And this many rows are built at all. The change list is everything over a
//megabyte and can run to thousands after a long gap; a hundred views is already
//more than the question needs, and the list is sorted biggest-first, so the cut
//falls where it matters least.
static const NSUInteger kMaximumRowsShown = 100;

//================ DIXChangeRow =======================================================

//One line: kind chip, name over the folder that holds it, and the signed figure.
@interface DIXChangeRow : NSView
{
	DIXKindChip *_chip;
	NSTextField *_nameField;
	NSTextField *_pathField;
	NSTextField *_deltaField;
}

+ (CGFloat) preferredHeight;

- (void) setChange: (DIXScanChange*) change
			 color: (NSColor*) color
		 formatter: (FileSizeFormatter*) formatter;

@end

@implementation DIXChangeRow

+ (CGFloat) preferredHeight
{
	//two lines of text inside the padding: 12pt and 11pt, as the design has them
	return kRowPaddingY * 2.0 + 15.0 + 14.0;
}

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_chip = [DIXKindChip chipWithColor: [DIXTheme neutralFill]];
		[_chip setTranslatesAutoresizingMaskIntoConstraints: YES];

		_nameField = [self labelWithFont: [NSFont systemFontOfSize: 12.0
															weight: NSFontWeightMedium]
								   color: [DIXTheme ink]];

		_pathField = [self labelWithFont: [NSFont systemFontOfSize: 11.0]
								   color: [DIXTheme tertiaryText]];

		//Tabular figures, because a column of sizes that ripples as it is read
		//is the one thing this window must not do to its own numbers.
		_deltaField = [self labelWithFont: [NSFont monospacedDigitSystemFontOfSize: 12.0
																			weight: NSFontWeightSemibold]
									color: [DIXTheme accent]];
		[_deltaField setAlignment: NSTextAlignmentRight];

		for ( NSView *view in @[ _chip, _nameField, _pathField, _deltaField ] )
			[self addSubview: view];
	}

	return self;
}

- (NSTextField*) labelWithFont: (NSFont*) font color: (NSColor*) color
{
	NSTextField *field = [NSTextField labelWithString: @""];

	[field setFont: font];
	[field setTextColor: color];
	[field setLineBreakMode: NSLineBreakByTruncatingTail];
	[field setTranslatesAutoresizingMaskIntoConstraints: YES];

	return field;
}

- (void) setChange: (DIXScanChange*) change
			 color: (NSColor*) color
		 formatter: (FileSizeFormatter*) formatter
{
	const long long delta = [change delta];
	const BOOL growth = ( delta > 0 );

	[_chip setColor: color];
	[_nameField setStringValue: [change name] ?: @""];

	//"~/Library/Developer/Xcode", and nothing at all at the root of a scan
	[_pathField setStringValue: [change folderPath] ?: @""];

	//A true minus sign, U+2212, not a hyphen: this sits under a headline set in
	//the same figures and a hyphen is visibly shorter and higher than the plus.
	[_deltaField setStringValue: [NSString stringWithFormat: @"%@%@",
		growth ? @"+" : @"−",
		[formatter stringForObjectValue: @( growth ? delta : -delta )]]];

	//growth is the accent, shrinkage the positive colour - the point of the
	//window is that growth is what you came to find
	[_deltaField setTextColor: growth ? [DIXTheme accent] : [DIXTheme positive]];

	[self layoutContents];
}

- (void) setFrameSize: (NSSize) newSize
{
	[super setFrameSize: newSize];
	[self layoutContents];
}

- (void) layoutContents
{
	const NSRect bounds = [self bounds];

	[_nameField sizeToFit];
	[_pathField sizeToFit];
	[_deltaField sizeToFit];

	const CGFloat nameHeight = NSHeight( [_nameField frame] );
	const CGFloat pathHeight = NSHeight( [_pathField frame] );
	const CGFloat deltaWidth = NSWidth( [_deltaField frame] );

	[_deltaField setFrame: NSMakeRect( NSMaxX( bounds ) - deltaWidth,
									   NSMidY( bounds ) - NSHeight( [_deltaField frame] ) / 2.0,
									   deltaWidth, NSHeight( [_deltaField frame] ) )];

	const CGFloat chipSize = [_chip chipSize];

	[_chip setFrame: NSMakeRect( NSMinX( bounds ),
								 NSMidY( bounds ) - chipSize / 2.0,
								 chipSize, chipSize )];

	const CGFloat textX = NSMaxX( [_chip frame] ) + kRowColumnGap;
	const CGFloat textWidth = MAX( 0.0, NSMinX( [_deltaField frame] ) - kRowDeltaGap - textX );

	//the pair centred as a block, so a row reads as one thing rather than two
	const CGFloat blockTop = NSMidY( bounds ) + ( nameHeight + pathHeight ) / 2.0;

	[_nameField setFrame: NSMakeRect( textX, blockTop - nameHeight, textWidth, nameHeight )];
	[_pathField setFrame: NSMakeRect( textX, blockTop - nameHeight - pathHeight,
									  textWidth, pathHeight )];
}

//The 1pt separator under each row. Under, not between: the design rules the
//last row too, which is what closes the list off above the footer.
- (void) drawRect: (NSRect) dirtyRect
{
	NSRect line = [self bounds];
	line.size.height = [DIXTheme hairlineThickness];

	[[DIXTheme rowSeparator] set];
	NSRectFill( NSIntersectionRect( line, dirtyRect ) );
}

@end

//================ DIXChangesController ===============================================

//Flipped, so the biggest change is at the top of the list and a scroll view
//around it starts there rather than at the last row.
@interface DIXChangeRowsView : NSView
@end

@implementation DIXChangeRowsView
- (BOOL) isFlipped { return YES; }
@end

@interface DIXChangesController()
{
	__weak FileSystemDoc *_document;

	NSWindow *_window;
	NSTextField *_headlineField;
	NSTextField *_totalsField;
	NSBox *_rule;

	NSScrollView *_scrollView;
	NSView *_rowsView;

	NSTextField *_emptyField;
	NSButton *_filterButton;
	NSButton *_reviewButton;

	NSArray<DIXScanChange*> *_changes;
	FSItem *_largestChangedItem;
}
@end

@implementation DIXChangesController

- (instancetype) initWithDocument: (FileSystemDoc*) document
{
	self = [super init];

	if ( self != nil )
	{
		_document = document;
		_changes = @[];

		[self buildWindow];
	}

	return self;
}

#pragma mark --------building it-----------------

- (void) buildWindow
{
	_window = [[NSWindow alloc] initWithContentRect: NSMakeRect( 0.0, 0.0, kWindowWidth, 320.0 )
										  styleMask: NSWindowStyleMaskTitled
													 | NSWindowStyleMaskClosable
											backing: NSBackingStoreBuffered
											  defer: NO];

	[_window setTitlebarAppearsTransparent: YES];
	[_window setBackgroundColor: [DIXTheme surface]];
	[_window setReleasedWhenClosed: NO];

	NSView *content = [_window contentView];

	_headlineField = [NSTextField labelWithString: @""];
	[_headlineField setTranslatesAutoresizingMaskIntoConstraints: YES];

	_totalsField = [NSTextField labelWithString: @""];
	[_totalsField setFont: [NSFont systemFontOfSize: 12.0]];
	[_totalsField setTextColor: [DIXTheme secondaryText]];
	[_totalsField setLineBreakMode: NSLineBreakByTruncatingTail];
	[_totalsField setTranslatesAutoresizingMaskIntoConstraints: YES];

	//2pt ink. The heaviest line the design draws here, and the boundary between
	//the one figure and the account of where it came from.
	_rule = [DIXControls sectionRule];
	[_rule setTranslatesAutoresizingMaskIntoConstraints: YES];

	_rowsView = [[DIXChangeRowsView alloc] initWithFrame: NSZeroRect];

	_scrollView = [[NSScrollView alloc] initWithFrame: NSZeroRect];
	[_scrollView setDocumentView: _rowsView];
	[_scrollView setHasVerticalScroller: YES];
	[_scrollView setDrawsBackground: NO];
	[_scrollView setBorderType: NSNoBorder];
	[DIXControls useOverlayScrollersIn: _scrollView];
	[_scrollView setTranslatesAutoresizingMaskIntoConstraints: YES];

	_emptyField = [NSTextField labelWithString: @""];
	[_emptyField setFont: [NSFont systemFontOfSize: 12.0]];
	[_emptyField setTextColor: [DIXTheme secondaryText]];
	[_emptyField setTranslatesAutoresizingMaskIntoConstraints: YES];

	_filterButton = [DIXControls secondaryButtonWithTitle: @""
												   target: self
												   action: @selector(toggleMapFilter:)];
	[_filterButton setTranslatesAutoresizingMaskIntoConstraints: YES];

	_reviewButton = [DIXControls primaryButtonWithTitle: @""
												 target: self
												 action: @selector(review:)];
	[_reviewButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[_reviewButton setKeyEquivalent: @"\r"];

	for ( NSView *view in @[ _headlineField, _totalsField, _rule, _scrollView,
							 _emptyField, _filterButton, _reviewButton ] )
		[content addSubview: view];
}

#pragma mark --------filling it-----------------

- (void) showChanges
{
	[self reload];
	[_window makeKeyAndOrderFront: nil];
}

- (void) reload
{
	FileSystemDoc *doc = _document;
	FSItem *rootItem = [doc rootItem];

	if ( doc == nil || rootItem == nil )
		return;

	_changes = [doc changesSinceLastScan] ?: @[];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	const unsigned long long now = [[rootItem size] unsignedLongLongValue];
	const unsigned long long before = [doc previousScanSize];
	const BOOL growth = ( now >= before );
	const unsigned long long difference = growth ? ( now - before ) : ( before - now );

	NSDate *previousDate = [doc previousScanDate];

	//"Since 8 Aug", the window's whole title - the same wording and the same
	//locale-ordered day and month as the summary strip's caption.
	NSDateFormatter *when = [[NSDateFormatter alloc] init];
	[when setDateFormat: [NSDateFormatter dateFormatFromTemplate: @"dMMM"
														options: 0
														 locale: [NSLocale currentLocale]]];

	[_window setTitle: previousDate != nil
		? [NSString stringWithFormat: NSLocalizedString( @"Since %@", @"change window title" ),
									  [when stringFromDate: previousDate]]
		: NSLocalizedString( @"What Changed", @"change window title, no previous scan" )];

	NSString *headline = [NSString stringWithFormat: @"%@%@",
		growth ? @"+" : @"−", [sizeFormatter stringForObjectValue: @(difference)]];

	[_headlineField setAttributedStringValue:
		[[NSAttributedString alloc] initWithString: headline
										attributes: [DIXTheme displayAttributesOfSize: kHeadlineSize
																				color: growth ? [DIXTheme accent]
																							  : [DIXTheme positive]]]];

	//"91.8 GB → 94.6 GB in 7 days". The span is a formatter's rather than a
	//division, so "1 day" and "3 hours" come out right and are translated.
	NSDateComponentsFormatter *span = [[NSDateComponentsFormatter alloc] init];
	[span setUnitsStyle: NSDateComponentsFormatterUnitsStyleFull];
	[span setAllowedUnits: NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute];
	[span setMaximumUnitCount: 1];

	NSString *elapsed = previousDate != nil
		? [span stringFromDate: previousDate toDate: [doc scanCompletedAt] ?: [NSDate date]] : nil;

	[_totalsField setStringValue: [elapsed length] > 0
		? [NSString stringWithFormat: NSLocalizedString( @"%@ → %@ in %@", @"change window totals" ),
			[sizeFormatter stringForObjectValue: @(before)],
			[sizeFormatter stringForObjectValue: @(now)], elapsed]
		: [NSString stringWithFormat: NSLocalizedString( @"%@ → %@", @"change window totals" ),
			[sizeFormatter stringForObjectValue: @(before)],
			[sizeFormatter stringForObjectValue: @(now)]]];

	[self rebuildRowsWithFormatter: sizeFormatter];

	//"Review 2.81 GB" names the figure above it, which is what it takes you to.
	[_reviewButton setTitle: [NSString stringWithFormat:
		NSLocalizedString( @"Review %@", @"change window, go to the biggest change" ),
		[sizeFormatter stringForObjectValue: @(difference)]]];

	[_reviewButton setEnabled: _largestChangedItem != nil];

	[self updateFilterButtonTitle];
	[self layoutContents];
}

- (void) updateFilterButtonTitle
{
	const BOOL filtering = [_document showsOnlyChanges];

	[_filterButton setTitle: filtering
		? NSLocalizedString( @"Show Everything on the Map", @"change window button" )
		: NSLocalizedString( @"Show Only These on the Map", @"change window button" )];

	[_filterButton setEnabled: filtering || [_changes count] > 0];
}

- (void) rebuildRowsWithFormatter: (FileSizeFormatter*) sizeFormatter
{
	for ( NSView *view in [[_rowsView subviews] copy] )
		[view removeFromSuperview];

	_largestChangedItem = nil;

	FileSystemDoc *doc = _document;
	FileTypeColors *colors = [doc fileTypeColors];
	const NSUInteger shown = MIN( [_changes count], kMaximumRowsShown );
	const CGFloat rowHeight = [DIXChangeRow preferredHeight];
	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;

	[_rowsView setFrameSize: NSMakeSize( width, rowHeight * (CGFloat) shown )];

	for ( NSUInteger i = 0; i < shown; i++ )
	{
		DIXScanChange *change = [_changes objectAtIndex: i];
		FSItem *item = [doc itemAtPath: [change path]];

		//The biggest one that is still there - which is not always the first
		//row, since the biggest change of all can be something that was deleted.
		if ( _largestChangedItem == nil && item != nil )
			_largestChangedItem = item;

		DIXChangeRow *row = [[DIXChangeRow alloc] initWithFrame:
			NSMakeRect( 0.0, rowHeight * (CGFloat) i, width, rowHeight )];

		//Something deleted since the scan has no item and so no kind: neutral,
		//the same tone the map gives to what is not a file kind.
		[row setChange: change
				 color: ( item != nil ) ? [colors colorForItem: item] : [DIXTheme neutralFill]
			 formatter: sizeFormatter];

		[_rowsView addSubview: row];
	}

	const BOOL empty = ( shown == 0 );

	[_scrollView setHidden: empty];
	[_emptyField setHidden: !empty];

	[_emptyField setStringValue: [_document previousScanDate] != nil
		? NSLocalizedString( @"Nothing has changed by more than a megabyte.",
							 @"change window, no rows" )
		: NSLocalizedString( @"This folder has not been scanned before, so there is nothing to compare against.",
							 @"change window, first scan" )];
}

#pragma mark --------layout-----------------

//One pass of arithmetic from the top down, and then the window is sized to what
//it came to: the height follows the row count, which is the only thing here
//that varies.
- (void) layoutContents
{
	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;
	const CGFloat rowHeight = [DIXChangeRow preferredHeight];
	const NSUInteger shown = MIN( [_changes count], kMaximumRowsShown );

	[_headlineField sizeToFit];
	[_totalsField sizeToFit];
	[_emptyField sizeToFit];
	[_filterButton sizeToFit];
	[_reviewButton sizeToFit];

	const CGFloat headlineHeight = NSHeight( [_headlineField frame] );

	const CGFloat listHeight = ( shown == 0 )
		? NSHeight( [_emptyField frame] ) + kRowPaddingY * 2.0
		: rowHeight * (CGFloat) MIN( shown, kRowsBeforeScrolling );

	const CGFloat contentHeight = kTopInset + headlineHeight + kHeadlineGapBot
								  + [DIXTheme ruleThickness] + listHeight
								  + kFooterGapTop + kFooterButtonH + kEdgeInset;

	//A window that comes back a row taller should grow downwards, not push its
	//title bar up the screen - so the top-left corner is what is held, which is
	//not what -setContentSize: does on its own.
	NSRect frame = [_window frameRectForContentRect:
		NSMakeRect( 0.0, 0.0, kWindowWidth, contentHeight )];

	if ( [_window isVisible] )
	{
		const NSRect existing = [_window frame];

		frame.origin = NSMakePoint( NSMinX( existing ),
									NSMaxY( existing ) - NSHeight( frame ) );
		[_window setFrame: frame display: YES];
	}
	else
	{
		[_window setContentSize: NSMakeSize( kWindowWidth, contentHeight )];
		[_window center];
	}

	CGFloat y = contentHeight - kTopInset - headlineHeight;

	[_headlineField setFrame: NSMakeRect( kEdgeInset, y,
										  MIN( NSWidth( [_headlineField frame] ), width ),
										  headlineHeight )];

	//The totals sit on the headline's baseline rather than on its box, which is
	//what "align-items: baseline" means and what keeps 12pt from floating in
	//the middle of 30pt.
	const CGFloat totalsX = NSMaxX( [_headlineField frame] ) + kHeadlineGap;
	const CGFloat baseline = y + [[_headlineField font] descender] * -1.0;

	[_totalsField setFrame: NSMakeRect( totalsX,
										baseline + [[_totalsField font] descender],
										MAX( 0.0, kEdgeInset + width - totalsX ),
										NSHeight( [_totalsField frame] ) )];

	y -= kHeadlineGapBot + [DIXTheme ruleThickness];
	[_rule setFrame: NSMakeRect( kEdgeInset, y, width, [DIXTheme ruleThickness] )];

	y -= listHeight;
	[_scrollView setFrame: NSMakeRect( kEdgeInset, y, width, listHeight )];

	[_emptyField setFrame: NSMakeRect( kEdgeInset, y + kRowPaddingY, width,
									   NSHeight( [_emptyField frame] ) )];

	y -= kFooterGapTop + kFooterButtonH;

	[_filterButton setFrame: NSMakeRect( kEdgeInset, y,
										 NSWidth( [_filterButton frame] ), kFooterButtonH )];

	const CGFloat reviewWidth = MAX( 110.0, NSWidth( [_reviewButton frame] ) );

	[_reviewButton setFrame: NSMakeRect( kEdgeInset + width - reviewWidth, y,
										 reviewWidth, kFooterButtonH )];
}

#pragma mark --------the two things it does-----------------

- (IBAction) toggleMapFilter: (id) sender
{
	const BOOL wanted = ![_document showsOnlyChanges];

	[[self changesDelegate] changesControllerSetShowsOnlyChanges: wanted];
	[self updateFilterButtonTitle];

	//Out of the way of the map it has just narrowed. Left open it would be
	//sitting over the answer it just asked for.
	[_window orderOut: nil];
}

- (IBAction) review: (id) sender
{
	if ( _largestChangedItem == nil )
		return;

	[[self changesDelegate] changesControllerSetShowsOnlyChanges: YES];
	[[self changesDelegate] changesControllerReviewItem: _largestChangedItem];

	[_window orderOut: nil];
}

@end
