//
//  DIXSummaryStripView.m
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

#import "DIXSummaryStripView.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "NSImage-Extensions.h"

static const CGFloat kStripHeight       = 68.0;
static const CGFloat kHorizontalPadding = 16.0;
static const CGFloat kBlockGap          = 18.0;
static const CGFloat kButtonGap         =  8.0;
static const CGFloat kTotalFontSize     = 26.0;
static const CGFloat kDeltaFontSize     = 20.0;
static const CGFloat kButtonHeight      = 26.0;
//The design's zoom buttons are square - 26x26, the same edge as the height
//Rescan is given beside them - so this is deliberately not a width of its own.
#define kIconButtonWidth kButtonHeight
static const CGFloat kRuleHeight        = 36.0;

@interface DIXSummaryStripView()
{
	NSTextField *_totalField;
	NSTextField *_subtitleField;

	NSView      *_deltaRule;
	NSTextField *_deltaField;
	NSTextField *_deltaCaptionField;

	NSButton *_rescanButton;
	NSButton *_zoomInButton;
	NSButton *_zoomOutButton;

	BOOL _hasDelta;
}
@end

@implementation DIXSummaryStripView

+ (CGFloat) preferredHeight
{
	return kStripHeight;
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

//Laid out by hand, not with constraints - a simplicity choice, since these
//frames are one pass of arithmetic. What actually matters for a sibling of
//the nib's views is the fill rule in -drawRect:; the note in DIXStatusBarView
//has the full story.
- (void) buildViewHierarchy
{
	_totalField    = [self label];
	_subtitleField = [self label];
	[_subtitleField setFont: [NSFont systemFontOfSize: 11.0]];
	[_subtitleField setTextColor: [DIXTheme secondaryText]];
	[_subtitleField setLineBreakMode: NSLineBreakByTruncatingTail];

	//A 2pt ink rule, not a hairline: the design is explicit that this divides
	//two different kinds of statement rather than separating list rows.
	_deltaRule = [[NSView alloc] initWithFrame: NSZeroRect];
	[_deltaRule setWantsLayer: YES];
	[[_deltaRule layer] setBackgroundColor: [[DIXTheme rule] CGColor]];

	_deltaField        = [self label];
	_deltaCaptionField = [self label];
	[_deltaCaptionField setFont: [NSFont systemFontOfSize: 11.0]];
	[_deltaCaptionField setTextColor: [DIXTheme secondaryText]];

	_rescanButton = [DIXControls secondaryButtonWithTitle:
		NSLocalizedString( @"Rescan", @"summary strip button" ) target: nil action: NULL];

	//The design puts a refresh glyph before the word. The accessibility
	//description is the title, so VoiceOver reads the button once rather than
	//announcing an image and then a label that say the same thing.
	[_rescanButton setImage: [NSImage imageForSymbolName: @"arrow.clockwise"
								   accessibilityDescription: [_rescanButton title]]];
	[_rescanButton setImagePosition: NSImageLeft];
	[DIXControls setImageTitleGap: 6.0 onButton: _rescanButton];

	[_rescanButton setTranslatesAutoresizingMaskIntoConstraints: YES];

	_zoomInButton  = [self iconButtonWithSymbol: @"plus.magnifyingglass"
										  label: NSLocalizedString( @"Zoom In", @"" )];
	_zoomOutButton = [self iconButtonWithSymbol: @"minus.magnifyingglass"
										  label: NSLocalizedString( @"Zoom Out", @"" )];

	for ( NSView *view in @[ _totalField, _subtitleField, _deltaRule, _deltaField,
							 _deltaCaptionField, _rescanButton, _zoomInButton, _zoomOutButton ] )
		[self addSubview: view];

	[self setTotal: @"" subtitle: @""];
	[self setDelta: nil caption: nil isGrowth: YES];
}

- (NSTextField*) label
{
	NSTextField *field = [NSTextField labelWithString: @""];

	//the label factory turns this off, and off means Auto Layout
	[field setTranslatesAutoresizingMaskIntoConstraints: YES];

	return field;
}

//SF Symbols, resolved through the extension that logs a bad name rather than
//handing back a blank image. Both names exist in SF Symbols 2, which is what
//the macOS 11 deployment target requires.
- (NSButton*) iconButtonWithSymbol: (NSString*) symbolName label: (NSString*) label
{
	//The design draws these as the secondary button: 26x26, the same fill,
	//border and radius as Rescan beside them - not as a bezel of their own.
	NSButton *button = [DIXControls secondaryButtonWithTitle: @"" target: nil action: NULL];

	[button setImage: [NSImage imageForSymbolName: symbolName accessibilityDescription: label]];
	[button setImagePosition: NSImageOnly];
	[button setToolTip: label];
	[button setTranslatesAutoresizingMaskIntoConstraints: YES];

	return button;
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

	// ---- the buttons, from the right ---------------------------------------
	CGFloat right = NSMaxX( bounds ) - kHorizontalPadding;

	[_zoomOutButton setFrame: NSMakeRect( right - kIconButtonWidth, midY - kButtonHeight / 2.0,
										  kIconButtonWidth, kButtonHeight )];
	right = NSMinX( [_zoomOutButton frame] ) - kButtonGap;

	[_zoomInButton setFrame: NSMakeRect( right - kIconButtonWidth, midY - kButtonHeight / 2.0,
										 kIconButtonWidth, kButtonHeight )];
	right = NSMinX( [_zoomInButton frame] ) - kButtonGap;

	[_rescanButton sizeToFit];
	const CGFloat rescanWidth = NSWidth( [_rescanButton frame] );
	[_rescanButton setFrame: NSMakeRect( right - rescanWidth, midY - kButtonHeight / 2.0,
										 rescanWidth, kButtonHeight )];
	right = NSMinX( [_rescanButton frame] ) - kBlockGap;

	// ---- the total and what it is made of ----------------------------------
	[_totalField sizeToFit];
	[_subtitleField sizeToFit];

	const CGFloat totalHeight = NSHeight( [_totalField frame] );
	const CGFloat subtitleHeight = NSHeight( [_subtitleField frame] );
	const CGFloat columnHeight = totalHeight + 2.0 + subtitleHeight;
	const CGFloat columnTop = midY + columnHeight / 2.0;

	[_totalField setFrame: NSMakeRect( kHorizontalPadding, columnTop - totalHeight,
									   NSWidth( [_totalField frame] ), totalHeight )];

	const CGFloat totalBlockWidth = MAX( NSWidth( [_totalField frame] ),
										 NSWidth( [_subtitleField frame] ) );

	[_subtitleField setFrame: NSMakeRect( kHorizontalPadding, columnTop - columnHeight,
										  NSWidth( [_subtitleField frame] ), subtitleHeight )];

	if ( !_hasDelta )
		return;

	// ---- what has changed since last time ----------------------------------
	const CGFloat ruleX = kHorizontalPadding + totalBlockWidth + kBlockGap;

	[_deltaRule setFrame: NSMakeRect( ruleX, midY - kRuleHeight / 2.0,
									  [DIXTheme ruleThickness], kRuleHeight )];

	[_deltaField sizeToFit];
	[_deltaCaptionField sizeToFit];

	const CGFloat deltaHeight = NSHeight( [_deltaField frame] );
	const CGFloat captionHeight = NSHeight( [_deltaCaptionField frame] );
	const CGFloat deltaColumnHeight = deltaHeight + 2.0 + captionHeight;
	const CGFloat deltaTop = midY + deltaColumnHeight / 2.0;

	const CGFloat deltaX = ruleX + [DIXTheme ruleThickness] + kBlockGap;

	[_deltaField setFrame: NSMakeRect( deltaX, deltaTop - deltaHeight,
									   NSWidth( [_deltaField frame] ), deltaHeight )];

	[_deltaCaptionField setFrame: NSMakeRect( deltaX, deltaTop - deltaColumnHeight,
											  NSWidth( [_deltaCaptionField frame] ), captionHeight )];
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Fill only what this view owns, never the dirty rect as handed in. Since
	//macOS 14 views no longer clip to their bounds by default, and this view
	//shares the window's backing layer with the nib's autoresizing-mask views -
	//so during a full-window display pass the dirty rect arrives here spanning
	//the entire content view. Filling it painted this background over every
	//sibling that had already drawn, which blanked the whole window.
	[[DIXTheme surface] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	//hairline along the bottom, between the strip and the map
	NSRect line = [self bounds];
	line.size.height = 1.0;

	//the lighter content weight: this divides one pane, where -hairline
	//is the edge *between* panes - between the strip and the map, inside the centre column
	[[DIXTheme contentHairline] set];
	NSRectFill( NSIntersectionRect( line, dirtyRect ) );
}

#pragma mark --------contents-----------------

- (void) setTotal: (NSString*) total subtitle: (NSString*) subtitle
{
	//Drawn from an attributed string rather than a plain one, because the
	//design's tracking is a kern attribute and no font trait carries it.
	[_totalField setAttributedStringValue:
		[[NSAttributedString alloc] initWithString: total != nil ? total : @""
										attributes: [DIXTheme displayAttributesOfSize: kTotalFontSize
																				color: [DIXTheme ink]]]];

	[_subtitleField setStringValue: subtitle != nil ? subtitle : @""];

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) setDelta: (NSString*) delta caption: (NSString*) caption isGrowth: (BOOL) isGrowth
{
	_hasDelta = [delta length] > 0;

	[_deltaRule setHidden: !_hasDelta];
	[_deltaField setHidden: !_hasDelta];
	[_deltaCaptionField setHidden: !_hasDelta];

	if ( _hasDelta )
	{
		//growth is the accent, shrinkage is the positive colour - the point of
		//the view is that growth is what you came to find
		NSColor *color = isGrowth ? [DIXTheme accent] : [DIXTheme positive];

		[_deltaField setAttributedStringValue:
			[[NSAttributedString alloc] initWithString: delta
											attributes: [DIXTheme displayAttributesOfSize: kDeltaFontSize
																					color: color]]];

		[_deltaCaptionField setStringValue: caption != nil ? caption : @""];
	}

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) setTarget: (id) target
	  rescanAction: (SEL) rescanAction
	  zoomInAction: (SEL) zoomInAction
	 zoomOutAction: (SEL) zoomOutAction
{
	[_rescanButton setTarget: target];
	[_rescanButton setAction: rescanAction];

	[_zoomInButton setTarget: target];
	[_zoomInButton setAction: zoomInAction];

	[_zoomOutButton setTarget: target];
	[_zoomOutButton setAction: zoomOutAction];
}

- (void) setZoomInEnabled: (BOOL) zoomIn zoomOutEnabled: (BOOL) zoomOut
{
	[_zoomInButton setEnabled: zoomIn];
	[_zoomOutButton setEnabled: zoomOut];
}

@end
