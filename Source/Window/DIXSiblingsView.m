//
//  DIXSiblingsView.m
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

#import "DIXSiblingsView.h"
#import "FileSystemDoc.h"
#import "FSItem.h"
#import "FSItem-Utilities.h"
#import "FileSizeFormatter.h"
#import "DIXTheme.h"
#import "DIXControls.h"

static const CGFloat kPadding      = 16.0;
static const CGFloat kHeaderHeight = 30.0;
static const CGFloat kRowHeight    = 26.0;
static const CGFloat kBarHeight    = 56.0;
static const CGFloat kBoxSize      = 15.0;

//Beyond this the list stops being something to read and starts being something
//to scroll forever. The header still counts every one of them, so the figure
//never lies about what is there.
static const NSUInteger kMaximumRows = 200;

@interface DIXSiblingsView()
{
	__weak FileSystemDoc *_document;
	FSItem *_item;
	NSArray<FSItem*> *_siblings;

	NSTextField *_headerLabel;
	NSTextField *_headerDetail;
	NSScrollView *_scrollView;
	NSView *_rowsView;

	NSBox *_barRule;
	NSTextField *_barCount;
	NSTextField *_barSize;
	NSButton *_trashButton;

	id _trashTarget;
	SEL _trashAction;
}
@end

@implementation DIXSiblingsView

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
	_headerLabel = [DIXControls sectionLabelWithTitle: @""];
	[_headerLabel setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _headerLabel];

	_headerDetail = [NSTextField labelWithString: @""];
	[_headerDetail setFont: [DIXTheme tabularFontOfSize: 11.0]];
	[_headerDetail setTextColor: [DIXTheme secondaryText]];
	[_headerDetail setAlignment: NSTextAlignmentRight];
	[_headerDetail setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _headerDetail];

	_rowsView = [[NSView alloc] initWithFrame: NSZeroRect];

	_scrollView = [[NSScrollView alloc] initWithFrame: NSZeroRect];
	[_scrollView setDocumentView: _rowsView];
	[_scrollView setHasVerticalScroller: YES];
	[_scrollView setAutohidesScrollers: YES];
	[_scrollView setDrawsBackground: NO];
	[_scrollView setBorderType: NSNoBorder];
	[_scrollView setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _scrollView];

	//The reclaim bar. Hidden until something is ticked - an empty bar offering
	//to trash nothing is a permanent invitation to an irreversible thing.
	//A 2pt rule, not a row separator. The design gives the reclaim bar the
	//heaviest line in the window - it is the boundary between browsing and an
	//action that deletes files - and it was drawn as the lightest one there is.
	_barRule = [DIXControls sectionRule];
	[_barRule setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _barRule];

	_barCount = [NSTextField labelWithString: @""];
	[_barCount setFont: [NSFont systemFontOfSize: 11.0]];
	[_barCount setTextColor: [DIXTheme secondaryText]];
	[_barCount setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _barCount];

	_barSize = [NSTextField labelWithString: @""];
	[_barSize setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _barSize];

	_trashButton = [DIXControls primaryButtonWithTitle:
		NSLocalizedString( @"Move to Trash", @"inspector, reclaim the ticked items" )
												target: self
												action: @selector(trash:)];
	[_trashButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _trashButton];

	[self updateReclaimBar];
}

- (void) setTrashTarget: (id) target action: (SEL) action
{
	_trashTarget = target;
	_trashAction = action;
}

#pragma mark --------contents-----------------

- (void) setDocument: (FileSystemDoc*) document item: (FSItem*) item
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

	if ( document != _document )
	{
		[center removeObserver: self];

		if ( document != nil )
		{
			[center addObserver: self selector: @selector(onBasketChanged:)
						   name: ReclaimBasketChangedNotification object: document];
			[center addObserver: self selector: @selector(reload)
						   name: FSItemsChangedNotification object: document];
		}
	}

	_document = document;
	_item = item;

	[self reload];
}

- (void) reload
{
	NSString *kind = ( _item != nil && ![_item isSpecialItem] ) ? [_item kindName] : nil;

	FileKindStatistic *statistic = ( kind != nil ) ? [_document kindStatisticForKind: kind] : nil;

	//Everything of the kind except the selection itself, largest first. Sorting
	//here rather than trusting the set: the statistic keeps an NSSet, which has
	//no order to trust.
	NSMutableArray<FSItem*> *siblings = [NSMutableArray array];

	for ( FSItem *sibling in [statistic items] )
	{
		if ( sibling != _item )
			[siblings addObject: sibling];
	}

	[siblings sortUsingComparator: ^NSComparisonResult( FSItem *a, FSItem *b )
	{
		const unsigned long long sizeA = [a sizeValue], sizeB = [b sizeValue];

		return ( sizeA == sizeB ) ? NSOrderedSame : ( sizeA > sizeB ? NSOrderedAscending
																	: NSOrderedDescending );
	}];

	_siblings = siblings;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	[_headerLabel setStringValue: ( kind != nil )
		? [[NSString stringWithFormat: NSLocalizedString( @"OTHER %@", @"inspector, the rest of the selection's kind" ), kind] localizedUppercaseString]
		: @""];

	unsigned long long total = 0;
	for ( FSItem *sibling in siblings )
		total += [sibling sizeValue];

	[_headerDetail setStringValue: ( [siblings count] > 0 )
		? [NSString stringWithFormat: NSLocalizedString( @"%lu files · %@", @"inspector, the sibling section's totals" ),
									  (unsigned long) [siblings count],
									  [sizeFormatter stringForObjectValue: @(total)]]
		: @""];

	[self rebuildRows];
	[self updateReclaimBar];
	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) rebuildRows
{
	for ( NSView *view in [[_rowsView subviews] copy] )
		[view removeFromSuperview];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
	const NSUInteger shown = MIN( [_siblings count], kMaximumRows );

	NSRect frame = [_rowsView frame];
	frame.size.height = MAX( kRowHeight * (CGFloat) shown, 1.0 );
	[_rowsView setFrame: frame];

	for ( NSUInteger i = 0; i < shown; i++ )
	{
		FSItem *sibling = [_siblings objectAtIndex: i];

		NSButton *box = [NSButton checkboxWithTitle: [sibling displayName]
											 target: self
											 action: @selector(toggleRow:)];
		[box setTag: (NSInteger) i];
		[box setFont: [NSFont systemFontOfSize: 12.0]];
		[box setState: [_document isItemInBasket: sibling] ? NSControlStateValueOn
														   : NSControlStateValueOff];
		[box setTranslatesAutoresizingMaskIntoConstraints: YES];
		[box setLineBreakMode: NSLineBreakByTruncatingMiddle];
		[_rowsView addSubview: box];

		NSTextField *size = [NSTextField labelWithString:
			[sizeFormatter stringForObjectValue: [sibling size]]];
		[size setFont: [DIXTheme tabularFontOfSize: 11.0]];
		[size setTextColor: [DIXTheme secondaryText]];
		[size setAlignment: NSTextAlignmentRight];
		[size setTag: (NSInteger) ( i + kMaximumRows )];   //so layout can tell them apart
		[size setTranslatesAutoresizingMaskIntoConstraints: YES];
		[_rowsView addSubview: size];
	}
}

- (void) toggleRow: (NSButton*) sender
{
	const NSUInteger index = (NSUInteger) [sender tag];

	if ( index >= [_siblings count] )
		return;

	[_document toggleBasketItem: [_siblings objectAtIndex: index]];
}

- (void) onBasketChanged: (NSNotification*) notification
{
	//Only the boxes and the bar - not the list. Rebuilding the rows on every tick
	//would rebuild the very checkbox being clicked, out from under the click.
	for ( NSView *view in [_rowsView subviews] )
	{
		if ( ![view isKindOfClass: [NSButton class]] )
			continue;

		const NSUInteger index = (NSUInteger) [(NSButton*) view tag];

		if ( index < [_siblings count] )
		{
			[(NSButton*) view setState:
				[_document isItemInBasket: [_siblings objectAtIndex: index]] ? NSControlStateValueOn
																			 : NSControlStateValueOff];
		}
	}

	[self updateReclaimBar];
	[self layoutContents];
}

- (void) updateReclaimBar
{
	const NSUInteger count = [_document basketCount];
	const BOOL visible = ( count > 0 );

	for ( NSView *view in @[ _barRule, _barCount, _barSize, _trashButton ] )
		[view setHidden: !visible];

	//the bar's own fill is drawn by -drawRect:, which hiding a subview does not
	//invalidate on its own
	[self setNeedsDisplay: YES];

	if ( !visible )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	[_barCount setStringValue:
		[NSString stringWithFormat: NSLocalizedString( @"%lu items selected", @"reclaim bar" ),
									(unsigned long) count]];

	[_barSize setAttributedStringValue:
		[[NSAttributedString alloc] initWithString: [sizeFormatter stringForObjectValue: @([_document basketSize])]
										attributes: [DIXTheme displayAttributesOfSize: 17.0
																				color: [DIXTheme ink]]]];
}

- (void) trash: (id) sender
{
	if ( _trashTarget != nil && _trashAction != NULL )
		[NSApp sendAction: _trashAction to: _trashTarget from: self];
}

#pragma mark --------layout-----------------

- (CGFloat) fittingHeight
{
	if ( [_siblings count] == 0 )
		return 0.0;

	const CGFloat rows = kRowHeight * (CGFloat) MIN( [_siblings count], (NSUInteger) 8 );

	return kHeaderHeight + rows + ( [_document basketCount] > 0 ? kBarHeight : 0.0 );
}

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

	[_headerDetail sizeToFit];

	const CGFloat detailWidth = MIN( NSWidth( [_headerDetail frame] ), contentWidth * 0.6 );
	const CGFloat headerY = NSMaxY( bounds ) - kHeaderHeight + 6.0;

	[_headerLabel setFrame: NSMakeRect( kPadding, headerY, contentWidth - detailWidth - 8.0, 16.0 )];
	[_headerDetail setFrame: NSMakeRect( NSMaxX( bounds ) - kPadding - detailWidth, headerY,
										 detailWidth, 16.0 )];

	const CGFloat barHeight = ( [_document basketCount] > 0 ) ? kBarHeight : 0.0;

	[_scrollView setFrame: NSMakeRect( 0.0, barHeight, NSWidth( bounds ),
									   MAX( 0.0, NSHeight( bounds ) - kHeaderHeight - barHeight ) )];

	//rows are laid out from the top of the (unflipped) document view
	const CGFloat rowsHeight = NSHeight( [_rowsView frame] );
	const CGFloat sizeWidth = 64.0;

	NSRect rowsFrame = [_rowsView frame];
	rowsFrame.size.width = NSWidth( [[_scrollView contentView] bounds] );
	[_rowsView setFrame: rowsFrame];

	for ( NSView *view in [_rowsView subviews] )
	{
		const NSUInteger tag = (NSUInteger) [(NSControl*) view tag];
		const BOOL isSize = ( tag >= kMaximumRows );
		const NSUInteger index = isSize ? ( tag - kMaximumRows ) : tag;
		const CGFloat y = rowsHeight - kRowHeight * (CGFloat) ( index + 1 );

		if ( isSize )
		{
			[view setFrame: NSMakeRect( NSWidth( rowsFrame ) - kPadding - sizeWidth,
										y + 5.0, sizeWidth, 16.0 )];
		}
		else
		{
			[view setFrame: NSMakeRect( kPadding, y + 3.0,
										MAX( 0.0, NSWidth( rowsFrame ) - kPadding * 2.0 - sizeWidth - 8.0 ),
										kBoxSize + 4.0 )];
		}
	}

	if ( barHeight > 0.0 )
	{
		[_barRule setFrame: NSMakeRect( 0.0, kBarHeight, NSWidth( bounds ),
										[DIXTheme ruleThickness] )];

		[_barCount setFrame: NSMakeRect( kPadding, kBarHeight - 22.0, contentWidth * 0.5, 14.0 )];
		[_barSize setFrame: NSMakeRect( kPadding, kBarHeight - 44.0, contentWidth * 0.5, 22.0 )];

		[_trashButton setFrame: NSMakeRect( NSMaxX( bounds ) - kPadding - 130.0,
											kBarHeight - 40.0, 130.0, 28.0 )];
	}
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Clamped to bounds - see DIXStatusBarView.
	[[DIXTheme chrome] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	//The reclaim bar is raised off the pane it sits on, in both appearances, so
	//that the rule above it reads as the top of something rather than as a line
	//through the middle of the section. Only while there is something in the
	//basket - the bar is hidden otherwise, and so is its fill.
	if ( ![_barRule isHidden] )
	{
		[[DIXTheme raised] set];

		NSRect bar = [self bounds];
		bar.size.height = kBarHeight;

		NSRectFill( NSIntersectionRect( bar, dirtyRect ) );
	}
}

@end
