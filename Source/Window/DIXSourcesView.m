//
//  DIXSourcesView.m
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

#import "DIXSourcesView.h"
#import "DIXVolumeList.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "FileSizeFormatter.h"
#import "NSImage-Extensions.h"

static const CGFloat kPadding       = 14.0;
static const CGFloat kLabelHeight   = 18.0;
static const CGFloat kLabelGap      = 10.0;
static const CGFloat kRowHeight     = 41.0;
static const CGFloat kChooseHeight  = 34.0;
static const CGFloat kIconSize      = 15.0;
static const CGFloat kIconGap       = 10.0;
static const CGFloat kBarHeight     =  4.0;
static const CGFloat kBarTopGap     =  7.0;

//Free space moves as the machine is used, and nothing announces it. Five
//seconds is what the Drives panel already uses; the timer only runs while this
//is in a window, so a closed sidebar costs nothing.
static const NSTimeInterval kSizeRefreshInterval = 5.0;

@interface DIXSourcesView()
{
	NSTextField *_sectionLabel;
	NSMutableArray<NSView*> *_rowViews;      //one container per volume
	NSButton *_chooseButton;
	//One entry per volume, so an index is shared with -volumes: the volume's
	//bar, or NSNull for a volume that cannot say how big it is.
	NSMutableArray *_bars;

	NSURL *_currentVolumeURL;
	NSInteger _hoveredRow;                   //-1 for none
	NSTimer *_refreshTimer;
	NSTrackingArea *_trackingArea;
}
@end

@implementation DIXSourcesView

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
	//NSTimer retains its target, so a running one would keep this view - and the
	//window behind it - alive after the window closed
	[_refreshTimer invalidate];

	[[NSNotificationCenter defaultCenter] removeObserver: self];
}

//Laid out by hand, like the rest of Source/Window/. See the note in
//DIXStatusBarView about what -drawRect: must not do here.
- (void) buildViewHierarchy
{
	_hoveredRow = -1;
	_rowViews = [NSMutableArray array];
	_bars = [NSMutableArray array];

	_sectionLabel = [DIXControls sectionLabelWithTitle:
		NSLocalizedString( @"SOURCES", @"sidebar section, what can be scanned" )];
	[_sectionLabel setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _sectionLabel];

	_chooseButton = [NSButton buttonWithTitle:
		NSLocalizedString( @"Choose Folder…", @"sidebar, scan something that is not a volume" )
									   target: self
									   action: @selector(chooseFolder:)];
	[_chooseButton setBordered: NO];
	[_chooseButton setImage: [NSImage imageForSymbolName: @"folder"
							   accessibilityDescription: NSLocalizedString( @"Choose Folder…",
																			@"sidebar, scan something that is not a volume" )]];
	[_chooseButton setImagePosition: NSImageLeft];
	[_chooseButton setAlignment: NSTextAlignmentLeft];
	[_chooseButton setFont: [NSFont systemFontOfSize: 13.0]];
	[_chooseButton setContentTintColor: [DIXTheme bodyText]];
	[_chooseButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _chooseButton];

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(onVolumesChanged:)
												 name: DIXVolumeListChangedNotification
											   object: nil];

	[self rebuildRows];
}

#pragma mark --------rows-----------------

- (void) rebuildRows
{
	for ( NSView *row in _rowViews )
		[row removeFromSuperview];

	[_rowViews removeAllObjects];
	[_bars removeAllObjects];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	for ( DIXVolume *volume in [[DIXVolumeList sharedList] volumes] )
	{
		NSView *row = [[NSView alloc] initWithFrame: NSZeroRect];

		NSImageView *icon = [NSImageView imageViewWithImage:
			[volume icon] ?: [NSImage imageForSymbolName: @"externaldrive"
								accessibilityDescription: [volume name]]];
		[icon setImageScaling: NSImageScaleProportionallyUpOrDown];
		[icon setTranslatesAutoresizingMaskIntoConstraints: YES];
		[row addSubview: icon];

		NSTextField *name = [NSTextField labelWithString: [volume name]];
		[name setFont: [NSFont systemFontOfSize: 13.0 weight: NSFontWeightMedium]];
		[name setTextColor: [DIXTheme ink]];
		[name setLineBreakMode: NSLineBreakByTruncatingTail];
		[name setTranslatesAutoresizingMaskIntoConstraints: YES];
		[row addSubview: name];

		//A volume that cannot say how big it is gets its format instead of a
		//figure, rather than a confident "0 bytes free" - a network share that
		//mounts without sizes is the usual case.
		//Free space stays on the name's line and the capacity moves down beside
		//the bar. Both figures on one line was tried twice and does not fit: a
		//244pt sidebar leaves about 174pt after the icon and the margins, and
		//"Macintosh HD" plus "42.1 GB / 995.1 GB" wants closer to 200 - so either
		//the name truncated to a single letter or the capacity was clipped off
		//the end. The second line is empty apart from a 4pt bar, and the capacity
		//is what that bar is a proportion of.
		NSString *detail = [volume knowsItsSize]
			? [NSString stringWithFormat: NSLocalizedString( @"%@ free", @"sidebar, a volume's free space" ),
										  [sizeFormatter stringForObjectValue: @([volume availableCapacity])]]
			: ( [volume formatDescription] ?: @"" );

		NSTextField *free = [NSTextField labelWithString: detail];
		[free setFont: [DIXTheme tabularFontOfSize: 11.0]];
		[free setTextColor: [DIXTheme secondaryText]];
		[free setAlignment: NSTextAlignmentRight];
		[free setTranslatesAutoresizingMaskIntoConstraints: YES];
		[row addSubview: free];

		if ( [volume knowsItsSize] )
		{
			//Not the accent. The accent marks the selection, in the map and in
			//the list, and a sidebar with two permanently red bars in it spends
			//that meaning on something that is not a selection at all - see the
			//note on -accent in DIXTheme.h. The design draws these in ink for the
			//volume being shown and in the muted step for the rest.
			DIXShareBar *bar = [DIXShareBar barWithFraction: [volume usedFraction]
												  fillColor: [DIXTheme muted]];
			[bar setTranslatesAutoresizingMaskIntoConstraints: YES];
			[row addSubview: bar];
			[_bars addObject: bar];

			NSTextField *capacity = [NSTextField labelWithString:
				[sizeFormatter stringForObjectValue: @([volume totalCapacity])]];
			[capacity setFont: [DIXTheme tabularFontOfSize: 10.0]];
			[capacity setTextColor: [DIXTheme tertiaryText]];
			[capacity setAlignment: NSTextAlignmentRight];
			[capacity setTranslatesAutoresizingMaskIntoConstraints: YES];
			[row addSubview: capacity];
		}
		else
		{
			[_bars addObject: [NSNull null]];
		}

		[self addSubview: row];
		[_rowViews addObject: row];
	}

	[self applyCurrentVolumeStyling];
	[self layoutContents];
	[self setNeedsDisplay: YES];
}

- (void) onVolumesChanged: (NSNotification*) notification
{
	[self rebuildRows];
}

- (CGFloat) fittingHeight
{
	return kPadding + kLabelHeight + kLabelGap
		 + ( kRowHeight * (CGFloat) [_rowViews count] )
		 + kChooseHeight + kPadding;
}

- (void) setCurrentVolumeURL: (NSURL*) url
{
	if ( url == _currentVolumeURL || [url isEqual: _currentVolumeURL] )
		return;

	_currentVolumeURL = url;

	[self applyCurrentVolumeStyling];
	[self setNeedsDisplay: YES];
}

//The current volume's bar is ink on a deep track, every other one muted on the
//ordinary track. The deep track is not decoration: the current row is filled,
//and on that fill the ordinary track is close enough in tone that the bar stops
//showing how far along it is.
- (void) applyCurrentVolumeStyling
{
	NSArray<DIXVolume*> *volumes = [[DIXVolumeList sharedList] volumes];

	for ( NSUInteger i = 0; i < [_bars count] && i < [volumes count]; i++ )
	{
		DIXShareBar *bar = [_bars objectAtIndex: i];

		if ( (id) bar == [NSNull null] )
			continue;

		const BOOL isCurrent = ( _currentVolumeURL != nil
								 && [[[volumes objectAtIndex: i] url] isEqual: _currentVolumeURL] );

		[bar setFillColor: isCurrent ? [DIXTheme ink] : [DIXTheme muted]];
		[bar setTrackColor: isCurrent ? [DIXTheme barTrackDeep] : [DIXTheme barTrack]];
	}
}

#pragma mark --------layout-----------------

- (void) setFrameSize: (NSSize) newSize
{
	[super setFrameSize: newSize];
	[self layoutContents];
}

- (NSRect) rectForRowAtIndex: (NSUInteger) index
{
	//the view is unflipped, so laying out from the top means counting down
	const CGFloat top = NSMaxY( [self bounds] ) - kPadding - kLabelHeight - kLabelGap;

	return NSMakeRect( 0.0, top - kRowHeight * (CGFloat) ( index + 1 ),
					   NSWidth( [self bounds] ), kRowHeight );
}

- (void) layoutContents
{
	const NSRect bounds = [self bounds];
	const CGFloat contentWidth = NSWidth( bounds ) - kPadding * 2.0;

	if ( contentWidth <= 0.0 )
		return;

	[_sectionLabel setFrame: NSMakeRect( kPadding, NSMaxY( bounds ) - kPadding - kLabelHeight,
										 contentWidth, kLabelHeight )];

	for ( NSUInteger i = 0; i < [_rowViews count]; i++ )
	{
		NSView *row = [_rowViews objectAtIndex: i];
		const NSRect rowRect = [self rectForRowAtIndex: i];

		[row setFrame: rowRect];

		const CGFloat innerWidth = NSWidth( rowRect ) - kPadding * 2.0;

		if ( innerWidth <= 0.0 )
			continue;

		NSArray<NSView*> *parts = [row subviews];
		NSImageView *icon = (NSImageView*) [parts objectAtIndex: 0];
		NSTextField *name = (NSTextField*) [parts objectAtIndex: 1];
		NSTextField *free = (NSTextField*) [parts objectAtIndex: 2];

		const CGFloat textTop = NSHeight( rowRect ) - 10.0;

		[icon setFrame: NSMakeRect( kPadding, textTop - kIconSize, kIconSize, kIconSize )];

		[free sizeToFit];

		const CGFloat freeWidth = MIN( NSWidth( [free frame] ), innerWidth * 0.5 );
		const CGFloat nameX = kPadding + kIconSize + kIconGap;

		[free setFrame: NSMakeRect( NSMaxX( rowRect ) - kPadding - freeWidth,
									textTop - 16.0, freeWidth, 16.0 )];
		[name setFrame: NSMakeRect( nameX, textTop - 16.0,
									MAX( 0.0, NSMaxX( [free frame] ) - freeWidth - 8.0 - nameX ), 16.0 )];

		if ( [parts count] > 3 )
		{
			//The bar runs from the name's leading edge and stops short of the
			//capacity, which sits at the end of the same line: the bar is a
			//proportion and that is the number it is a proportion of.
			const CGFloat capacityWidth = 62.0;
			const CGFloat barY = textTop - 16.0 - kBarTopGap - kBarHeight;

			[[parts objectAtIndex: 3] setFrame:
				NSMakeRect( nameX, barY,
							MAX( 0.0, NSMaxX( rowRect ) - kPadding - capacityWidth - 8.0 - nameX ),
							kBarHeight )];

			if ( [parts count] > 4 )
			{
				[[parts objectAtIndex: 4] setFrame:
					NSMakeRect( NSMaxX( rowRect ) - kPadding - capacityWidth, barY - 5.0,
								capacityWidth, 14.0 )];
			}
		}
	}

	//No rule above Choose Folder: the design has none there. The 2pt rule the
	//sidebar does have separates this whole section from FILE KINDS, and belongs
	//to neither view - MainWindowController draws it between them.
	const CGFloat chooseTop = NSMinY( [self rectForRowAtIndex: MAX( (NSInteger)[_rowViews count], 1 ) - 1 ] );

	[_chooseButton setFrame: NSMakeRect( kPadding - 2.0, chooseTop - kChooseHeight,
										 contentWidth, kChooseHeight )];
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Clamped to this view's bounds - see the note in DIXStatusBarView's
	//-drawRect:. The dirty rect can span the whole content view, and filling it
	//paints over every sibling drawn before this one.
	[[DIXTheme sidebar] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	NSArray<DIXVolume*> *volumes = [[DIXVolumeList sharedList] volumes];

	for ( NSUInteger i = 0; i < [_rowViews count] && i < [volumes count]; i++ )
	{
		const BOOL isCurrent = ( _currentVolumeURL != nil
								 && [[[volumes objectAtIndex: i] url] isEqual: _currentVolumeURL] );

		if ( !isCurrent && (NSInteger) i != _hoveredRow )
			continue;

		NSRect rowRect = NSInsetRect( [self rectForRowAtIndex: i], kPadding - 6.0, 2.0 );

		[( isCurrent ? [DIXTheme selectedRowFill] : [DIXTheme controlFill] ) set];

		NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: rowRect
															xRadius: [DIXTheme cornerRadius]
															yRadius: [DIXTheme cornerRadius]];
		[path fill];
	}
}

#pragma mark --------opening-----------------

- (void) mouseUp: (NSEvent*) event
{
	const NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
	NSArray<DIXVolume*> *volumes = [[DIXVolumeList sharedList] volumes];

	for ( NSUInteger i = 0; i < [_rowViews count] && i < [volumes count]; i++ )
	{
		if ( !NSPointInRect( point, [self rectForRowAtIndex: i] ) )
			continue;

		[self openURL: [[volumes objectAtIndex: i] url]];
		return;
	}
}

//Deferred to the next turn of the run loop, the way DrivesPanelController opens
//a volume: a scan takes long enough that starting one from inside the click
//leaves the row drawn in its pressed state for the whole of it.
- (void) openURL: (NSURL*) url
{
	if ( url == nil )
		return;

	[[NSRunLoop currentRunLoop] performSelector: @selector(openDocumentWithContentsOfFile:)
										 target: [NSDocumentController sharedDocumentController]
									   argument: [url path]
										  order: 1
										  modes: @[ NSDefaultRunLoopMode ]];
}

- (void) chooseFolder: (id) sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];

	[panel setCanChooseFiles: NO];
	[panel setCanChooseDirectories: YES];
	[panel setAllowsMultipleSelection: NO];
	[panel setPrompt: NSLocalizedString( @"Scan", @"open panel button, start scanning the chosen folder" )];

	__weak DIXSourcesView *weakSelf = self;

	[panel beginSheetModalForWindow: [self window] completionHandler: ^( NSModalResponse response )
	{
		if ( response == NSModalResponseOK )
			[weakSelf openURL: [panel URL]];
	}];
}

#pragma mark --------hover and the refresh timer-----------------

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];

	if ( _trackingArea != nil )
		[self removeTrackingArea: _trackingArea];

	_trackingArea = [[NSTrackingArea alloc] initWithRect: [self bounds]
												 options: ( NSTrackingMouseMoved
															| NSTrackingMouseEnteredAndExited
															| NSTrackingActiveInKeyWindow )
												   owner: self
												userInfo: nil];
	[self addTrackingArea: _trackingArea];
}

- (void) setHoveredRow: (NSInteger) row
{
	if ( row == _hoveredRow )
		return;

	_hoveredRow = row;
	[self setNeedsDisplay: YES];
}

- (void) mouseMoved: (NSEvent*) event
{
	const NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];

	for ( NSUInteger i = 0; i < [_rowViews count]; i++ )
	{
		if ( NSPointInRect( point, [self rectForRowAtIndex: i] ) )
		{
			[self setHoveredRow: (NSInteger) i];
			return;
		}
	}

	[self setHoveredRow: -1];
}

- (void) mouseExited: (NSEvent*) event
{
	[self setHoveredRow: -1];
}

//The timer follows the view in and out of a window, so a closed document stops
//re-reading free space rather than keeping a machine awake for a list nobody
//is looking at.
- (void) viewDidMoveToWindow
{
	[super viewDidMoveToWindow];

	[_refreshTimer invalidate];
	_refreshTimer = nil;

	if ( [self window] == nil )
		return;

	__weak DIXSourcesView *weakSelf = self;

	_refreshTimer = [NSTimer scheduledTimerWithTimeInterval: kSizeRefreshInterval
													repeats: YES
													  block: ^( NSTimer *timer )
	{
		if ( [weakSelf window] == nil )
			return;

		[[DIXVolumeList sharedList] refreshSizes];
	}];
}

@end
