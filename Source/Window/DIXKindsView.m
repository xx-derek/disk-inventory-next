//
//  DIXKindsView.m
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

#import "DIXKindsView.h"
#import "FileSystemDoc.h"
#import "FSItem.h"
#import "FileTypeColors.h"
#import "FileSizeFormatter.h"
#import "DIXTheme.h"
#import "DIXControls.h"

static const CGFloat kPadding      = 14.0;
static const CGFloat kLabelHeight  = 18.0;
static const CGFloat kHeaderHeight = 34.0;
static const CGFloat kRowHeight    = 38.0;
static const CGFloat kChipGap      = 10.0;
static const CGFloat kBarHeight    =  3.0;

//How far the share bar starts inside the row's own padding. The design's 18px,
//which lands it under the chip's trailing edge rather than under the name.
static const CGFloat kBarIndent    = 18.0;

//The rows themselves. Split out from DIXKindsView so it can be an
//NSScrollView's document view: a volume can carry sixty kinds and the sidebar
//has room for a dozen.
@interface DIXKindsRowsView : NSView
{
	NSArray<FileKindStatistic*> *_statistics;
	__weak FileSystemDoc *_document;
	NSInteger _hoveredRow;
	NSTrackingArea *_trackingArea;
}
- (void) setDocument: (FileSystemDoc*) document statistics: (NSArray<FileKindStatistic*>*) statistics;
@end

@implementation DIXKindsRowsView

- (BOOL) isFlipped
{
	//rows are counted from the top, which is also the direction a scroll view
	//scrolls in - laying them out bottom-up would put the largest kind at the
	//bottom of the scrolled content
	return YES;
}

- (void) setDocument: (FileSystemDoc*) document statistics: (NSArray<FileKindStatistic*>*) statistics
{
	_document = document;
	_statistics = statistics;
	_hoveredRow = -1;

	NSRect frame = [self frame];
	frame.size.height = MAX( kRowHeight * (CGFloat) [statistics count], 1.0 );
	[self setFrame: frame];

	[self setNeedsDisplay: YES];
}

- (NSRect) rectForRowAtIndex: (NSUInteger) index
{
	return NSMakeRect( 0.0, kRowHeight * (CGFloat) index, NSWidth( [self bounds] ), kRowHeight );
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Clamped, like every other chrome view here - see DIXStatusBarView.
	[[DIXTheme sidebar] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	if ( [_statistics count] == 0 )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	const unsigned long long scanSize = [[[_document rootItem] size] unsignedLongLongValue];
	NSString *filter = [_document kindFilter];

	//Ink, not bodyText. A kind name is the row's subject and the design sets it
	//in the same tone as any other primary label; the quieter step belongs to
	//the figure beside it.
	NSDictionary *nameAttributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize: 12.0],
		NSForegroundColorAttributeName: [DIXTheme ink],
	};
	NSDictionary *sizeAttributes = @{
		NSFontAttributeName: [DIXTheme tabularFontOfSize: 11.0],
		NSForegroundColorAttributeName: [DIXTheme secondaryText],
	};

	for ( NSUInteger i = 0; i < [_statistics count]; i++ )
	{
		const NSRect row = [self rectForRowAtIndex: i];

		if ( !NSIntersectsRect( row, dirtyRect ) )
			continue;

		FileKindStatistic *statistic = [_statistics objectAtIndex: i];
		NSString *kind = [statistic kindName];

		const BOOL isFiltered = ( filter != nil && [filter isEqualToString: kind] );

		if ( isFiltered || (NSInteger) i == _hoveredRow )
		{
			[( isFiltered ? [DIXTheme selectedRowFill] : [DIXTheme controlFill] ) set];

			[[NSBezierPath bezierPathWithRoundedRect: NSInsetRect( row, 8.0, 2.0 )
											 xRadius: [DIXTheme cornerRadius]
											 yRadius: [DIXTheme cornerRadius]] fill];
		}

		const CGFloat chipSize = [DIXTheme kindChipSize];
		const CGFloat chipX = kPadding;
		const CGFloat textY = NSMinY( row ) + 7.0;

		//the same colour the map gives this kind, which is the whole point of
		//the section
		[[[_document fileTypeColors] colorForKind: kind] set];
		NSRectFill( NSMakeRect( chipX, textY + 2.0, chipSize, chipSize ) );

		NSString *sizeText = [sizeFormatter stringForObjectValue: @([statistic size])];
		const NSSize sizeExtent = [sizeText sizeWithAttributes: sizeAttributes];

		const CGFloat nameX = chipX + chipSize + kChipGap;
		const CGFloat nameWidth = MAX( 0.0, NSMaxX( row ) - kPadding - sizeExtent.width - 8.0 - nameX );

		[kind drawInRect: NSMakeRect( nameX, textY, nameWidth, 16.0 ) withAttributes: nameAttributes];
		[sizeText drawAtPoint: NSMakePoint( NSMaxX( row ) - kPadding - sizeExtent.width, textY )
			   withAttributes: sizeAttributes];

		if ( scanSize > 0 )
		{
			const double fraction = (double) [statistic size] / (double) scanSize;
			//Indented past the chip but not as far as the name: the design starts
			//the bar 18pt inside the row's padding, which is 8pt short of where
			//the text begins, so the bars line up as a column of their own.
			const CGFloat barX = kPadding + kBarIndent;
			const NSRect track = NSMakeRect( barX, NSMaxY( row ) - 11.0,
											 NSMaxX( row ) - kPadding - barX, kBarHeight );

			//-well is the *surface* white; a track drawn in it disappears against
			//the sidebar in light and is far too dark in the other direction
			[[DIXTheme barTrack] set];
			NSRectFill( track );

			NSRect fill = track;
			fill.size.width = MAX( 1.0, track.size.width * MIN( 1.0, fraction ) );

			[[[_document fileTypeColors] colorForKind: kind] set];
			NSRectFill( fill );
		}
	}
}

#pragma mark --------filtering-----------------

- (void) mouseUp: (NSEvent*) event
{
	const NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];

	for ( NSUInteger i = 0; i < [_statistics count]; i++ )
	{
		if ( !NSPointInRect( point, [self rectForRowAtIndex: i] ) )
			continue;

		NSString *kind = [[_statistics objectAtIndex: i] kindName];

		//a second click on the same row clears it, so the filter needs no
		//separate control to turn off
		[_document setKindFilter: [kind isEqualToString: [_document kindFilter]] ? nil : kind];

		[self setNeedsDisplay: YES];
		return;
	}
}

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];

	if ( _trackingArea != nil )
		[self removeTrackingArea: _trackingArea];

	_trackingArea = [[NSTrackingArea alloc] initWithRect: [self bounds]
												 options: ( NSTrackingMouseMoved
															| NSTrackingMouseEnteredAndExited
															| NSTrackingActiveInKeyWindow )
												   owner: self
												userInfo: nil];
	[self addTrackingArea: _trackingArea];
}

- (void) setHoveredRow: (NSInteger) row
{
	if ( row == _hoveredRow )
		return;

	_hoveredRow = row;
	[self setNeedsDisplay: YES];
}

- (void) mouseMoved: (NSEvent*) event
{
	const NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
	const NSInteger row = (NSInteger) floor( point.y / kRowHeight );

	[self setHoveredRow: ( row >= 0 && row < (NSInteger) [_statistics count] ) ? row : -1];
}

- (void) mouseExited: (NSEvent*) event
{
	[self setHoveredRow: -1];
}

@end

#pragma mark ================================================================

@interface DIXKindsView()
{
	NSTextField *_sectionLabel;
	NSButton *_filterButton;
	NSScrollView *_scrollView;
	DIXKindsRowsView *_rowsView;
	__weak FileSystemDoc *_document;
}
@end

@implementation DIXKindsView

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
		[self buildViewHierarchy];

	return self;
}

- (instancetype) initWithCoder: (NSCoder*) coder
{
	self = [super initWithCoder: coder];

	if ( self != nil )
		[self buildViewHierarchy];

	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void) buildViewHierarchy
{
	_sectionLabel = [DIXControls sectionLabelWithTitle:
		NSLocalizedString( @"FILE KINDS", @"sidebar section, the treemap's colour legend" )];
	[_sectionLabel setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _sectionLabel];

	//Only meaningful once something is filtered, so it says "Clear" rather than
	//"Filter": the filter is applied by clicking a row, and a button offering to
	//do what a click already does would be a second way to say the same thing.
	_filterButton = [NSButton buttonWithTitle:
		NSLocalizedString( @"Clear", @"sidebar, stop filtering the map to one kind" )
									   target: self
									   action: @selector(clearFilter:)];
	[_filterButton setBordered: NO];
	[_filterButton setFont: [NSFont systemFontOfSize: 11.0 weight: NSFontWeightSemibold]];
	[_filterButton setContentTintColor: [DIXTheme accent]];
	[_filterButton setHidden: YES];
	[_filterButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _filterButton];

	_rowsView = [[DIXKindsRowsView alloc] initWithFrame: NSZeroRect];

	_scrollView = [[NSScrollView alloc] initWithFrame: NSZeroRect];
	[_scrollView setDocumentView: _rowsView];
	[_scrollView setHasVerticalScroller: YES];
	[_scrollView setAutohidesScrollers: YES];
	[_scrollView setDrawsBackground: NO];
	[_scrollView setBorderType: NSNoBorder];
	[_scrollView setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _scrollView];
}

- (void) setDocument: (FileSystemDoc*) document
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

	[center removeObserver: self];

	_document = document;

	if ( document != nil )
	{
		for ( NSString *name in @[ FSItemsChangedNotification,
								   ZoomedItemChangedNotification,
								   ViewOptionChangedNotification ] )
			[center addObserver: self selector: @selector(reload) name: name object: document];
	}

	[self reload];
}

- (void) reload
{
	//Largest first. The statistics are a dictionary keyed by kind name, so the
	//order has to be imposed here; the design's legend is a ranking.
	NSArray<FileKindStatistic*> *statistics =
		[[[_document kindStatistics] allValues] sortedArrayUsingSelector: @selector(compareSizeDescendingly:)];

	[_rowsView setDocument: _document statistics: statistics];
	[_filterButton setHidden: ( [_document kindFilter] == nil )];

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) clearFilter: (id) sender
{
	[_document setKindFilter: nil];
}

#pragma mark --------layout-----------------

- (void) setFrameSize: (NSSize) newSize
{
	[super setFrameSize: newSize];
	[self layoutContents];
}

- (void) layoutContents
{
	const NSRect bounds = [self bounds];
	const CGFloat contentWidth = NSWidth( bounds ) - kPadding * 2.0;

	if ( contentWidth <= 0.0 )
		return;

	[_filterButton sizeToFit];

	const CGFloat buttonWidth = MIN( NSWidth( [_filterButton frame] ), contentWidth / 2.0 );
	const CGFloat labelY = NSMaxY( bounds ) - kHeaderHeight + ( kHeaderHeight - kLabelHeight ) / 2.0;

	[_sectionLabel setFrame: NSMakeRect( kPadding, labelY,
										 contentWidth - buttonWidth - 8.0, kLabelHeight )];
	[_filterButton setFrame: NSMakeRect( NSMaxX( bounds ) - kPadding - buttonWidth, labelY,
										 buttonWidth, kLabelHeight )];

	[_scrollView setFrame: NSMakeRect( 0.0, 0.0, NSWidth( bounds ),
									   MAX( 0.0, NSHeight( bounds ) - kHeaderHeight ) )];

	NSRect rowsFrame = [_rowsView frame];
	rowsFrame.size.width = NSWidth( [_scrollView contentView].bounds );
	[_rowsView setFrame: rowsFrame];
}

- (void) drawRect: (NSRect) dirtyRect
{
	[[DIXTheme sidebar] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	//hairline down the trailing edge, separating the sidebar from the file list
	NSRect line = [self bounds];
	line.origin.x = NSMaxX( line ) - 1.0;
	line.size.width = 1.0;

	[[DIXTheme hairline] set];
	NSRectFill( NSIntersectionRect( line, dirtyRect ) );
}

@end
