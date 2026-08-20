//
//  DIXScanPickerController.m
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

#import "DIXScanPickerController.h"
#import "DIXVolumeList.h"
#import "DIXRecentScans.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "FileSizeFormatter.h"

//The design's own numbers for this screen.
static const CGFloat kWindowWidth     = 560.0;
static const CGFloat kEdgeInset       =  28.0;
static const CGFloat kHeadingSize     =  22.0;
static const CGFloat kSubtitleGapTop  =   6.0;
static const CGFloat kSubtitleGapBot  =  18.0;

static const CGFloat kCardPaddingX    =  14.0;
static const CGFloat kCardPaddingY    =  12.0;
static const CGFloat kCardGap         =   8.0;   //between one card and the next
static const CGFloat kCardIconWidth   =  34.0;
static const CGFloat kCardIconHeight  =  26.0;
static const CGFloat kCardColumnGap   =  14.0;   //icon to text
static const CGFloat kCardBarHeight   =   6.0;
static const CGFloat kCardBarGapTop   =   8.0;
static const CGFloat kCardDetailGap   =   5.0;

static const CGFloat kFooterGap       =  10.0;
static const CGFloat kFooterButtonH   =  30.0;

//================ DIXVolumeCard ======================================================

//One volume, as the design draws it: icon, name, format and capacity, free space
//to the right, a capacity bar, and what the last scan of it found.
//
//Square-cornered on purpose. The design gives 6pt to buttons and nothing else;
//a card is a surface, not a control.
@interface DIXVolumeCard : NSView
{
	DIXVolume *_volume;
	DIXRecentScan *_lastScan;
	BOOL _selected;

	NSImageView *_iconView;
	NSTextField *_nameField;
	NSTextField *_detailField;
	NSTextField *_freeField;
	NSTextField *_historyField;
	DIXShareBar *_bar;
}

@property (nonatomic, strong) DIXVolume *volume;
@property (nonatomic, strong) DIXRecentScan *lastScan;
@property (nonatomic, assign, getter=isSelected) BOOL selected;

//__weak: the controller owns the window that owns these
@property (nonatomic, weak) id owner;

+ (CGFloat) preferredHeight;

@end

@implementation DIXVolumeCard

+ (CGFloat) preferredHeight
{
	//two lines of text, the bar, and the history line, inside the padding
	return kCardPaddingY * 2.0 + 18.0 + kCardBarGapTop + kCardBarHeight
		   + kCardDetailGap + 14.0;
}

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_iconView = [[NSImageView alloc] initWithFrame: NSZeroRect];
		[_iconView setImageScaling: NSImageScaleProportionallyUpOrDown];

		_nameField    = [self labelOfSize: 15.0 weight: NSFontWeightSemibold color: [DIXTheme ink]];
		_detailField  = [self labelOfSize: 12.0 weight: NSFontWeightRegular  color: [DIXTheme secondaryText]];
		_freeField    = [self labelOfSize: 13.0 weight: NSFontWeightSemibold color: [DIXTheme ink]];
		_historyField = [self labelOfSize: 11.0 weight: NSFontWeightRegular  color: [DIXTheme secondaryText]];

		_bar = [DIXShareBar barWithFraction: 0.0 fillColor: [DIXTheme ink]];
		[_bar setTranslatesAutoresizingMaskIntoConstraints: YES];

		for ( NSView *view in @[ _iconView, _nameField, _detailField, _freeField, _historyField, _bar ] )
			[self addSubview: view];
	}

	return self;
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

- (void) setVolume: (DIXVolume*) volume
{
	_volume = volume;
	[self refresh];
}

- (void) setLastScan: (DIXRecentScan*) lastScan
{
	_lastScan = lastScan;
	[self refresh];
}

- (void) setSelected: (BOOL) selected
{
	if ( _selected == selected )
		return;

	_selected = selected;

	[_bar setFillColor: selected ? [DIXTheme accent] : [DIXTheme ink]];
	[self setNeedsDisplay: YES];
}

- (void) refresh
{
	if ( _volume == nil )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	[_iconView setImage: [_volume icon]];
	[_nameField setStringValue: [_volume name] ?: @""];

	//"APFS · 994.7 GB", and just the size when the format is unknown
	NSString *capacity = [_volume knowsItsSize]
		? [sizeFormatter stringForObjectValue: @([_volume totalCapacity])] : @"";
	NSString *format = [_volume formatDescription];

	NSString *detail = ( [format length] > 0 && [capacity length] > 0 )
		? [NSString stringWithFormat: @"%@ · %@", format, capacity]
		: ( [format length] > 0 ? format : capacity );

	[_detailField setStringValue: detail];

	[_freeField setStringValue: [_volume knowsItsSize]
		? [NSString stringWithFormat: NSLocalizedString( @"%@ free", @"volume card, free space" ),
									  [sizeFormatter stringForObjectValue: @([_volume availableCapacity])]]
		: @""];

	[_bar setFraction: [_volume usedFraction]];
	[_bar setHidden: ![_volume knowsItsSize]];

	//"Scanned 8 Aug · 91.8 GB", or the plain statement that it never has been
	if ( _lastScan != nil )
	{
		//"Scanned 8 Aug", the design's wording, in the locale's day/month order
		NSDateFormatter *when = [[NSDateFormatter alloc] init];
		[when setDateFormat: [NSDateFormatter dateFormatFromTemplate: @"dMMM"
															 options: 0
															  locale: [NSLocale currentLocale]]];

		[_historyField setStringValue: [NSString stringWithFormat:
			NSLocalizedString( @"Scanned %@ · %@", @"volume card, last scan" ),
			[when stringFromDate: [_lastScan scannedAt]],
			[sizeFormatter stringForObjectValue: @([_lastScan size])]]];
	}
	else
	{
		[_historyField setStringValue: NSLocalizedString( @"Never scanned",
														 @"volume card, no scan yet" )];
	}

	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) setFrameSize: (NSSize) newSize
{
	[super setFrameSize: newSize];
	[self layoutContents];
}

- (void) layoutContents
{
	const NSRect bounds = [self bounds];
	const CGFloat textX = kCardPaddingX + kCardIconWidth + kCardColumnGap;
	const CGFloat textWidth = NSWidth( bounds ) - textX - kCardPaddingX;

	if ( textWidth <= 0.0 )
		return;

	[_iconView setFrame: NSMakeRect( kCardPaddingX,
									 NSMidY( bounds ) - kCardIconHeight / 2.0,
									 kCardIconWidth, kCardIconHeight )];

	//the name row, from the top down
	[_nameField sizeToFit];
	[_detailField sizeToFit];
	[_freeField sizeToFit];
	[_historyField sizeToFit];

	const CGFloat nameHeight = NSHeight( [_nameField frame] );
	CGFloat top = NSMaxY( bounds ) - kCardPaddingY;

	[_freeField setFrame: NSMakeRect( NSMaxX( bounds ) - kCardPaddingX - NSWidth( [_freeField frame] ),
									  top - NSHeight( [_freeField frame] ),
									  NSWidth( [_freeField frame] ), NSHeight( [_freeField frame] ) )];

	//the name takes what the free-space figure leaves, and the format follows it
	const CGFloat nameRoom = NSMinX( [_freeField frame] ) - textX - 8.0;
	const CGFloat nameWidth = MIN( NSWidth( [_nameField frame] ), MAX( 0.0, nameRoom ) );

	[_nameField setFrame: NSMakeRect( textX, top - nameHeight, nameWidth, nameHeight )];

	const CGFloat detailX = NSMaxX( [_nameField frame] ) + 8.0;

	[_detailField setFrame: NSMakeRect( detailX,
										top - nameHeight + 1.0,
										MAX( 0.0, NSMinX( [_freeField frame] ) - detailX - 8.0 ),
										NSHeight( [_detailField frame] ) )];

	top -= nameHeight + kCardBarGapTop;

	[_bar setFrame: NSMakeRect( textX, top - kCardBarHeight, textWidth, kCardBarHeight )];

	top -= kCardBarHeight + kCardDetailGap;

	[_historyField setFrame: NSMakeRect( textX, top - NSHeight( [_historyField frame] ),
										 textWidth, NSHeight( [_historyField frame] ) )];
}

//A click selects, a double-click scans - the same pair the Finder uses for a
//list, and what the Drives panel this replaces did.
- (void) mouseDown: (NSEvent*) event
{
	[_owner performSelector: @selector(mouseDownInCard:) withObject: self];

	if ( [event clickCount] >= 2 )
		[_owner performSelector: @selector(scanSelection:) withObject: self];
}

- (void) drawRect: (NSRect) dirtyRect
{
	const NSRect bounds = [self bounds];

	[( _selected ? [DIXTheme accentTint] : [DIXTheme surface] ) set];
	NSRectFill( NSIntersectionRect( dirtyRect, bounds ) );

	//0.5pt, the design's control border: an edge rather than a frame
	NSBezierPath *border = [NSBezierPath bezierPathWithRect: NSInsetRect( bounds, 0.25, 0.25 )];

	[( _selected ? [DIXTheme accent] : [DIXTheme controlBorder] ) set];
	[border setLineWidth: 0.5];
	[border stroke];
}

@end

//================ DIXScanPickerController ============================================

@interface DIXScanPickerController()
{
	NSWindow *_window;
	NSView *_cardsView;
	NSTextField *_footerCaption;
	NSButton *_scanButton;
	NSMutableArray<DIXVolumeCard*> *_cards;
	NSInteger _selectedIndex;
}
@end

@implementation DIXScanPickerController

+ (DIXScanPickerController*) sharedController
{
	static DIXScanPickerController *controller = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ controller = [[DIXScanPickerController alloc] init]; } );

	return controller;
}

- (instancetype) init
{
	self = [super init];

	if ( self != nil )
	{
		_cards = [NSMutableArray array];
		_selectedIndex = -1;

		[self buildWindow];

		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(onListsChanged:)
													 name: DIXVolumeListChangedNotification
												   object: nil];

		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(onListsChanged:)
													 name: DIXRecentScansChangedNotification
												   object: nil];
	}

	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver: self];
}

#pragma mark --------building it-----------------

- (void) buildWindow
{
	_window = [[NSWindow alloc] initWithContentRect: NSMakeRect( 0.0, 0.0, kWindowWidth, 360.0 )
										  styleMask: NSWindowStyleMaskTitled
													 | NSWindowStyleMaskClosable
													 | NSWindowStyleMaskMiniaturizable
											backing: NSBackingStoreBuffered
											  defer: NO];

	[_window setTitle: NSLocalizedString( @"Disk Inventory Next", @"scan picker window title" )];
	[_window setTitleVisibility: NSWindowTitleHidden];
	[_window setTitlebarAppearsTransparent: YES];
	[_window setBackgroundColor: [DIXTheme surface]];
	[_window setReleasedWhenClosed: NO];
	[_window setFrameAutosaveName: @"ScanPicker"];

	NSView *content = [_window contentView];

	NSTextField *heading = [NSTextField labelWithString: NSLocalizedString(
		@"Where did the space go?", @"scan picker heading" )];

	[heading setFont: [NSFont systemFontOfSize: kHeadingSize weight: NSFontWeightBold]];
	[heading setTextColor: [DIXTheme ink]];
	[heading setTranslatesAutoresizingMaskIntoConstraints: YES];

	NSTextField *subtitle = [NSTextField labelWithString: NSLocalizedString(
		@"Pick a volume or a folder. Scanning does not change anything on disk.",
		@"scan picker subtitle" )];

	[subtitle setFont: [NSFont systemFontOfSize: 12.0]];
	[subtitle setTextColor: [DIXTheme secondaryText]];
	[subtitle setTranslatesAutoresizingMaskIntoConstraints: YES];

	_cardsView = [[NSView alloc] initWithFrame: NSZeroRect];

	NSButton *choose = [DIXControls secondaryButtonWithTitle:
		NSLocalizedString( @"Choose Folder…", @"scan picker button" )
													 target: self
													 action: @selector(chooseFolder:)];

	[choose setTranslatesAutoresizingMaskIntoConstraints: YES];

	_footerCaption = [NSTextField labelWithString: @""];
	[_footerCaption setFont: [NSFont systemFontOfSize: 11.0]];
	[_footerCaption setTextColor: [DIXTheme secondaryText]];
	[_footerCaption setLineBreakMode: NSLineBreakByTruncatingTail];
	[_footerCaption setTranslatesAutoresizingMaskIntoConstraints: YES];

	_scanButton = [DIXControls primaryButtonWithTitle:
		NSLocalizedString( @"Scan", @"scan picker button" )
											   target: self
											   action: @selector(scanSelection:)];

	[_scanButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[_scanButton setKeyEquivalent: @"\r"];

	for ( NSView *view in @[ heading, subtitle, _cardsView, choose, _footerCaption, _scanButton ] )
		[content addSubview: view];

	//Laid out once, from the top down: the window does not resize, so this is
	//one pass of arithmetic rather than a constraint graph.
	[self rebuildCards];

	CGFloat y = 0.0;
	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;

	[heading sizeToFit];
	[subtitle sizeToFit];
	[choose sizeToFit];
	[_scanButton sizeToFit];

	const CGFloat cardsHeight = NSHeight( [_cardsView frame] );
	const CGFloat contentHeight = kEdgeInset + NSHeight( [heading frame] )
								  + kSubtitleGapTop + NSHeight( [subtitle frame] )
								  + kSubtitleGapBot + cardsHeight
								  + kFooterGap + kFooterButtonH + kEdgeInset;

	[_window setContentSize: NSMakeSize( kWindowWidth, contentHeight )];

	y = contentHeight - kEdgeInset - NSHeight( [heading frame] );
	[heading setFrame: NSMakeRect( kEdgeInset, y, width, NSHeight( [heading frame] ) )];

	y -= kSubtitleGapTop + NSHeight( [subtitle frame] );
	[subtitle setFrame: NSMakeRect( kEdgeInset, y, width, NSHeight( [subtitle frame] ) )];

	y -= kSubtitleGapBot + cardsHeight;
	[_cardsView setFrame: NSMakeRect( kEdgeInset, y, width, cardsHeight )];

	y -= kFooterGap + kFooterButtonH;
	[choose setFrame: NSMakeRect( kEdgeInset, y,
								  MAX( 120.0, NSWidth( [choose frame] ) ), kFooterButtonH )];

	const CGFloat scanWidth = MAX( 88.0, NSWidth( [_scanButton frame] ) );

	[_scanButton setFrame: NSMakeRect( kEdgeInset + width - scanWidth, y, scanWidth, kFooterButtonH )];

	const CGFloat captionX = NSMaxX( [choose frame] ) + kFooterGap;

	[_footerCaption setFrame: NSMakeRect( captionX,
										  y + ( kFooterButtonH - 14.0 ) / 2.0,
										  MAX( 0.0, NSMinX( [_scanButton frame] ) - captionX - kFooterGap ),
										  14.0 )];

	[_window center];
}

//One card per volume, stacked. Rebuilt wholesale when a volume is mounted or a
//scan is recorded: the list is a handful of rows and working out which one moved
//is more code than redrawing it.
- (void) rebuildCards
{
	for ( DIXVolumeCard *card in _cards )
		[card removeFromSuperview];

	[_cards removeAllObjects];

	NSArray<DIXVolume*> *volumes = [[DIXVolumeList sharedList] volumes];
	const CGFloat cardHeight = [DIXVolumeCard preferredHeight];
	const CGFloat width = kWindowWidth - kEdgeInset * 2.0;
	const CGFloat total = MAX( cardHeight,
							   ( cardHeight + kCardGap ) * (CGFloat) [volumes count] - kCardGap );

	[_cardsView setFrameSize: NSMakeSize( width, total )];

	CGFloat y = total;

	for ( DIXVolume *volume in volumes )
	{
		y -= cardHeight;

		DIXVolumeCard *card = [[DIXVolumeCard alloc] initWithFrame:
			NSMakeRect( 0.0, y, width, cardHeight )];

		[card setOwner: self];
		[card setVolume: volume];
		[card setLastScan: [self lastScanOfVolume: volume]];

		[_cardsView addSubview: card];
		[_cards addObject: card];

		y -= kCardGap;
	}

	if ( _selectedIndex >= (NSInteger) [_cards count] )
		_selectedIndex = -1;

	//the first volume is the one anyone means unless they say otherwise
	if ( _selectedIndex < 0 && [_cards count] > 0 )
		_selectedIndex = 0;

	[self applySelection];
}

- (DIXRecentScan*) lastScanOfVolume: (DIXVolume*) volume
{
	for ( DIXRecentScan *scan in [[DIXRecentScans sharedList] scans] )
		if ( [[[scan url] path] isEqualToString: [[volume url] path]] )
			return scan;

	return nil;
}

- (void) applySelection
{
	for ( NSUInteger i = 0; i < [_cards count]; i++ )
		[[_cards objectAtIndex: i] setSelected: ( (NSInteger) i == _selectedIndex )];

	[_scanButton setEnabled: _selectedIndex >= 0];

	//"Last scan of Macintosh HD: 8 Aug, 91.8 GB" - the same statement the
	//selected card makes, said once more where the eye ends up before Scan
	NSString *caption = @"";

	if ( _selectedIndex >= 0 )
	{
		DIXVolume *volume = [[[DIXVolumeList sharedList] volumes] objectAtIndex: _selectedIndex];
		DIXRecentScan *scan = [self lastScanOfVolume: volume];

		if ( scan != nil )
		{
			NSDateFormatter *when = [[NSDateFormatter alloc] init];
			[when setDateFormat: [NSDateFormatter dateFormatFromTemplate: @"dMMM"
																 options: 0
																  locale: [NSLocale currentLocale]]];

			FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

			caption = [NSString stringWithFormat:
				NSLocalizedString( @"Last scan of %@: %@, %@", @"scan picker footer" ),
				[volume name], [when stringFromDate: [scan scannedAt]],
				[sizeFormatter stringForObjectValue: @([scan size])]];
		}
	}

	[_footerCaption setStringValue: caption];
}

#pragma mark --------showing it-----------------

- (void) showPicker
{
	[self rebuildCards];
	[_window makeKeyAndOrderFront: nil];
}

- (BOOL) pickerIsVisible
{
	return [_window isVisible];
}

- (void) onListsChanged: (NSNotification*) notification
{
	if ( [_window isVisible] )
		[self rebuildCards];
}

#pragma mark --------choosing-----------------

- (void) mouseDownInCard: (DIXVolumeCard*) card
{
	const NSUInteger index = [_cards indexOfObject: card];

	if ( index == NSNotFound )
		return;

	_selectedIndex = (NSInteger) index;
	[self applySelection];
}

- (IBAction) scanSelection: (id) sender
{
	NSArray<DIXVolume*> *volumes = [[DIXVolumeList sharedList] volumes];

	if ( _selectedIndex < 0 || _selectedIndex >= (NSInteger) [volumes count] )
		return;

	NSURL *url = [[volumes objectAtIndex: _selectedIndex] url];

	[_window orderOut: nil];

	[[NSDocumentController sharedDocumentController]
		openDocumentWithContentsOfURL: url
							  display: YES
					completionHandler: ^( NSDocument *document, BOOL alreadyOpen, NSError *error )
	{
		//back on screen if nothing opened, rather than leaving the application
		//with no window and no explanation
		if ( document == nil )
			[self->_window makeKeyAndOrderFront: nil];
	}];
}

- (IBAction) chooseFolder: (id) sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];

	[panel setCanChooseDirectories: YES];
	[panel setCanChooseFiles: NO];
	[panel setAllowsMultipleSelection: NO];
	[panel setTreatsFilePackagesAsDirectories: YES];
	[panel setPrompt: NSLocalizedString( @"Scan", @"scan picker button" )];

	[panel beginSheetModalForWindow: _window completionHandler: ^( NSModalResponse response )
	{
		if ( response != NSModalResponseOK || [panel URL] == nil )
			return;

		[self->_window orderOut: nil];

		[[NSDocumentController sharedDocumentController]
			openDocumentWithContentsOfURL: [panel URL]
								  display: YES
						completionHandler: ^( NSDocument *document, BOOL alreadyOpen, NSError *error )
		{
			if ( document == nil )
				[self->_window makeKeyAndOrderFront: nil];
		}];
	}];
}

@end
