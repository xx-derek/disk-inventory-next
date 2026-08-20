//
//  DIXInspectorView.m
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

#import "DIXInspectorView.h"
#import "DIXFileInfoView.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "FSItem.h"
#import "FileSizeFormatter.h"

static const CGFloat kInspectorWidth   = 300.0;
static const CGFloat kPadding          =  16.0;
static const CGFloat kIconSize         =  52.0;
static const CGFloat kIconToTextGap    =  12.0;
static const CGFloat kButtonHeight     =  28.0;
static const CGFloat kButtonGap        =   8.0;
static const CGFloat kHeaderBottomGap  =  14.0;

@interface DIXInspectorView()
{
	NSImageView *_iconView;
	NSTextField *_nameField;
	NSTextField *_sizeField;

	NSButton *_revealButton;
	NSButton *_openButton;
	NSButton *_trashButton;

	DIXFileInfoView *_infoView;

	NSTextField *_emptyLabel;
}
@end

@implementation DIXInspectorView

+ (CGFloat) preferredWidth
{
	return kInspectorWidth;
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

//Laid out by hand. DIXFileInfoView brings its own constraints, which is fine -
//they are its own business and stop at its bounds - but this view is a sibling
//of the nib's autoresizing views, so it positions its own children with frames.
//See the note in DIXStatusBarView about what -drawRect: must not do here.
- (void) buildViewHierarchy
{
	_iconView = [[NSImageView alloc] initWithFrame: NSZeroRect];
	[_iconView setImageScaling: NSImageScaleProportionallyUpOrDown];

	_nameField = [NSTextField labelWithString: @""];
	[_nameField setFont: [NSFont systemFontOfSize: 14.0 weight: NSFontWeightSemibold]];
	[_nameField setTextColor: [DIXTheme ink]];
	[_nameField setLineBreakMode: NSLineBreakByTruncatingTail];
	[_nameField setTranslatesAutoresizingMaskIntoConstraints: YES];

	_sizeField = [NSTextField labelWithString: @""];
	[_sizeField setTranslatesAutoresizingMaskIntoConstraints: YES];

	//The trash button is the destructive one and the design makes it the solid
	//accent; the other two are ordinary bordered buttons.
	_revealButton = [DIXControls secondaryButtonWithTitle:
		NSLocalizedString( @"Reveal", @"inspector button" ) target: nil action: NULL];
	_openButton = [DIXControls secondaryButtonWithTitle:
		NSLocalizedString( @"Open", @"inspector button" ) target: nil action: NULL];
	_trashButton = [DIXControls primaryButtonWithTitle:
		NSLocalizedString( @"Trash", @"inspector button" ) target: nil action: NULL];

	for ( NSButton *button in @[ _revealButton, _openButton, _trashButton ] )
		[button setTranslatesAutoresizingMaskIntoConstraints: YES];

	_infoView = [[DIXFileInfoView alloc] initWithFrame: NSZeroRect];

	//What the pane says when nothing is selected. The floating panel it replaces
	//simply went blank, which read as broken rather than as empty.
	_emptyLabel = [NSTextField labelWithString:
		NSLocalizedString( @"Nothing selected", @"inspector, with no selection" )];
	[_emptyLabel setFont: [NSFont systemFontOfSize: 13.0]];
	[_emptyLabel setTextColor: [DIXTheme tertiaryText]];
	[_emptyLabel setAlignment: NSTextAlignmentCenter];
	[_emptyLabel setTranslatesAutoresizingMaskIntoConstraints: YES];

	for ( NSView *view in @[ _iconView, _nameField, _sizeField, _revealButton,
							 _openButton, _trashButton, _infoView, _emptyLabel ] )
		[self addSubview: view];

	[self setItem: nil];
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

	//the view is unflipped, so laying out from the top means counting down
	CGFloat top = NSMaxY( bounds ) - kPadding;

	if ( [_emptyLabel isHidden] )
	{
		[_iconView setFrame: NSMakeRect( kPadding, top - kIconSize, kIconSize, kIconSize )];

		const CGFloat textX = kPadding + kIconSize + kIconToTextGap;
		const CGFloat textWidth = NSMaxX( bounds ) - kPadding - textX;

		[_nameField sizeToFit];
		[_sizeField sizeToFit];

		const CGFloat nameHeight = NSHeight( [_nameField frame] );
		const CGFloat sizeHeight = NSHeight( [_sizeField frame] );
		const CGFloat block = nameHeight + 4.0 + sizeHeight;
		const CGFloat blockTop = top - ( kIconSize - block ) / 2.0;

		[_nameField setFrame: NSMakeRect( textX, blockTop - nameHeight, textWidth, nameHeight )];
		[_sizeField setFrame: NSMakeRect( textX, blockTop - block, textWidth, sizeHeight )];

		top -= kIconSize + kHeaderBottomGap;

		//three equal buttons across the pane
		const CGFloat buttonWidth = floor( ( contentWidth - kButtonGap * 2.0 ) / 3.0 );

		[_revealButton setFrame: NSMakeRect( kPadding, top - kButtonHeight,
											 buttonWidth, kButtonHeight )];
		[_openButton setFrame: NSMakeRect( kPadding + buttonWidth + kButtonGap, top - kButtonHeight,
										   buttonWidth, kButtonHeight )];
		//the last one takes the rounding, so the row ends flush with the margin
		[_trashButton setFrame: NSMakeRect( kPadding + ( buttonWidth + kButtonGap ) * 2.0,
											top - kButtonHeight,
											contentWidth - ( buttonWidth + kButtonGap ) * 2.0,
											kButtonHeight )];

		top -= kButtonHeight + kHeaderBottomGap;

		[_infoView setFrame: NSMakeRect( 0.0, NSMinY( bounds ), NSWidth( bounds ),
										 top - NSMinY( bounds ) )];
	}
	else
	{
		[_emptyLabel sizeToFit];

		const CGFloat height = NSHeight( [_emptyLabel frame] );

		[_emptyLabel setFrame: NSMakeRect( kPadding, NSMidY( bounds ) - height / 2.0,
										   contentWidth, height )];
	}
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Clamped to this view's bounds. The dirty rect handed to a view without its
	//own backing layer can span the whole window, and filling it paints over
	//every sibling drawn before this one - see DIXStatusBarView.
	[[DIXTheme chrome] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	//hairline down the leading edge, separating the pane from the map
	NSRect line = [self bounds];
	line.size.width = 1.0;

	[[DIXTheme hairline] set];
	NSRectFill( NSIntersectionRect( line, dirtyRect ) );
}

#pragma mark --------contents-----------------

- (void) setItem: (FSItem*) item
{
	const BOOL empty = ( item == nil );

	for ( NSView *view in @[ _iconView, _nameField, _sizeField,
							 _revealButton, _openButton, _trashButton, _infoView ] )
		[view setHidden: empty];

	[_emptyLabel setHidden: !empty];

	if ( empty )
	{
		//The URL is cleared too, so a stale set of rows is not sitting behind
		//the empty label waiting to be shown again.
		[_infoView setURL: nil];
	}
	else
	{
		[_iconView setImage: [item iconWithSize: (unsigned) kIconSize]];
		[_nameField setStringValue: [item displayName]];

		FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

		[_sizeField setAttributedStringValue:
			[[NSAttributedString alloc] initWithString: [sizeFormatter stringForObjectValue: [item size]]
											attributes: [DIXTheme displayAttributesOfSize: 20.0
																					color: [DIXTheme ink]]]];

		//Special items - free space, space used elsewhere - have no file behind
		//them, so there is nothing for the attribute rows to read.
		[_infoView setURL: [item isSpecialItem] ? nil : [item fileURL]];
	}

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) setTarget: (id) target
	  revealAction: (SEL) revealAction
		openAction: (SEL) openAction
	   trashAction: (SEL) trashAction
{
	[_revealButton setTarget: target];
	[_revealButton setAction: revealAction];

	[_openButton setTarget: target];
	[_openButton setAction: openAction];

	[_trashButton setTarget: target];
	[_trashButton setAction: trashAction];
}

- (void) setRevealEnabled: (BOOL) reveal openEnabled: (BOOL) open trashEnabled: (BOOL) trash
{
	[_revealButton setEnabled: reveal];
	[_openButton setEnabled: open];
	[_trashButton setEnabled: trash];
}

@end
