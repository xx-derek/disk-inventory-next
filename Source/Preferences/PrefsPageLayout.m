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

//the same table the page titles are localized through
static NSString * const PrefsStringsTable = @"Preferences";

static const CGFloat kColumnGap   = 10.0;
static const CGFloat kRowGap      = 8.0;
static const CGFloat kSectionGap  = 18.0;   //extra space above a new section
static const CGFloat kEdgeInset   = 20.0;

//Explanatory text has to be told how wide it will be before it can report a
//height. Taking that from the field's own frame is what sent the Info panel's
//value column into a shrinking loop, so it is taken from the checkboxes
//instead: their widths are intrinsic and settled before any help text is
//measured, which makes the number deterministic. The floor is for a page whose
//checkboxes are all short.
static const CGFloat kMinimumHelpTextWidth = 320.0;

@implementation PrefsPageLayout

+ (instancetype) layout
{
	return [[self alloc] init];
}

- (id) init
{
	self = [super init];
	if ( self == nil )
		return nil;

	_checkboxes = [[NSMutableArray alloc] init];
	_controls = [[NSMutableArray alloc] init];
	_helpFields = [[NSMutableArray alloc] init];

	_grid = [[NSGridView alloc] initWithFrame: NSZeroRect];
	[_grid setColumnSpacing: kColumnGap];
	[_grid setRowSpacing: kRowGap];
	[_grid setRowAlignment: NSGridRowAlignmentFirstBaseline];

	return self;
}

- (void) beginSectionWithLabel: (NSString*) label
{
	//held until the next row is added, so it lands beside that row rather than
	//on a line of its own
	_pendingSectionLabel = label;

	if ( [_grid numberOfRows] > 0 )
		[[_grid rowAtIndex: [_grid numberOfRows] - 1] setBottomPadding: kSectionGap];
}

- (NSTextField*) labelWithString: (NSString*) string
{
	NSString *localized = NSLocalizedStringFromTable( string, PrefsStringsTable, @"" );
	NSTextField *field = [NSTextField labelWithString: localized];

	[field setAlignment: NSTextAlignmentRight];
	[field setTextColor: [NSColor labelColor]];

	return field;
}

- (void) addCheckboxTitled: (NSString*) title
			   defaultsKey: (NSString*) defaultsKey
					  help: (NSString*) help
{
	NSString *localizedTitle = NSLocalizedStringFromTable( title, PrefsStringsTable, @"" );

	NSButton *checkbox = [NSButton checkboxWithTitle: localizedTitle target: nil action: NULL];

	//What the nibs did through Interface Builder's bindings inspector. The
	//shared controller is what makes a change take effect immediately, and what
	//lets "Restore Defaults" show up in the checkboxes without reloading them.
	[checkbox bind: NSValueBinding
		  toObject: [NSUserDefaultsController sharedUserDefaultsController]
	   withKeyPath: [@"values." stringByAppendingString: defaultsKey]
		   options: nil];

	NSView *labelCell = ( _pendingSectionLabel != nil )
						? (NSView*) [self labelWithString: _pendingSectionLabel]
						: [NSGridCell emptyContentView];
	_pendingSectionLabel = nil;

	[_grid addRowWithViews: @[ labelCell, checkbox ]];

	[_checkboxes addObject: checkbox];

	if ( _firstCheckbox == nil )
		_firstCheckbox = checkbox;
	_lastCheckbox = checkbox;

	if ( [help length] == 0 )
		return;

	//explanatory text: secondary colour and small type, so it reads as a note on
	//the checkbox above rather than as another setting
	NSTextField *helpField =
		[NSTextField wrappingLabelWithString: NSLocalizedStringFromTable( help, PrefsStringsTable, @"" )];

	[helpField setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
	[helpField setTextColor: [NSColor secondaryLabelColor]];
	[helpField setSelectable: NO];

	//width is applied in -view, once every checkbox has been added
	[_helpFields addObject: helpField];

	NSGridRow *helpRow = [_grid addRowWithViews: @[ [NSGridCell emptyContentView], helpField ]];

	//tighter to the checkbox it explains than to the next setting
	[helpRow setTopPadding: -2.0];
	[helpRow setBottomPadding: 4.0];
}


- (void) addPopUpWithValues: (NSArray<NSNumber*>*) values
				defaultsKey: (NSString*) defaultsKey
			  trailingTitle: (NSString*) trailingTitle
					   help: (NSString*) help
{
	NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame: NSZeroRect pullsDown: NO];

	for ( NSNumber *value in values )
	{
		[popUp addItemWithTitle: [value stringValue]];
		//the tag carries the value, so the binding below stores the number the
		//user chose and not where it happened to sit in the menu
		[[popUp lastItem] setTag: [value integerValue]];
	}

	[popUp sizeToFit];
	[popUp setTranslatesAutoresizingMaskIntoConstraints: NO];
	[[popUp widthAnchor] constraintEqualToConstant: NSWidth( [popUp frame] )].active = YES;

	//as the checkboxes do: the shared controller is what makes a change take
	//effect at once and what lets Restore Defaults show up without a reload
	[popUp bind: NSSelectedTagBinding
	   toObject: [NSUserDefaultsController sharedUserDefaultsController]
	withKeyPath: [@"values." stringByAppendingString: defaultsKey]
		options: nil];

	NSTextField *caption =
		[NSTextField labelWithString: NSLocalizedStringFromTable( trailingTitle, PrefsStringsTable, @"" )];

	NSStackView *row = [NSStackView stackViewWithViews: @[ popUp, caption ]];
	[row setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[row setAlignment: NSLayoutAttributeCenterY];
	[row setSpacing: 6.0];

	NSView *labelCell = ( _pendingSectionLabel != nil )
						? (NSView*) [self labelWithString: _pendingSectionLabel]
						: [NSGridCell emptyContentView];
	_pendingSectionLabel = nil;

	[_grid addRowWithViews: @[ labelCell, row ]];

	[_controls addObject: popUp];

	if ( _firstCheckbox == nil )
		_firstCheckbox = (NSButton*) popUp;
	_lastCheckbox = (NSButton*) popUp;

	if ( [help length] == 0 )
		return;

	NSTextField *helpField =
		[NSTextField wrappingLabelWithString: NSLocalizedStringFromTable( help, PrefsStringsTable, @"" )];

	[helpField setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
	[helpField setTextColor: [NSColor secondaryLabelColor]];
	[helpField setSelectable: NO];

	[_helpFields addObject: helpField];

	NSGridRow *helpRow = [_grid addRowWithViews: @[ [NSGridCell emptyContentView], helpField ]];
	[helpRow setTopPadding: -2.0];
	[helpRow setBottomPadding: 4.0];
}

- (NSView*) view
{
	if ( [_grid numberOfRows] == 0 )
		return _grid;

	//the control column is as wide as its widest checkbox, so the help text
	//fills it rather than leaving a ragged right edge
	CGFloat controlWidth = kMinimumHelpTextWidth;
	for ( NSButton *checkbox in _checkboxes )
		controlWidth = MAX( controlWidth, ceil( [checkbox intrinsicContentSize].width ) );

	for ( NSTextField *helpField in _helpFields )
		[helpField setPreferredMaxLayoutWidth: controlWidth];

	NSGridColumn *labels = [_grid columnAtIndex: 0];
	[labels setXPlacement: NSGridCellPlacementTrailing];
	[labels setLeadingPadding: kEdgeInset];

	NSGridColumn *controls = [_grid columnAtIndex: 1];
	[controls setXPlacement: NSGridCellPlacementLeading];
	[controls setTrailingPadding: kEdgeInset];

	[[_grid rowAtIndex: 0] setTopPadding: kEdgeInset];
	[[_grid rowAtIndex: [_grid numberOfRows] - 1] setBottomPadding: kEdgeInset];

	//The panel sizes its window from -[pageView frame], and a grid that has
	//never been through a layout pass still has whatever frame it was created
	//with. Without this the window came out 736 points wide for 552 points of
	//content, with the surplus as blank space down the right.
	[_grid setFrameSize: [_grid fittingSize]];

	return _grid;
}

- (NSView*) firstControl
{
	return _firstCheckbox;
}

- (NSView*) lastControl
{
	return _lastCheckbox;
}

@end
