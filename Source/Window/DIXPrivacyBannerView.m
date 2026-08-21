//
//  DIXPrivacyBannerView.m
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

#import "DIXPrivacyBannerView.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "NSImage-Extensions.h"

//The design's own numbers for this banner.
static const CGFloat kEdgeInset      = 16.0;
static const CGFloat kTopInset       = 14.0;
static const CGFloat kBorderWidth    =  4.0;   //the accent bar down the left
static const CGFloat kTitleGap       =  8.0;
static const CGFloat kButtonsGapTop  = 14.0;
static const CGFloat kButtonHeight   = 30.0;
static const CGFloat kButtonGap      =  8.0;
static const CGFloat kListGapTop     = 14.0;
static const CGFloat kListRowHeight  = 30.0;

@implementation DIXPrivacyBannerView
{
	NSTextField *_titleField;
	NSTextField *_bodyField;

	NSButton *_settingsButton;
	NSButton *_scanButton;
	NSButton *_dismissButton;

	NSMutableArray<NSImageView*> *_lockViews;
	NSMutableArray<NSTextField*> *_nameFields;
	NSMutableArray<NSTextField*> *_stateFields;

	NSArray<NSURL*> *_folders;
}

//Measured rather than guessed at, because the body wraps: the whole point of
//the sentence is the total it names, and a banner that cut it off would be
//worse than the alert it replaces.
- (CGFloat) preferredHeightForWidth: (CGFloat) width
{
	const NSUInteger count = [_folders count];

	if ( count == 0 )
		return 0.0;

	const CGFloat textWidth = width - kBorderWidth - kEdgeInset * 2.0;

	[_titleField sizeToFit];

	const CGFloat bodyHeight = [[_bodyField cell] cellSizeForBounds:
		NSMakeRect( 0.0, 0.0, textWidth, CGFLOAT_MAX )].height;

	return kTopInset + NSHeight( [_titleField frame] ) + kTitleGap + bodyHeight
		   + kButtonsGapTop + kButtonHeight
		   + kListGapTop + kListRowHeight * (CGFloat) count
		   + kTopInset;
}

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_lockViews  = [NSMutableArray array];
		_nameFields = [NSMutableArray array];
		_stateFields = [NSMutableArray array];

		_titleField = [NSTextField labelWithString: @""];
		[_titleField setFont: [NSFont systemFontOfSize: 13.0 weight: NSFontWeightSemibold]];
		[_titleField setTextColor: [DIXTheme ink]];
		[_titleField setTranslatesAutoresizingMaskIntoConstraints: YES];
		[self addSubview: _titleField];

		_bodyField = [NSTextField wrappingLabelWithString: @""];
		[_bodyField setFont: [NSFont systemFontOfSize: 13.0]];
		[_bodyField setTextColor: [DIXTheme bodyText]];
		[_bodyField setSelectable: NO];
		[_bodyField setTranslatesAutoresizingMaskIntoConstraints: YES];
		[self addSubview: _bodyField];

		//Solid accent: granting the permission is the thing that fixes this, and
		//the other two only decide how to live without it.
		_settingsButton = [DIXControls primaryButtonWithTitle:
			NSLocalizedString( @"Open Privacy Settings", @"privacy banner" )
													   target: nil action: NULL];

		_scanButton = [DIXControls secondaryButtonWithTitle:
			NSLocalizedString( @"Scan Them Anyway", @"privacy banner" )
													 target: nil action: NULL];

		//Plain text, no border: the design draws it as the way out rather than
		//as a third thing to weigh up.
		_dismissButton = [NSButton buttonWithTitle:
			NSLocalizedString( @"Dismiss", @"privacy banner" ) target: nil action: NULL];
		[_dismissButton setBordered: NO];
		[_dismissButton setButtonType: NSButtonTypeMomentaryChange];
		[_dismissButton setContentTintColor: [DIXTheme secondaryText]];

		for ( NSButton *button in @[ _settingsButton, _scanButton, _dismissButton ] )
		{
			[button setTranslatesAutoresizingMaskIntoConstraints: YES];
			[self addSubview: button];
		}
	}

	return self;
}

#pragma mark --------contents-----------------

- (void) setSkippedFolders: (NSArray<NSURL*>*) folders totalShown: (NSString*) totalShown
{
	_folders = folders;

	for ( NSView *view in [_lockViews arrayByAddingObjectsFromArray: _nameFields] )
		[view removeFromSuperview];

	for ( NSView *view in _stateFields )
		[view removeFromSuperview];

	[_lockViews removeAllObjects];
	[_nameFields removeAllObjects];
	[_stateFields removeAllObjects];

	const NSUInteger count = [folders count];

	[_titleField setStringValue: ( count == 1 )
		? NSLocalizedString( @"1 folder was skipped", @"privacy banner" )
		: [NSString stringWithFormat:
			NSLocalizedString( @"%lu folders were skipped", @"privacy banner" ),
			(unsigned long) count]];

	//The names, listed rather than counted: "Desktop, Documents and Downloads"
	//is what tells someone whether the missing part is one they care about.
	NSMutableArray<NSString*> *names = [NSMutableArray array];

	for ( NSURL *folder in folders )
		[names addObject: [[NSFileManager defaultManager] displayNameAtPath: [folder path]]];

	NSString *list = ( [names count] > 1 )
		? [NSString stringWithFormat: @"%@ %@ %@",
			[[names subarrayWithRange: NSMakeRange( 0, [names count] - 1 )]
				componentsJoinedByString: @", "],
			NSLocalizedString( @"and", @"privacy banner, joining the last folder name" ),
			[names lastObject]]
		: [names firstObject] ?: @"";

	[_bodyField setStringValue: [NSString stringWithFormat:
		NSLocalizedString( @"macOS protects %@. They are not counted in the %@ below.",
						   @"privacy banner" ), list, totalShown ?: @""]];

	for ( NSURL *folder in folders )
	{
		NSImageView *lock = [NSImageView imageViewWithImage:
			[NSImage imageForSymbolName: @"lock" accessibilityDescription:
				NSLocalizedString( @"not counted", @"privacy banner" )] ?: [[NSImage alloc] init]];

		[lock setContentTintColor: [DIXTheme secondaryText]];
		[lock setTranslatesAutoresizingMaskIntoConstraints: YES];
		[self addSubview: lock];
		[_lockViews addObject: lock];

		NSTextField *name = [NSTextField labelWithString:
			[[NSFileManager defaultManager] displayNameAtPath: [folder path]]];
		[name setFont: [NSFont systemFontOfSize: 13.0]];
		[name setTextColor: [DIXTheme ink]];
		[name setLineBreakMode: NSLineBreakByTruncatingMiddle];
		[name setTranslatesAutoresizingMaskIntoConstraints: YES];
		[self addSubview: name];
		[_nameFields addObject: name];

		NSTextField *state = [NSTextField labelWithString:
			NSLocalizedString( @"not counted", @"privacy banner" )];
		[state setFont: [NSFont systemFontOfSize: 13.0]];
		[state setTextColor: [DIXTheme secondaryText]];
		[state setAlignment: NSTextAlignmentRight];
		[state setTranslatesAutoresizingMaskIntoConstraints: YES];
		[self addSubview: state];
		[_stateFields addObject: state];
	}

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) setTarget: (id) target
	  settingsAction: (SEL) settingsAction
	     scanAction: (SEL) scanAction
	  dismissAction: (SEL) dismissAction
{
	[_settingsButton setTarget: target];
	[_settingsButton setAction: settingsAction];

	[_scanButton setTarget: target];
	[_scanButton setAction: scanAction];

	[_dismissButton setTarget: target];
	[_dismissButton setAction: dismissAction];
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
	const CGFloat left = kBorderWidth + kEdgeInset;
	const CGFloat textWidth = NSWidth( bounds ) - left - kEdgeInset;

	if ( textWidth <= 0.0 )
		return;

	[_titleField sizeToFit];

	CGFloat top = NSMaxY( bounds ) - kTopInset;

	[_titleField setFrame: NSMakeRect( left, top - NSHeight( [_titleField frame] ),
									   textWidth, NSHeight( [_titleField frame] ) )];

	top -= NSHeight( [_titleField frame] ) + kTitleGap;

	const CGFloat bodyHeight = [[_bodyField cell] cellSizeForBounds:
		NSMakeRect( 0.0, 0.0, textWidth, CGFLOAT_MAX )].height;

	[_bodyField setFrame: NSMakeRect( left, top - bodyHeight, textWidth, bodyHeight )];

	top -= bodyHeight + kButtonsGapTop;

	CGFloat x = left;

	for ( NSButton *button in @[ _settingsButton, _scanButton, _dismissButton ] )
	{
		[button sizeToFit];

		[button setFrame: NSMakeRect( x, top - kButtonHeight,
									  NSWidth( [button frame] ), kButtonHeight )];

		x = NSMaxX( [button frame] ) + kButtonGap;
	}

	top -= kButtonHeight + kListGapTop;

	for ( NSUInteger i = 0; i < [_lockViews count]; i++ )
	{
		const CGFloat rowTop = top - kListRowHeight * (CGFloat) i;
		const CGFloat midY = rowTop - kListRowHeight / 2.0;

		[[_lockViews objectAtIndex: i] setFrame: NSMakeRect( left, midY - 7.0, 14.0, 14.0 )];

		NSTextField *state = [_stateFields objectAtIndex: i];
		[state sizeToFit];

		[state setFrame: NSMakeRect( NSMaxX( bounds ) - kEdgeInset - NSWidth( [state frame] ),
									 midY - NSHeight( [state frame] ) / 2.0,
									 NSWidth( [state frame] ), NSHeight( [state frame] ) )];

		NSTextField *name = [_nameFields objectAtIndex: i];
		[name sizeToFit];

		const CGFloat nameX = left + 14.0 + 10.0;

		[name setFrame: NSMakeRect( nameX, midY - NSHeight( [name frame] ) / 2.0,
									MAX( 0.0, NSMinX( [state frame] ) - 10.0 - nameX ),
									NSHeight( [name frame] ) )];
	}
}

- (void) drawRect: (NSRect) dirtyRect
{
	const NSRect bounds = [self bounds];

	[[DIXTheme accentTint] set];
	NSRectFill( NSIntersectionRect( dirtyRect, bounds ) );

	//4pt of accent down the left edge, which is the whole of the banner's
	//colour beyond its tint - a border all the way round would make it a box.
	NSRect border = bounds;
	border.size.width = kBorderWidth;

	[[DIXTheme accent] set];
	NSRectFill( NSIntersectionRect( border, dirtyRect ) );

	//and a 1pt line under each listed folder but the last, matching every other
	//list in the window
	const CGFloat left = kBorderWidth + kEdgeInset;

	[[DIXTheme rowSeparator] set];

	for ( NSUInteger i = 0; i + 1 < [_lockViews count]; i++ )
	{
		NSRect line = NSMakeRect( left,
								  NSMinY( [[_lockViews objectAtIndex: i] frame] ) - 7.0
									  - [DIXTheme hairlineThickness],
								  NSWidth( bounds ) - left - kEdgeInset,
								  [DIXTheme hairlineThickness] );

		NSRectFill( NSIntersectionRect( line, dirtyRect ) );
	}
}

@end
