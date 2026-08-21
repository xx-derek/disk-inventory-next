//
//  DIXScanningController.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 03.12.04 as LoadingPanelController.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "DIXScanningController.h"
#import "FSItem.h"
#import "FileTypeColors.h"
#import "FileSizeFormatter.h"
#import "DIXTheme.h"
#import "DIXControls.h"

//The design's own numbers for this screen.
static const CGFloat kWindowWidth     = 560.0;
static const CGFloat kEdgeInset       =  24.0;
static const CGFloat kTopInset        =  22.0;

static const CGFloat kTotalSize       =  34.0;
static const CGFloat kTotalGap        =  10.0;   //total to "found so far"
static const CGFloat kBarGapTop       =  16.0;
static const CGFloat kBarHeight       =   6.0;
static const CGFloat kPathGapTop      =  10.0;
static const CGFloat kStatsGapTop     =  16.0;

static const CGFloat kStatValueSize   =  18.0;
static const CGFloat kStatGap         =   6.0;   //value to its label
static const CGFloat kStatsGapBottom  =  14.0;

static const CGFloat kSectionGapTop   =  16.0;
static const CGFloat kSectionGapBot   =  10.0;
static const CGFloat kBiggestRowH     =  26.0;

static const CGFloat kFooterGapTop    =  18.0;
static const CGFloat kFooterButtonH   =  30.0;
static const CGFloat kFooterGap       =   8.0;

//Three, which is what the walk keeps and what the design draws. Named because
//the row block is laid out at a fixed height whether or not they have arrived -
//a screen that grows two rows taller a second into a scan is a flicker.
static const NSUInteger kBiggestRows  = 3;

@interface DIXScanningController()
{
	NSWindow *_window;
	NSModalSession _modalSession;

	NSTextField *_totalField;
	NSTextField *_foundSoFarField;

	//see -widestTotalWidth; set once while the window is built, and only ever
	//grown after that
	CGFloat _foundSoFarX;

	//when the last sample arrived, which is how long the bar is given to travel
	NSTimeInterval _lastProgressAt;
	NSTextField *_percentField;
	DIXShareBar *_bar;
	NSTextField *_pathField;

	NSBox *_statsRule;
	NSBox *_statsHairline;
	NSMutableArray<NSTextField*> *_statValues;
	NSMutableArray<NSTextField*> *_statLabels;

	NSTextField *_biggestLabel;
	NSMutableArray<DIXKindChip*> *_biggestChips;
	NSMutableArray<NSTextField*> *_biggestNames;
	NSMutableArray<NSTextField*> *_biggestSizes;

	NSTextField *_remainingField;
	NSButton *_cancelButton;
	NSButton *_partialButton;

	BOOL _cancelPressed;
	BOOL _partialPressed;

	FileSizeFormatter *_sizeFormatter;
	NSNumberFormatter *_countFormatter;
}
@end

@implementation DIXScanningController

- (instancetype) initWithTitle: (NSString*) title
{
	self = [super init];

	if ( self != nil )
	{
		_sizeFormatter = [[FileSizeFormatter alloc] init];
		_countFormatter = [[NSNumberFormatter alloc] init];
		[_countFormatter setNumberStyle: NSNumberFormatterDecimalStyle];

		[self buildWindow];

		[_window setTitle: [title length] > 0 ? title
			: NSLocalizedString( @"Scanning", @"scanning screen title, no name" )];

		[_window center];
		[_window display];

		//The scan is about to take the main thread, so the screen has to run its
		//own event handling - which is what a modal session is for. Nothing else
		//in the application is usable meanwhile, which is the same bargain the
		//panel this replaces made.
		_modalSession = [NSApp beginModalSessionForWindow: _window];
	}

	return self;
}

- (void) dealloc
{
	if ( _window != nil )
		[self close];
}

#pragma mark --------building it-----------------

- (void) buildWindow
{
	//No close button: a scan is stopped with Cancel, which also has to tell the
	//walk. A red dot that killed the window and left the queue walking would be
	//a second, worse way out.
	_window = [[NSWindow alloc] initWithContentRect: NSMakeRect( 0.0, 0.0, kWindowWidth, 420.0 )
										  styleMask: NSWindowStyleMaskTitled
											backing: NSBackingStoreBuffered
											  defer: NO];

	[_window setTitlebarAppearsTransparent: YES];
	[_window setBackgroundColor: [DIXTheme surface]];
	[_window setReleasedWhenClosed: NO];

	NSView *content = [_window contentView];

	_totalField = [NSTextField labelWithString: @""];
	[_totalField setTranslatesAutoresizingMaskIntoConstraints: YES];

	//Before anything is laid out, and through the field itself - see
	//-widestTotalWidth for why both of those matter.
	_foundSoFarX = kEdgeInset + [self widestTotalWidth] + kTotalGap;

	_foundSoFarField = [self labelOfSize: 12.0
								  weight: NSFontWeightRegular
								   color: [DIXTheme secondaryText]];
	[_foundSoFarField setStringValue: NSLocalizedString( @"found so far", @"scanning screen" )];

	_percentField = [NSTextField labelWithString: @""];
	[_percentField setAlignment: NSTextAlignmentRight];
	[_percentField setTranslatesAutoresizingMaskIntoConstraints: YES];

	_bar = [DIXShareBar barWithFraction: 0.0 fillColor: [DIXTheme accent]];
	[_bar setTranslatesAutoresizingMaskIntoConstraints: YES];

	//Truncated at the head, which is the design's choice and the right one: the
	//end of a path says which folder the walk is in, and the beginning says
	//nothing that the window title does not already.
	_pathField = [self labelOfSize: 11.0 weight: NSFontWeightRegular color: [DIXTheme secondaryText]];
	[_pathField setLineBreakMode: NSLineBreakByTruncatingHead];

	//2pt ink above the stat row and a hairline under it - the design's heaviest
	//line and one of its lightest, a point apart on the screen.
	_statsRule = [DIXControls sectionRule];
	[_statsRule setTranslatesAutoresizingMaskIntoConstraints: YES];

	_statsHairline = [DIXControls rowSeparator];
	[_statsHairline setTranslatesAutoresizingMaskIntoConstraints: YES];

	_statValues = [NSMutableArray array];
	_statLabels = [NSMutableArray array];

	NSArray<NSString*> *statTitles = @[
		NSLocalizedString( @"files",   @"scanning screen stat" ),
		NSLocalizedString( @"folders", @"scanning screen stat" ),
		NSLocalizedString( @"rate",    @"scanning screen stat" ),
		NSLocalizedString( @"skipped", @"scanning screen stat" ) ];

	for ( NSString *title in statTitles )
	{
		NSTextField *value = [NSTextField labelWithString: @""];
		[value setTranslatesAutoresizingMaskIntoConstraints: YES];
		[_statValues addObject: value];

		NSTextField *label = [self labelOfSize: 11.0
										weight: NSFontWeightRegular
										 color: [DIXTheme secondaryText]];
		[label setStringValue: title];
		[_statLabels addObject: label];
	}

	_biggestLabel = [DIXControls sectionLabelWithTitle:
		NSLocalizedString( @"Biggest so far", @"scanning screen section" )];
	[_biggestLabel setTranslatesAutoresizingMaskIntoConstraints: YES];

	_biggestChips = [NSMutableArray array];
	_biggestNames = [NSMutableArray array];
	_biggestSizes = [NSMutableArray array];

	for ( NSUInteger i = 0; i < kBiggestRows; i++ )
	{
		DIXKindChip *chip = [DIXKindChip chipWithColor: [DIXTheme neutralFill]];
		[chip setTranslatesAutoresizingMaskIntoConstraints: YES];
		[chip setHidden: YES];
		[_biggestChips addObject: chip];

		NSTextField *name = [self labelOfSize: 13.0
									   weight: NSFontWeightRegular
										color: [DIXTheme ink]];
		[_biggestNames addObject: name];

		NSTextField *size = [self labelOfSize: 13.0
									   weight: NSFontWeightRegular
										color: [DIXTheme secondaryText]];
		[size setFont: [DIXTheme tabularFontOfSize: 13.0]];
		[size setAlignment: NSTextAlignmentRight];
		[_biggestSizes addObject: size];
	}

	_remainingField = [self labelOfSize: 12.0
								 weight: NSFontWeightRegular
								  color: [DIXTheme secondaryText]];

	_cancelButton = [DIXControls secondaryButtonWithTitle:
		NSLocalizedString( @"Cancel", @"scanning screen button" )
												   target: self
												   action: @selector(cancel:)];
	[_cancelButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[_cancelButton setKeyEquivalent: @"\033"];

	//Secondary, not the accent: it stops a scan early, which is a compromise
	//rather than the thing the screen is for. Nothing here is a primary action -
	//the primary action is the one already running.
	_partialButton = [DIXControls secondaryButtonWithTitle:
		NSLocalizedString( @"Show Partial Results", @"scanning screen button" )
													target: self
													action: @selector(showPartialResults:)];
	[_partialButton setTranslatesAutoresizingMaskIntoConstraints: YES];

	NSMutableArray<NSView*> *views = [NSMutableArray arrayWithObjects:
		_totalField, _foundSoFarField, _percentField, _bar, _pathField,
		_statsRule, _statsHairline, _biggestLabel, _remainingField,
		_cancelButton, _partialButton, nil];

	[views addObjectsFromArray: _statValues];
	[views addObjectsFromArray: _statLabels];
	[views addObjectsFromArray: _biggestChips];
	[views addObjectsFromArray: _biggestNames];
	[views addObjectsFromArray: _biggestSizes];

	for ( NSView *view in views )
		[content addSubview: view];

	[self setTotalBytes: 0];
	[self setPercentText: nil];

	for ( NSUInteger i = 0; i < [_statValues count]; i++ )
		[self setStatValue: @"0" atIndex: i];

	[self layoutContents];
}

- (NSTextField*) labelOfSize: (CGFloat) size
					  weight: (NSFontWeight) weight
					   color: (NSColor*) color
{
	NSTextField *field = [NSTextField labelWithString: @""];

	[field setFont: [NSFont systemFontOfSize: size weight: weight]];
	[field setTextColor: color];
	[field setLineBreakMode: NSLineBreakByTruncatingTail];
	[field setTranslatesAutoresizingMaskIntoConstraints: YES];

	return field;
}

- (void) takeFrameFrom: (NSWindow*) window
{
	if ( window == nil || ![window isVisible] )
		return;

	//The top-left corner, not the whole frame: this screen is taller than the
	//picker, and matching the origin would slide the title bar down the screen
	//at the moment the two swap over.
	const NSRect existing = [window frame];
	NSRect frame = [_window frame];

	frame.origin = NSMakePoint( NSMinX( existing ), NSMaxY( existing ) - NSHeight( frame ) );

	[_window setFrame: frame display: NO];
}

#pragma mark --------layout-----------------

//One pass from the top down, then the window is sized to what it came to. The
//height is fixed for the life of a scan: everything that changes is text inside
//a row whose place is already decided, which is what keeps a screen updating
//four times a second from jumping about.
- (void) layoutContents
{
	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;

	[_totalField sizeToFit];
	[_foundSoFarField sizeToFit];
	[_percentField sizeToFit];
	[_pathField sizeToFit];
	[_biggestLabel sizeToFit];
	[_remainingField sizeToFit];
	[_cancelButton sizeToFit];
	[_partialButton sizeToFit];

	const CGFloat totalHeight = NSHeight( [_totalField frame] );
	const CGFloat pathHeight  = NSHeight( [_pathField frame] );

	CGFloat statValueHeight = 0.0;
	CGFloat statLabelHeight = 0.0;

	for ( NSUInteger i = 0; i < [_statValues count]; i++ )
	{
		[[_statValues objectAtIndex: i] sizeToFit];
		[[_statLabels objectAtIndex: i] sizeToFit];

		statValueHeight = MAX( statValueHeight, NSHeight( [[_statValues objectAtIndex: i] frame] ) );
		statLabelHeight = MAX( statLabelHeight, NSHeight( [[_statLabels objectAtIndex: i] frame] ) );
	}

	const CGFloat statsHeight = statValueHeight + kStatGap + statLabelHeight;
	const CGFloat sectionHeight = NSHeight( [_biggestLabel frame] );

	const CGFloat contentHeight =
		kTopInset + totalHeight
		+ kBarGapTop + kBarHeight
		+ kPathGapTop + pathHeight
		+ kStatsGapTop + [DIXTheme ruleThickness] + kStatsGapBottom + statsHeight
		+ kStatsGapBottom + [DIXTheme hairlineThickness]
		+ kSectionGapTop + sectionHeight + kSectionGapBot
		+ kBiggestRowH * (CGFloat) kBiggestRows
		+ kFooterGapTop + kFooterButtonH + kEdgeInset;

	[_window setContentSize: NSMakeSize( kWindowWidth, contentHeight )];

	CGFloat y = contentHeight - kTopInset - totalHeight;

	[_totalField setFrame: NSMakeRect( kEdgeInset, y,
									   NSWidth( [_totalField frame] ), totalHeight )];

	//"found so far" sits on the total's baseline, not in the middle of its box:
	//12pt beside 34pt has to be aligned to something, and the design aligns it
	//to the line they share.
	const CGFloat baseline = y - [[_totalField font] descender];

	[_foundSoFarField setFrame: NSMakeRect( [self foundSoFarX],
											baseline + [[_foundSoFarField font] descender],
											NSWidth( [_foundSoFarField frame] ),
											NSHeight( [_foundSoFarField frame] ) )];

	[_percentField setFrame: NSMakeRect( kEdgeInset + width - NSWidth( [_percentField frame] ),
										 baseline + [[_percentField font] descender],
										 NSWidth( [_percentField frame] ),
										 NSHeight( [_percentField frame] ) )];

	y -= kBarGapTop + kBarHeight;
	[_bar setFrame: NSMakeRect( kEdgeInset, y, width, kBarHeight )];

	y -= kPathGapTop + pathHeight;
	[_pathField setFrame: NSMakeRect( kEdgeInset, y, width, pathHeight )];

	y -= kStatsGapTop + [DIXTheme ruleThickness];
	[_statsRule setFrame: NSMakeRect( kEdgeInset, y, width, [DIXTheme ruleThickness] )];

	y -= kStatsGapBottom + statsHeight;

	//four equal cells, as the design has them, so the columns line up whatever
	//the figures come to
	const CGFloat cellWidth = width / (CGFloat) [_statValues count];

	for ( NSUInteger i = 0; i < [_statValues count]; i++ )
	{
		const CGFloat x = kEdgeInset + cellWidth * (CGFloat) i;

		NSTextField *value = [_statValues objectAtIndex: i];
		NSTextField *label = [_statLabels objectAtIndex: i];

		[value setFrame: NSMakeRect( x, y + statLabelHeight + kStatGap,
									 cellWidth, statValueHeight )];
		[label setFrame: NSMakeRect( x, y, cellWidth, statLabelHeight )];
	}

	y -= kStatsGapBottom + [DIXTheme hairlineThickness];
	[_statsHairline setFrame: NSMakeRect( kEdgeInset, y, width, [DIXTheme hairlineThickness] )];

	y -= kSectionGapTop + sectionHeight;
	[_biggestLabel setFrame: NSMakeRect( kEdgeInset, y, width, sectionHeight )];

	y -= kSectionGapBot;

	const CGFloat chipSize = [DIXTheme kindChipSize];

	for ( NSUInteger i = 0; i < kBiggestRows; i++ )
	{
		const CGFloat rowBottom = y - kBiggestRowH * (CGFloat) ( i + 1 );
		const CGFloat rowMidY = rowBottom + kBiggestRowH / 2.0;

		DIXKindChip *chip = [_biggestChips objectAtIndex: i];
		NSTextField *name = [_biggestNames objectAtIndex: i];
		NSTextField *size = [_biggestSizes objectAtIndex: i];

		[name sizeToFit];
		[size sizeToFit];

		[chip setFrame: NSMakeRect( kEdgeInset, rowMidY - chipSize / 2.0, chipSize, chipSize )];

		const CGFloat sizeWidth = MAX( 80.0, NSWidth( [size frame] ) );

		[size setFrame: NSMakeRect( kEdgeInset + width - sizeWidth,
									rowMidY - NSHeight( [size frame] ) / 2.0,
									sizeWidth, NSHeight( [size frame] ) )];

		const CGFloat nameX = kEdgeInset + chipSize + 12.0;

		[name setFrame: NSMakeRect( nameX, rowMidY - NSHeight( [name frame] ) / 2.0,
									MAX( 0.0, NSMinX( [size frame] ) - 12.0 - nameX ),
									NSHeight( [name frame] ) )];
	}

	y -= kBiggestRowH * (CGFloat) kBiggestRows;
	y -= kFooterGapTop + kFooterButtonH;

	const CGFloat partialWidth = NSWidth( [_partialButton frame] );

	[_partialButton setFrame: NSMakeRect( kEdgeInset + width - partialWidth, y,
										  partialWidth, kFooterButtonH )];

	const CGFloat cancelWidth = MAX( 84.0, NSWidth( [_cancelButton frame] ) );

	[_cancelButton setFrame: NSMakeRect( NSMinX( [_partialButton frame] ) - kFooterGap - cancelWidth,
										 y, cancelWidth, kFooterButtonH )];

	[_remainingField setFrame: NSMakeRect( kEdgeInset,
										   y + ( kFooterButtonH - NSHeight( [_remainingField frame] ) ) / 2.0,
										   MAX( 0.0, NSMinX( [_cancelButton frame] ) - kFooterGap - kEdgeInset ),
										   NSHeight( [_remainingField frame] ) )];
}

#pragma mark --------what it says-----------------

- (void) setTotalBytes: (unsigned long long) bytes
{
	[_totalField setAttributedStringValue:
		[[NSAttributedString alloc] initWithString:
			[_sizeFormatter stringForObjectValue: @(bytes)]
										attributes: [DIXTheme tickingDisplayAttributesOfSize: kTotalSize
																				color: [DIXTheme ink]]]];
}

- (void) setPercentText: (NSString*) text
{
	[_percentField setAttributedStringValue:
		[[NSAttributedString alloc] initWithString: text != nil ? text : @""
										attributes: [DIXTheme tickingDisplayAttributesOfSize: 13.0
																				color: [DIXTheme accent]]]];
}

- (void) setStatValue: (NSString*) text atIndex: (NSUInteger) index
{
	if ( index >= [_statValues count] )
		return;

	[[_statValues objectAtIndex: index] setAttributedStringValue:
		[[NSAttributedString alloc] initWithString: text != nil ? text : @""
										attributes: [DIXTheme tickingDisplayAttributesOfSize: kStatValueSize
																				color: [DIXTheme ink]]]];
}

- (void) setProgress: (DIXScanProgress) progress
{
	//Let the bar travel over exactly one sampling period, so it is still moving
	//when the next sample lands and reads as motion rather than as four steps a
	//second. Measured rather than declared: the refresh cadence belongs to
	//FileSystemDoc's loop, and a constant here would be a copy of it that could
	//quietly stop matching. Bounded, so one late sample cannot leave the bar
	//crawling through the next second.
	const NSTimeInterval at = [NSDate timeIntervalSinceReferenceDate];

	if ( _lastProgressAt > 0.0 && at > _lastProgressAt )
		[_bar setGlideDuration: MIN( MAX( at - _lastProgressAt, 0.05 ), 0.5 )];

	_lastProgressAt = at;

	[self setTotalBytes: progress.bytes];

	if ( progress.fraction < 0.0 )
	{
		//No estimate to divide by. The bar stays empty and the percentage blank
		//rather than showing a figure that would be made up - see the note on
		//estimating scan progress.
		[_bar setFraction: 0.0];
		[self setPercentText: nil];
	}
	else
	{
		//Held below 100 until the scan really ends: the total is an estimate,
		//and a full bar over a still-running scan reads as a hang.
		const double percent = MIN( progress.fraction * 100.0, 99.0 );

		[_bar setFraction: percent / 100.0];
		[self setPercentText: [NSString stringWithFormat: @"%.0f%%", percent]];
	}

	[self setStatValue: [_countFormatter stringFromNumber: @(progress.files)] atIndex: 0];
	[self setStatValue: [_countFormatter stringFromNumber: @(progress.folders)] atIndex: 1];

	[self setStatValue: [NSString stringWithFormat:
		NSLocalizedString( @"%@/s", @"scanning screen, items per second" ),
		[_countFormatter stringFromNumber: @( (NSUInteger) ( progress.itemsPerSecond + 0.5 ) )]]
			   atIndex: 2];

	[self setStatValue: [_countFormatter stringFromNumber: @(progress.skipped)] atIndex: 3];

	//"About 40 seconds left". Nothing at all until there is a rate to say it
	//with, which is better than "About 0 seconds left" for the first half second.
	if ( progress.secondsRemaining < 0.0 )
	{
		[_remainingField setStringValue: @""];
	}
	else
	{
		static NSDateComponentsFormatter *remaining = nil;
		static dispatch_once_t once;

		dispatch_once( &once, ^
		{
			remaining = [[NSDateComponentsFormatter alloc] init];
			[remaining setUnitsStyle: NSDateComponentsFormatterUnitsStyleFull];
			[remaining setAllowedUnits: NSCalendarUnitMinute | NSCalendarUnitSecond];
			[remaining setMaximumUnitCount: 1];
		} );

		//Rounded to five seconds below a minute. The estimate is not good to the
		//second and a figure that counts down unevenly says so out loud.
		double seconds = progress.secondsRemaining;

		if ( seconds < 60.0 )
			seconds = MAX( 5.0, round( seconds / 5.0 ) * 5.0 );

		NSString *text = [remaining stringFromTimeInterval: seconds];

		[_remainingField setStringValue: [text length] > 0
			? [NSString stringWithFormat:
				NSLocalizedString( @"About %@ left", @"scanning screen, time remaining" ), text]
			: @""];
	}

	[self layoutFooterAndHeader];
}

//The widest the total can ever be drawn, which is where "found so far" goes.
//
//Tabular digits hold a total at one width for as long as it has the same number
//of them; they cannot hold it across 99.4 GB to 105.3 GB, or GB to TB. So the
//caption is parked past the longest string there is instead, and two things
//have to be right or it moves anyway.
//
//Measure the *field*, not the string. -sizeToFit adds the cell's own insets,
//about 4pt, so a bare -[NSAttributedString size] comes up short - which is
//exactly how far the caption jumped the first time a total used all eight of
//its characters, tabular digits notwithstanding.
//
//And ask the formatter for its own widest output rather than writing a template
//out here. It divides by 1000 and prints one decimal above kB, so the widest is
//not the largest: "999.9 MB" beats "999.9 GB" because M is a wider letter than
//G, and "999 Bytes" beats both.
- (CGFloat) widestTotalWidth
{
	static const unsigned long long samples[] = {
		999ULL,                 //999 Bytes
		999999ULL,              //999 kB
		999900000ULL,           //999.9 MB
		999900000000ULL,        //999.9 GB
		999900000000000ULL };   //999.9 TB

	CGFloat widest = 0.0;

	for ( size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); i++ )
	{
		[self setTotalBytes: samples[i]];
		[_totalField sizeToFit];

		widest = MAX( widest, NSWidth( [_totalField frame] ) );
	}

	[_totalField setStringValue: @""];
	[_totalField sizeToFit];

	return widest;
}

- (CGFloat) foundSoFarX
{
	//Belt and braces. The seed is the widest the formatter can produce, so this
	//should not fire; if a locale's separator or unit turns out wider, the
	//caption steps right once and stays rather than shaking.
	_foundSoFarX = MAX( _foundSoFarX, NSMaxX( [_totalField frame] ) + kTotalGap );

	return _foundSoFarX;
}

//Only the things whose width changes with their text, which is why this is not
//the whole of -layoutContents: the rows and the rules do not move for the life
//of a scan, and laying them out four times a second is work for nothing.
- (void) layoutFooterAndHeader
{
	[_totalField sizeToFit];
	[_percentField sizeToFit];
	[_remainingField sizeToFit];

	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;
	const NSRect totalFrame = [_totalField frame];
	const CGFloat baseline = NSMinY( totalFrame ) - [[_totalField font] descender];

	[_totalField setFrame: NSMakeRect( kEdgeInset, NSMinY( totalFrame ),
									   NSWidth( [_totalField frame] ), NSHeight( totalFrame ) )];

	[_foundSoFarField setFrameOrigin: NSMakePoint( [self foundSoFarX],
												   NSMinY( [_foundSoFarField frame] ) )];

	[_percentField setFrame: NSMakeRect( kEdgeInset + width - NSWidth( [_percentField frame] ),
										 baseline + [[_percentField font] descender],
										 NSWidth( [_percentField frame] ),
										 NSHeight( [_percentField frame] ) )];

	[_remainingField setFrame: NSMakeRect( kEdgeInset,
										   NSMidY( [_cancelButton frame] )
											   - NSHeight( [_remainingField frame] ) / 2.0,
										   MAX( 0.0, NSMinX( [_cancelButton frame] ) - kFooterGap - kEdgeInset ),
										   NSHeight( [_remainingField frame] ) )];
}

- (void) setCurrentPath: (NSString*) path
{
	[_pathField setStringValue: path != nil ? path : @""];
}

- (void) setBiggestFiles: (NSArray<NSDictionary*>*) biggest
{
	for ( NSUInteger i = 0; i < kBiggestRows; i++ )
	{
		DIXKindChip *chip = [_biggestChips objectAtIndex: i];
		NSTextField *name = [_biggestNames objectAtIndex: i];
		NSTextField *size = [_biggestSizes objectAtIndex: i];

		if ( i >= [biggest count] )
		{
			[chip setHidden: YES];
			[name setStringValue: @""];
			[size setStringValue: @""];
			continue;
		}

		NSDictionary *entry = [biggest objectAtIndex: i];
		NSString *kind = [entry objectForKey: FSItemBiggestKindKey];

		//A file inside a package has no kind read for it - the walk stops asking
		//once it is not looking into packages - so the chip falls back to the
		//tone the map gives to what is not a file kind.
		[chip setColor: ( kind != nil ) ? [[FileTypeColors instance] colorForKind: kind]
										: [DIXTheme neutralFill]];
		[chip setHidden: NO];

		[name setStringValue: [entry objectForKey: FSItemBiggestNameKey] ?: @""];
		[size setStringValue: [_sizeFormatter stringForObjectValue:
			[entry objectForKey: FSItemBiggestSizeKey]]];
	}

	[self layoutBiggestRows];
}

- (void) layoutBiggestRows
{
	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;
	const CGFloat chipSize = [DIXTheme kindChipSize];

	for ( NSUInteger i = 0; i < kBiggestRows; i++ )
	{
		NSTextField *name = [_biggestNames objectAtIndex: i];
		NSTextField *size = [_biggestSizes objectAtIndex: i];

		const CGFloat rowMidY = NSMidY( [[_biggestChips objectAtIndex: i] frame] );

		[size sizeToFit];

		const CGFloat sizeWidth = MAX( 80.0, NSWidth( [size frame] ) );

		[size setFrame: NSMakeRect( kEdgeInset + width - sizeWidth,
									rowMidY - NSHeight( [size frame] ) / 2.0,
									sizeWidth, NSHeight( [size frame] ) )];

		const CGFloat nameX = kEdgeInset + chipSize + 12.0;

		[name setFrame: NSMakeRect( nameX, rowMidY - NSHeight( [name frame] ) / 2.0,
									MAX( 0.0, NSMinX( [size frame] ) - 12.0 - nameX ),
									NSHeight( [name frame] ) )];
	}
}

#pragma mark --------running and stopping-----------------

- (BOOL) runModalSessionForInterval: (NSTimeInterval) seconds
{
	if ( _modalSession != 0 )
	{
		if ( [NSApp runModalSession: _modalSession] != NSModalResponseContinue )
			return NO;
	}

	//-runModalSession: returns at once when there is nothing to do, so without
	//this the caller's wait loop would spin a core doing nothing. Blocking in
	//the run loop instead lets the screen redraw and the buttons respond.
	[[NSRunLoop currentRunLoop] runMode: NSModalPanelRunLoopMode
							 beforeDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];

	return YES;
}

- (BOOL) cancelPressed
{
	@synchronized ( self )
	{
		return _cancelPressed;
	}
}

- (BOOL) partialResultsPressed
{
	@synchronized ( self )
	{
		return _partialPressed;
	}
}

- (void) enableCancelButton: (BOOL) enable
{
	[_cancelButton setEnabled: enable];
}

- (void) setAllowsPartialResults: (BOOL) allows
{
	[_partialButton setHidden: !allows];

	//Cancel takes the trailing place when it is on its own, which is where a
	//lone button belongs and where the eye already is.
	if ( !allows )
	{
		const CGFloat width = kWindowWidth - kEdgeInset * 2.0;
		NSRect frame = [_cancelButton frame];

		frame.origin.x = kEdgeInset + width - NSWidth( frame );
		[_cancelButton setFrame: frame];

		[self layoutFooterAndHeader];
	}
}

- (IBAction) cancel: (id) sender
{
	@synchronized ( self )
	{
		_cancelPressed = YES;
	}

	[_cancelButton setEnabled: NO];
	[_partialButton setEnabled: NO];
}

- (IBAction) showPartialResults: (id) sender
{
	@synchronized ( self )
	{
		//Both: the walk is stopped the same way either button stops it, and what
		//separates them is what the document does with the tree afterwards.
		_partialPressed = YES;
		_cancelPressed = YES;
	}

	[_cancelButton setEnabled: NO];
	[_partialButton setEnabled: NO];
}

- (void) close
{
	if ( _modalSession != 0 )
	{
		[NSApp endModalSession: _modalSession];
		_modalSession = 0;
	}

	[self closeNoModalEnd];
}

- (void) closeNoModalEnd
{
	//The sender asked us not to end the modal session - it has run into an
	//exception, and AppKit's documentation says not to end one from a handler.
	_modalSession = 0;

	[_window close];
	_window = nil;
}

@end
