//
//  DIXStatusBarView.m
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

#import "DIXStatusBarView.h"
#import "DIXTheme.h"
#import "DIXControls.h"

static const CGFloat kStatusBarHeight   = 42.0;
static const CGFloat kHorizontalPadding = 14.0;
static const CGFloat kChipToNameGap     =  8.0;
static const CGFloat kNameToDetailGap   = 10.0;
static const NSTimeInterval kFlashDuration = 4.0;

@interface DIXStatusBarView()
{
	NSView      *_chip;
	NSTextField *_nameField;
	NSTextField *_detailField;
	NSTextField *_hintField;

	NSColor  *_chipColor;
	NSString *_idleSummary;
	NSString *_idleDetail;
	BOOL _showingItem;
	NSString *_hint;
	NSTimer  *_flashTimer;
}
@end

@implementation DIXStatusBarView

+ (CGFloat) preferredHeight
{
	return kStatusBarHeight;
}

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
	//NSTimer retains its target, so a flash still in flight would keep this view
	//- and the window behind it - alive after the window closed
	[_flashTimer invalidate];
}

//Everything here is positioned by hand rather than with constraints. That is
//a simplicity choice, not a requirement - an earlier version of this comment
//blamed Auto Layout for blanking the nib's sibling views, and that was wrong.
//
//The real rule for these chrome views is in -drawRect:. They are siblings of
//the views TreeMap.nib positions with autoresizing masks, and none of these
//views has a backing layer of its own - they all draw into the window's one
//shared layer, and since macOS 14 none of them clips drawing to its bounds.
//During a full-window display pass -drawRect: is therefore handed a dirty
//rect spanning the entire content view, and filling it paints this view's
//background over every sibling drawn earlier in the same pass. The window
//then comes up empty apart from the chrome, with every frame correct and an
//offscreen -cacheDisplayInRect: probe rendering fine - which is what made it
//look like a layout-system conflict. It is not one: measured on macOS 26, a
//sibling using activated constraints but no -drawRect: leaves the nib's views
//painting, and this view with hand layout blanked them until its fill was
//clamped to its own bounds. The earlier bisection was confounded - every
//"constraints" variant under test also carried the overfilling -drawRect:.
- (void) buildViewHierarchy
{
	_chip = [[NSView alloc] initWithFrame: NSZeroRect];
	[_chip setWantsLayer: YES];
	[_chip setHidden: YES];

	_nameField = [self labelWithSize: 12.0 weight: NSFontWeightMedium color: [DIXTheme ink]];
	[_nameField setLineBreakMode: NSLineBreakByTruncatingMiddle];

	_detailField = [self labelWithSize: 12.0 weight: NSFontWeightRegular color: [DIXTheme secondaryText]];
	[_detailField setLineBreakMode: NSLineBreakByTruncatingTail];

	_hintField = [self labelWithSize: 11.0 weight: NSFontWeightRegular color: [DIXTheme tertiaryText]];
	[_hintField setAlignment: NSTextAlignmentRight];
	[_hintField setLineBreakMode: NSLineBreakByTruncatingTail];

	for ( NSView *view in @[ _chip, _nameField, _detailField, _hintField ] )
		[self addSubview: view];

	[self clearItem];
}

- (NSTextField*) labelWithSize: (CGFloat) size weight: (NSFontWeight) weight color: (NSColor*) color
{
	NSTextField *field = [NSTextField labelWithString: @""];

	[field setFont: [NSFont systemFontOfSize: size weight: weight]];
	[field setTextColor: color];

	//the label factory turns this off, and off means Auto Layout
	[field setTranslatesAutoresizingMaskIntoConstraints: YES];

	return field;
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
	const CGFloat midY = NSMidY( bounds );

	//11, not [DIXTheme kindChipSize]: the legend's chip is 10 and this one is
	//11 in the design - they sit at different sizes of text
	const CGFloat chipSize = 11.0;
	CGFloat x = kHorizontalPadding;

	[_chip setFrame: NSMakeRect( x, midY - chipSize / 2.0, chipSize, chipSize )];

	if ( ![_chip isHidden] )
		x += chipSize + kChipToNameGap;

	//The hint is measured first and given its width off the right-hand edge, so
	//that what gets squeezed as the window narrows is the file name - the hint
	//is short and fixed, and the detail carries the share, which is the number
	//worth keeping.
	[_hintField sizeToFit];
	CGFloat hintWidth = NSWidth( [_hintField frame] );
	const CGFloat hintX = NSMaxX( bounds ) - kHorizontalPadding - hintWidth;

	[_hintField setFrame: NSMakeRect( hintX, midY - NSHeight([_hintField frame]) / 2.0,
									  hintWidth, NSHeight([_hintField frame]) )];

	[_nameField sizeToFit];
	[_detailField sizeToFit];

	const CGFloat available = hintX - kNameToDetailGap - x;
	const CGFloat detailWidth = MIN( NSWidth( [_detailField frame] ), MAX( 0.0, available ) );
	const CGFloat nameWidth = MAX( 0.0, MIN( NSWidth( [_nameField frame] ),
											 available - detailWidth - kNameToDetailGap ) );

	[_nameField setFrame: NSMakeRect( x, midY - NSHeight([_nameField frame]) / 2.0,
									  nameWidth, NSHeight([_nameField frame]) )];

	[_detailField setFrame: NSMakeRect( x + nameWidth + kNameToDetailGap,
										midY - NSHeight([_detailField frame]) / 2.0,
										detailWidth, NSHeight([_detailField frame]) )];
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Fill only what this view owns - see the note in DIXSummaryStripView's
	//-drawRect:. The dirty rect can span the whole content view here, and
	//filling it blanks every sibling drawn before this one.
	[[DIXTheme chrome] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	//hairline along the top edge, separating the bar from the map above it
	NSRect line = [self bounds];
	line.size.height = 1.0;

	//the view is unflipped, so its top edge is at the maximum y
	line.origin.y = NSMaxY( [self bounds] ) - 1.0;

	//the lighter content weight: this divides one pane, where -hairline
	//is the edge *between* panes - between the map and the bar, inside the centre column
	[[DIXTheme contentHairline] set];
	NSRectFill( NSIntersectionRect( line, dirtyRect ) );
}

#pragma mark --------contents-----------------

- (void) setItemName: (NSString*) name detail: (NSString*) detail kindColor: (NSColor*) kindColor
{
	if ( [name length] == 0 )
	{
		[self clearItem];
		return;
	}

	[_nameField setStringValue: name];
	[_detailField setStringValue: detail != nil ? detail : @""];

	//No chip for the synthetic cells: free space and space used elsewhere are
	//not file kinds, and giving them a colour chip would put them in the
	//sidebar's legend, which binds those colours to named kinds.
	_showingItem = YES;

	_chipColor = kindColor;
	[_chip setHidden: kindColor == nil];
	[[_chip layer] setBackgroundColor: [kindColor CGColor]];

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) clearItem
{
	//Not blank: the idle line takes the space back when there is one. It uses
	//the same two fields as a hovered cell so it inherits the same hierarchy -
	//the count reads as the name, the size and share as the detail.
	_showingItem = NO;

	[_nameField setStringValue: _idleSummary != nil ? _idleSummary : @""];
	[_detailField setStringValue: _idleDetail != nil ? _idleDetail : @""];

	//No chip. The idle line spans every kind at once, and a chip would claim
	//one of them.
	_chipColor = nil;
	[_chip setHidden: YES];

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) setIdleSummary: (NSString*) summary detail: (NSString*) detail
{
	_idleSummary = [summary copy];
	_idleDetail = [detail copy];

	//Only if nothing is being hovered right now - otherwise this would yank the
	//readout out from under the pointer. A resize can rebuild the layout while
	//the pointer sits on a cell, and that is exactly when it happens. The test
	//is an explicit flag and not "is there a chip", because the two synthetic
	//cells are hovered items that have no chip.
	if ( !_showingItem )
		[self clearItem];
}

- (void) setHint: (NSString*) hint
{
	_hint = [hint copy];

	//a flash is showing; it will put this back when it expires
	if ( _flashTimer == nil )
	{
		[_hintField setStringValue: _hint != nil ? _hint : @""];
		[self layoutContents];
	}
}

- (void) flashMessage: (NSString*) message
{
	[_flashTimer invalidate];
	_flashTimer = nil;

	if ( [message length] == 0 )
	{
		[_hintField setStringValue: _hint != nil ? _hint : @""];
		[_hintField setTextColor: [DIXTheme tertiaryText]];
		[self layoutContents];
		return;
	}

	[_hintField setStringValue: message];
	[_hintField setTextColor: [DIXTheme accent]];
	[self layoutContents];

	__weak DIXStatusBarView *weakSelf = self;

	_flashTimer = [NSTimer scheduledTimerWithTimeInterval: kFlashDuration
												  repeats: NO
													block: ^( NSTimer *timer )
	{
		DIXStatusBarView *strongSelf = weakSelf;
		if ( strongSelf == nil )
			return;

		strongSelf->_flashTimer = nil;
		[strongSelf->_hintField setTextColor: [DIXTheme tertiaryText]];
		[strongSelf->_hintField setStringValue: strongSelf->_hint != nil ? strongSelf->_hint : @""];
		[strongSelf layoutContents];
	}];
}

@end
