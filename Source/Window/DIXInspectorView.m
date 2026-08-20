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
#import "DIXSiblingsView.h"

static const CGFloat kInspectorWidth   = 300.0;
static const CGFloat kPadding          =  16.0;
static const CGFloat kIconSize         =  52.0;
static const CGFloat kIconToTextGap    =  12.0;
static const CGFloat kButtonHeight     =  28.0;
static const CGFloat kButtonGap        =   8.0;
static const CGFloat kHeaderBottomGap  =  14.0;

//Breathing space under the attribute rows, before the rule that starts the
//siblings section. On top of the 12 the block already keeps inside itself, so
//the last row sits in 36 points of air.
static const CGFloat kInfoBottomGap    =  24.0;

@interface DIXInspectorView()
{
	NSImageView *_iconView;
	NSTextField *_nameField;
	NSTextField *_sizeField;

	NSButton *_revealButton;
	NSButton *_openButton;
	NSButton *_trashButton;

	DIXFileInfoView *_infoView;
	DIXSiblingsView *_siblingsView;
	__weak FileSystemDoc *_document;

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
	[_infoView setUsesInspectorLayout: YES];

	_siblingsView = [[DIXSiblingsView alloc] initWithFrame: NSZeroRect];

	//What the pane says when nothing is selected. The floating panel it replaces
	//simply went blank, which read as broken rather than as empty.
	_emptyLabel = [NSTextField labelWithString:
		NSLocalizedString( @"Nothing selected", @"inspector, with no selection" )];
	[_emptyLabel setFont: [NSFont systemFontOfSize: 13.0]];
	[_emptyLabel setTextColor: [DIXTheme tertiaryText]];
	[_emptyLabel setAlignment: NSTextAlignmentCenter];
	[_emptyLabel setTranslatesAutoresizingMaskIntoConstraints: YES];

	for ( NSView *view in @[ _iconView, _nameField, _sizeField, _revealButton,
							 _openButton, _trashButton, _infoView, _siblingsView, _emptyLabel ] )
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

		//The attribute block takes the height its rows need and the siblings list
		//takes everything left.
		//
		//It used to be the other way round - the list capped at 55% and the block
		//given the rest - which put a column of empty space under seven rows
		//whenever the list was long, which is most of the time. The block's
		//height is a property of its content: seven rows are seven rows however
		//tall the pane is, and there is nothing for the spare space to do up
		//there. A list, on the other hand, is always glad of another row.
		const CGFloat available = MAX( 0.0, top - NSMinY( bounds ) );
		const CGFloat siblingsFitting = [_siblingsView fittingHeight];

		//A third is the floor, for a Where or an Opens with long enough to wrap
		//several times; the block scrolls past that rather than crowding the list
		//off the bottom.
		//kInfoBottomGap on top of what the rows measure. The grid already carries
		//the design's 12pt padding inside its own frame, and once the block stops
		//being oversized that padding is all that stands between the last row and
		//the rule under it - which reads as the rows having been cut off there.
		const CGFloat infoHeight = ( siblingsFitting > 0.0 )
			? MIN( [_infoView fittingHeight] + kInfoBottomGap, available * 0.67 )
			: available;

		const CGFloat siblingsHeight = MAX( 0.0, available - infoHeight );

		[_siblingsView setFrame: NSMakeRect( 0.0, NSMinY( bounds ), NSWidth( bounds ),
											 siblingsHeight )];

		[_infoView setFrame: NSMakeRect( 0.0, NSMinY( bounds ) + siblingsHeight, NSWidth( bounds ),
										 top - NSMinY( bounds ) - siblingsHeight )];
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

	//No hairline down the leading edge. This pane is a split view subview and
	//the divider beside it already draws one, in the same tone - two of them
	//read as a 2pt border here where the sidebar, which draws none of its own,
	//gets the single line the design has.

	//Two rules across it: under the header block, and under the attribute rows.
	//Without them the three sections run together into one column of text, which
	//is what the design uses these lines to prevent. They are the lighter
	//content weight, not the pane border above - a division inside a pane should
	//not read as strongly as the edge of one.
	//
	//Taken from the section frames rather than recomputed, so a change to
	//-layoutContents cannot leave a rule floating where a section used to end.
	if ( [_emptyLabel isHidden] )
	{
		const CGFloat thickness = [DIXTheme hairlineThickness];

		[[DIXTheme contentHairline] set];

		for ( NSView *section in @[ _infoView, _siblingsView ] )
		{
			if ( [section isHidden] || NSHeight( [section frame] ) <= 0.0 )
				continue;

			NSRect rule = NSMakeRect( NSMinX( [self bounds] ), NSMaxY( [section frame] ),
									  NSWidth( [self bounds] ), thickness );

			NSRectFill( NSIntersectionRect( rule, dirtyRect ) );
		}
	}
}

#pragma mark --------contents-----------------

- (void) setItem: (FSItem*) item
{
	const BOOL empty = ( item == nil );

	for ( NSView *view in @[ _iconView, _nameField, _sizeField,
							 _revealButton, _openButton, _trashButton, _infoView, _siblingsView ] )
		[view setHidden: empty];

	[_emptyLabel setHidden: !empty];

	[_siblingsView setDocument: _document item: empty ? nil : item];

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

- (void) setDocument: (FileSystemDoc*) document
{
	_document = document;
	[_siblingsView setDocument: document item: nil];
}

- (void) setReclaimTarget: (id) target action: (SEL) action
{
	[_siblingsView setTrashTarget: target action: action];
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
