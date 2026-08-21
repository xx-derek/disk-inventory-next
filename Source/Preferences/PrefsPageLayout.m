//
//  PrefsPageLayout.m
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

#import "PrefsPageLayout.h"
#import "DIXTheme.h"
#import "DIXControls.h"

//the strings table the page text is localized in
static NSString * const PrefsTitlesTable = @"Preferences";

//The design's own numbers for a settings row.
static const CGFloat kSectionGapTop     = 20.0;   //above a section label
static const CGFloat kSectionLabelGap   =  8.0;   //label to its 2pt rule
static const CGFloat kRowPaddingY       = 11.0;
static const CGFloat kRowTitleGap       =  3.0;   //title to its help line
static const CGFloat kControlGap        = 14.0;   //text column to the control
static const CGFloat kFootnoteGapTop    = 12.0;

static const CGFloat kSwitchWidth       = 38.0;
static const CGFloat kSwitchHeight      = 22.0;
static const CGFloat kPopUpHeight       = 24.0;
static const CGFloat kButtonHeight      = 26.0;
static const CGFloat kStatusDotSize     =  8.0;
static const CGFloat kStatusDotGap      =  6.0;

static const CGFloat kPathChipHeight    = 24.0;
static const CGFloat kPathChipGapTop    =  8.0;

static NSString* Localized( NSString *text )
{
	if ( [text length] == 0 )
		return text;

	return NSLocalizedStringFromTable( text, PrefsTitlesTable, @"settings" );
}

static NSTextField* RowTitleField( NSString *text )
{
	NSTextField *field = [NSTextField labelWithString: Localized( text ) ?: @""];

	[field setFont: [NSFont systemFontOfSize: 13.0]];
	[field setTextColor: [DIXTheme ink]];
	[field setTranslatesAutoresizingMaskIntoConstraints: YES];

	return field;
}

//Wrapping, not truncating: help text is a sentence, and a settings pane that
//cuts one off mid-word is worse than one that is a line taller.
static NSTextField* HelpField( NSString *text, NSColor *color )
{
	NSTextField *field = [NSTextField wrappingLabelWithString: Localized( text ) ?: @""];

	[field setFont: [NSFont systemFontOfSize: 11.0]];
	[field setTextColor: color];
	[field setSelectable: NO];
	[field setTranslatesAutoresizingMaskIntoConstraints: YES];

	return field;
}

//================ PrefsStatusRow =====================================================

//Handed in by the layout after the row is built, so a page can restate the help
//line as well as the value.
@interface PrefsStatusRow()
- (void) setHelpField: (NSTextField*) field;
@end

@interface PrefsPathRow()
- (void) setChipField: (NSTextField*) chip;
@end

@implementation PrefsStatusRow
{
	NSView *_dot;
	NSTextField *_valueField;
	NSTextField *_helpField;
	CGFloat _width;
}

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_width = NSWidth( frameRect );

		_dot = [[NSView alloc] initWithFrame: NSZeroRect];
		[_dot setWantsLayer: YES];
		[[_dot layer] setCornerRadius: kStatusDotSize / 2.0];
		[self addSubview: _dot];

		_valueField = [NSTextField labelWithString: @""];
		[_valueField setFont: [NSFont systemFontOfSize: 12.0 weight: NSFontWeightSemibold]];
		[_valueField setTranslatesAutoresizingMaskIntoConstraints: YES];
		[self addSubview: _valueField];
	}

	return self;
}

- (void) setHelpField: (NSTextField*) field
{
	_helpField = field;
}

- (void) setHelpText: (NSString*) help
{
	[_helpField setStringValue: Localized( help ) ?: @""];
}

- (void) setStatusText: (NSString*) text good: (BOOL) good
{
	NSColor *color = good ? [DIXTheme positive] : [DIXTheme accent];

	[_valueField setStringValue: text ?: @""];
	[_valueField setTextColor: color];
	[_valueField sizeToFit];

	[[_dot layer] setBackgroundColor: [color CGColor]];

	//laid out from the right, so the dot follows however long the word is
	const CGFloat height = NSHeight( [_valueField frame] );

	[_valueField setFrame: NSMakeRect( _width - NSWidth( [_valueField frame] ),
									   ( NSHeight( [self bounds] ) - height ) / 2.0,
									   NSWidth( [_valueField frame] ), height )];

	[_dot setFrame: NSMakeRect( NSMinX( [_valueField frame] ) - kStatusDotGap - kStatusDotSize,
								NSMidY( [_valueField frame] ) - kStatusDotSize / 2.0,
								kStatusDotSize, kStatusDotSize )];
}

//The dot's layer keeps whatever colour was resolved when it was set, and a
//resolved colour does not follow the appearance on its own.
- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];

	NSColor *color = [_valueField textColor];

	[[self effectiveAppearance] performAsCurrentDrawingAppearance: ^
	{
		[[self->_dot layer] setBackgroundColor: [color CGColor]];
	}];
}

@end

//================ PrefsPathRow =======================================================

@implementation PrefsPathRow
{
	NSTextField *_chip;
}

- (void) setChipField: (NSTextField*) chip
{
	_chip = chip;
}

- (void) setPath: (NSString*) path
{
	[_chip setStringValue: [path stringByAbbreviatingWithTildeInPath] ?: @""];
}

@end

//================ PrefsPageLayout ====================================================

@implementation PrefsPageLayout

+ (instancetype) layoutWithWidth: (CGFloat) width
{
	PrefsPageLayout *layout = [[self alloc] init];

	layout->_width = width;
	layout->_view = [[NSView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, width, 0.0 )];
	layout->_controls = [NSMutableArray array];
	layout->_y = 0.0;

	return layout;
}

//Everything is placed downwards from zero and the whole page is flipped upright
//at the end, in -view. Laying a page out top-down and then translating it once
//is far easier to read than working out the height first.
- (void) addSubview: (NSView*) view height: (CGFloat) height
{
	[view setFrame: NSMakeRect( NSMinX( [view frame] ), -_y - height,
								NSWidth( [view frame] ), height )];
	[_view addSubview: view];

	_y += height;
}

- (void) beginSectionWithLabel: (NSString*) label
{
	if ( _y > 0.0 )
		_y += kSectionGapTop;

	if ( [label length] > 0 )
	{
		NSTextField *field = [DIXControls sectionLabelWithTitle: Localized( label )];

		[field setTranslatesAutoresizingMaskIntoConstraints: YES];
		[field sizeToFit];
		[field setFrameOrigin: NSMakePoint( 0.0, 0.0 )];

		[self addSubview: field height: NSHeight( [field frame] )];

		_y += kSectionLabelGap;
	}

	//2pt ink. The design is explicit that softening this into a hairline undoes
	//the whole hierarchy - it is what separates one group of settings from the
	//next, where the 1pt lines only separate rows inside a group.
	NSBox *rule = [DIXControls sectionRule];

	[rule setTranslatesAutoresizingMaskIntoConstraints: YES];
	[rule setFrame: NSMakeRect( 0.0, 0.0, _width, [DIXTheme ruleThickness] )];

	[self addSubview: rule height: [DIXTheme ruleThickness]];

	_sectionHasRows = NO;
}

//A 1pt line above every row but the first in its section.
- (void) addSeparatorIfNeeded
{
	if ( !_sectionHasRows )
	{
		_sectionHasRows = YES;
		return;
	}

	NSBox *line = [DIXControls rowSeparator];

	[line setTranslatesAutoresizingMaskIntoConstraints: YES];
	[line setFrame: NSMakeRect( 0.0, 0.0, _width, [DIXTheme hairlineThickness] )];

	[self addSubview: line height: [DIXTheme hairlineThickness]];
}

//The shape every row shares: a title over a help line in the left column, and
//one control against the right edge, centred on the title rather than on the
//row - a two-line help text must not drag the switch down with it.
- (NSView*) addRowTitled: (NSString*) title
					help: (NSString*) help
				 control: (NSView*) control
		   controlHeight: (CGFloat) controlHeight
			controlWidth: (CGFloat) controlWidth
	   helpSpansFullWidth: (BOOL) helpSpansFullWidth
			 helpFieldOut: (NSTextField**) helpFieldOut
{
	[self addSeparatorIfNeeded];

	NSView *row = [[NSView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, _width, 0.0 )];

	NSTextField *titleField = RowTitleField( title );
	[titleField sizeToFit];

	const CGFloat textWidth = ( control != nil )
		? _width - controlWidth - kControlGap : _width;

	//A status row's value is a word, so its help line runs the whole width
	//under it rather than stopping short of a column that is mostly empty.
	const CGFloat helpWidth = helpSpansFullWidth ? _width : textWidth;

	//Built whenever one was asked for, even when it is empty: a status row is
	//filled in after it has been laid out, and a field that was never made has
	//nowhere to put the answer. Pass nil, not @"", for a row that wants none.
	NSTextField *helpField = nil;
	CGFloat helpHeight = 0.0;

	if ( help != nil )
	{
		helpField = HelpField( help, [DIXTheme muted] );
		[helpField setFrameSize: NSMakeSize( helpWidth, 0.0 )];

		helpHeight = [[helpField cell] cellSizeForBounds:
			NSMakeRect( 0.0, 0.0, helpWidth, CGFLOAT_MAX )].height;

		//an empty one still owes a line's height, or the row would grow when it
		//is answered
		if ( helpHeight <= 0.0 )
			helpHeight = 14.0;
	}

	const CGFloat titleHeight = NSHeight( [titleField frame] );
	const CGFloat textHeight = titleHeight + ( helpField != nil ? kRowTitleGap + helpHeight : 0.0 );
	const CGFloat rowHeight = kRowPaddingY * 2.0 + MAX( textHeight, controlHeight );

	[row setFrameSize: NSMakeSize( _width, rowHeight )];

	const CGFloat textTop = rowHeight - kRowPaddingY;

	[titleField setFrame: NSMakeRect( 0.0, textTop - titleHeight, textWidth, titleHeight )];
	[row addSubview: titleField];

	if ( helpField != nil )
	{
		[helpField setFrame: NSMakeRect( 0.0, textTop - textHeight, helpWidth, helpHeight )];
		[row addSubview: helpField];
	}

	if ( control != nil )
	{
		[control setFrame: NSMakeRect( _width - controlWidth,
									   NSMidY( [titleField frame] ) - controlHeight / 2.0,
									   controlWidth, controlHeight )];
		[row addSubview: control];

		[_controls addObject: control];

		if ( _firstControl == nil )
			_firstControl = control;

		_lastControl = control;
	}

	[self addSubview: row height: rowHeight];

	if ( helpFieldOut != NULL )
		*helpFieldOut = helpField;

	return row;
}

#pragma mark --------the four kinds of row-----------------

- (void) addToggleTitled: (NSString*) title
					help: (NSString*) help
			 defaultsKey: (NSString*) defaultsKey
{
	[self addToggleTitled: title help: help defaultsKey: defaultsKey inverted: NO];
}

- (void) addToggleTitled: (NSString*) title
					help: (NSString*) help
			 defaultsKey: (NSString*) defaultsKey
				inverted: (BOOL) inverted
{
	DIXSwitch *toggle = [[DIXSwitch alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, kSwitchWidth, kSwitchHeight )];

	[toggle setTranslatesAutoresizingMaskIntoConstraints: YES];
	[toggle setAccessibilityTitle: Localized( title )];

	//Bound to NSUserDefaultsController, which is what makes a change take effect
	//at once and what lets Restore Defaults show up without reloading the page.
	[toggle bind: NSValueBinding
		toObject: [NSUserDefaultsController sharedUserDefaultsController]
	 withKeyPath: [@"values." stringByAppendingString: defaultsKey]
		 options: inverted ? @{ NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName }
						   : nil];

	[self addRowTitled: title help: help control: toggle
		 controlHeight: kSwitchHeight controlWidth: kSwitchWidth
	   helpSpansFullWidth: NO helpFieldOut: NULL];
}

- (void) addPopUpTitled: (NSString*) title
				   help: (NSString*) help
			defaultsKey: (NSString*) defaultsKey
				 titles: (NSArray<NSString*>*) titles
				 values: (NSArray<NSNumber*>*) values
{
	NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame: NSZeroRect pullsDown: NO];

	[popUp setTranslatesAutoresizingMaskIntoConstraints: YES];
	[popUp setControlSize: NSControlSizeSmall];
	[popUp setFocusRingType: NSFocusRingTypeNone];
	[popUp setFont: [NSFont systemFontOfSize: 12.0]];
	[popUp setAccessibilityTitle: Localized( title )];

	for ( NSUInteger i = 0; i < [titles count] && i < [values count]; i++ )
	{
		[popUp addItemWithTitle: Localized( [titles objectAtIndex: i] )];
		[[popUp lastItem] setTag: [[values objectAtIndex: i] integerValue]];
	}

	//The tag, not the index: what is stored is the number chosen, so reordering
	//the menu later cannot silently change what an existing preference means.
	[popUp bind: NSSelectedTagBinding
	   toObject: [NSUserDefaultsController sharedUserDefaultsController]
	withKeyPath: [@"values." stringByAppendingString: defaultsKey]
		options: nil];

	[popUp sizeToFit];

	[self addRowTitled: title help: help control: popUp
		 controlHeight: kPopUpHeight controlWidth: NSWidth( [popUp frame] )
	   helpSpansFullWidth: NO helpFieldOut: NULL];
}

- (void) addButtonTitled: (NSString*) title
					help: (NSString*) help
			 buttonTitle: (NSString*) buttonTitle
			 destructive: (BOOL) destructive
				  target: (id) target
				  action: (SEL) action
{
	NSButton *button = destructive
		? [DIXControls primaryButtonWithTitle: Localized( buttonTitle ) target: target action: action]
		: [DIXControls secondaryButtonWithTitle: Localized( buttonTitle ) target: target action: action];

	[button setTranslatesAutoresizingMaskIntoConstraints: YES];
	[button sizeToFit];

	[self addRowTitled: title help: help control: button
		 controlHeight: kButtonHeight controlWidth: NSWidth( [button frame] )
	   helpSpansFullWidth: NO helpFieldOut: NULL];
}

- (PrefsStatusRow*) addStatusTitled: (NSString*) title help: (NSString*) help
{
	//The status itself is not a control, so it is built at a fixed width and
	//lays its own dot and word out from the right when it is filled in.
	const CGFloat statusWidth = 120.0;

	PrefsStatusRow *status = [[PrefsStatusRow alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, statusWidth, 16.0 )];

	NSTextField *helpField = nil;

	[self addRowTitled: title help: help control: status
		 controlHeight: 16.0 controlWidth: statusWidth
	   helpSpansFullWidth: YES helpFieldOut: &helpField];

	//so the page can restate the help line as well as the value - "12 scans
	//across 2 volumes" is not knowable until the folder is counted
	[status setHelpField: helpField];

	//not a control: it takes no focus and belongs in no tab order
	[_controls removeObject: status];

	if ( _lastControl == status )
		_lastControl = [_controls lastObject];

	if ( _firstControl == status )
		_firstControl = [_controls firstObject];

	return status;
}

- (PrefsPathRow*) addPathRowTitled: (NSString*) title
							  help: (NSString*) help
					   buttonTitle: (NSString*) buttonTitle
							target: (id) target
							action: (SEL) action
{
	//This row is the one that does not fit the shape: a path is too long to sit
	//in the right-hand column, so it gets a line of its own under the help text
	//with the button beside it.
	[self addSeparatorIfNeeded];

	NSButton *button = [DIXControls secondaryButtonWithTitle: Localized( buttonTitle )
													  target: target
													  action: action];
	[button setTranslatesAutoresizingMaskIntoConstraints: YES];
	[button sizeToFit];

	const CGFloat buttonWidth = NSWidth( [button frame] );

	NSTextField *titleField = RowTitleField( title );
	[titleField sizeToFit];

	NSTextField *helpField = nil;
	CGFloat helpHeight = 0.0;

	if ( [help length] > 0 )
	{
		helpField = HelpField( help, [DIXTheme muted] );
		helpHeight = [[helpField cell] cellSizeForBounds:
			NSMakeRect( 0.0, 0.0, _width, CGFLOAT_MAX )].height;
	}

	//A recessed chip, square-cornered and monospaced: it is a value being shown
	//rather than a control, and the design gives 6pt corners to controls only.
	NSTextField *chip = [NSTextField labelWithString: @""];

	[chip setFont: [DIXTheme monoFontOfSize: 11.0]];
	[chip setTextColor: [DIXTheme bodyText]];
	[chip setBackgroundColor: [DIXTheme chrome]];
	[chip setDrawsBackground: YES];
	[chip setBordered: YES];
	[chip setBezeled: NO];
	//At the tail, which is how the design draws it: what matters at a glance is
	//whether this is the default place inside the home folder or somewhere else
	//entirely, and that is the beginning of the path.
	[chip setLineBreakMode: NSLineBreakByTruncatingTail];
	[chip setSelectable: YES];
	[chip setTranslatesAutoresizingMaskIntoConstraints: YES];

	const CGFloat titleHeight = NSHeight( [titleField frame] );
	const CGFloat textHeight = titleHeight + ( helpField != nil ? kRowTitleGap + helpHeight : 0.0 );
	const CGFloat rowHeight = kRowPaddingY * 2.0 + textHeight + kPathChipGapTop + kPathChipHeight;

	PrefsPathRow *row = [[PrefsPathRow alloc] initWithFrame: NSMakeRect( 0.0, 0.0, _width, rowHeight )];

	const CGFloat textTop = rowHeight - kRowPaddingY;

	[titleField setFrame: NSMakeRect( 0.0, textTop - titleHeight, _width, titleHeight )];
	[row addSubview: titleField];

	if ( helpField != nil )
	{
		[helpField setFrame: NSMakeRect( 0.0, textTop - textHeight, _width, helpHeight )];
		[row addSubview: helpField];
	}

	const CGFloat chipY = kRowPaddingY;

	[button setFrame: NSMakeRect( _width - buttonWidth,
								  chipY + ( kPathChipHeight - kButtonHeight ) / 2.0,
								  buttonWidth, kButtonHeight )];
	[row addSubview: button];

	[chip setFrame: NSMakeRect( 0.0, chipY, _width - buttonWidth - 10.0, kPathChipHeight )];
	[row addSubview: chip];

	[row setChipField: chip];

	[self addSubview: row height: rowHeight];

	[_controls addObject: button];

	if ( _firstControl == nil )
		_firstControl = button;

	_lastControl = button;

	return row;
}

- (void) addFootnote: (NSString*) text
{
	if ( [text length] == 0 )
		return;

	_y += kFootnoteGapTop;

	NSTextField *field = HelpField( text, [DIXTheme tertiaryText] );

	const CGFloat height = [[field cell] cellSizeForBounds:
		NSMakeRect( 0.0, 0.0, _width, CGFLOAT_MAX )].height;

	[field setFrame: NSMakeRect( 0.0, 0.0, _width, height )];

	[self addSubview: field height: height];
}

#pragma mark --------the finished page-----------------

- (NSView*) view
{
	//Everything was placed downwards from zero; move it all up by the height it
	//came to, so the page reads as an ordinary bottom-left view from here on.
	[_view setFrameSize: NSMakeSize( _width, _y )];

	for ( NSView *subview in [_view subviews] )
		[subview setFrameOrigin: NSMakePoint( NSMinX( [subview frame] ),
											  NSMinY( [subview frame] ) + _y )];

	return _view;
}

- (NSView*) firstControl  { return _firstControl; }
- (NSView*) lastControl   { return _lastControl; }

@end
