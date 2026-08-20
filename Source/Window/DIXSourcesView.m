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
#import "DIXRecentScans.h"

static const CGFloat kPadding       = 14.0;
static const CGFloat kLabelHeight   = 18.0;
static const CGFloat kLabelGap      = 10.0;
//A row, from the top: 7 points of padding, the name and free-space line, a
//6 point gap, the bar's line, 7 points of padding. 7+16+6+12+7.
//
//The design's row is 40, because its bar line is the bar's own 4 points. Ours
//shares that line with the capacity figure - a 10pt number, which wants 12 -
//and the row is 8 points taller for it. That figure is this fork's addition,
//so the extra height is too.
static const CGFloat kRowPaddingV   =  7.0;
static const CGFloat kTextLine      = 16.0;
static const CGFloat kCapacityLine  = 12.0;
static const CGFloat kRowHeight     = 48.0;
static const CGFloat kChooseHeight  = 34.0;

//A folder that has been scanned before: its name and total on one line, then
//where it is and when it was last looked at. 7 + 16 + 15 + 7.
//
//Drawn rather than built out of views, the way DIXKindsView draws its rows.
//The one thing that *is* clickable inside a row - the button that forgets it -
//is hit tested against its own rect in -mouseUp:, which is less machinery than
//a button per row that has to be created and destroyed as the list changes.
static const CGFloat kRecentRowHeight = 45.0;
static const CGFloat kRecentDetailLine = 15.0;
static const CGFloat kForgetSize = 16.0;
static const CGFloat kIconSize      = 15.0;
static const CGFloat kIconGap       = 10.0;
static const CGFloat kBarHeight     =  4.0;
static const CGFloat kBarTopGap     =  6.0;   //the design's margin-top

//Free space moves as the machine is used, and nothing announces it. Five
//seconds is what the Drives panel already uses; the timer only runs while this
//is in a window, so a closed sidebar costs nothing.
static const NSTimeInterval kSizeRefreshInterval = 5.0;

//The document view of the scroll around the folder list. It owns no state and
//makes no decisions: the section draws into it and hit tests against it, so the
//row code did not have to move or learn about two coordinate spaces - it simply
//measures from this view's bounds instead of the section's.
@interface DIXRecentsDocumentView : NSView
@property (nonatomic, weak) DIXSourcesView *owner;
@end

//what the document view hands back
@interface DIXSourcesView(RecentsDocumentView)
- (void) drawRecentsInRect: (NSRect) dirtyRect;
- (void) recentsMouseUp: (NSEvent*) event;
- (void) recentsMouseMoved: (NSEvent*) event;
- (void) recentsMouseExited;
@end

@interface DIXSourcesView()
{
	NSTextField *_sectionLabel;
	NSMutableArray<NSView*> *_rowViews;      //one container per volume
	NSButton *_chooseButton;
	//One entry per volume, so an index is shared with -volumes: the volume's
	//bar, or NSNull for a volume that cannot say how big it is.
	NSMutableArray *_bars;

	//folders scanned before, most recent first, and their icons
	NSScrollView *_recentsScroll;
	DIXRecentsDocumentView *_recentsView;
	NSMutableArray<DIXRecentScan*> *_recents;
	NSMutableArray<NSImage*> *_recentIcons;
	NSInteger _hoveredRecent;   //-1 for none; separate, so the forget button can show

	NSURL *_currentVolumeURL;
	NSURL *_currentRootURL;      //what this window scanned, which may be a folder
	NSInteger _hoveredRow;                   //-1 for none
	NSTimer *_refreshTimer;
	NSTrackingArea *_trackingArea;
}
@end

@implementation DIXRecentsDocumentView

- (void) drawRect: (NSRect) dirtyRect      { [_owner drawRecentsInRect: dirtyRect]; }
- (void) mouseUp: (NSEvent*) event         { [_owner recentsMouseUp: event]; }
- (void) mouseMoved: (NSEvent*) event      { [_owner recentsMouseMoved: event]; }
- (void) mouseExited: (NSEvent*) event     { [_owner recentsMouseExited]; }

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];

	for ( NSTrackingArea *area in [self trackingAreas] )
		[self removeTrackingArea: area];

	[self addTrackingArea:
		[[NSTrackingArea alloc] initWithRect: [self bounds]
									 options: ( NSTrackingMouseMoved
												| NSTrackingMouseEnteredAndExited
												| NSTrackingActiveInKeyWindow )
									   owner: self userInfo: nil]];
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
	_recents = [NSMutableArray array];
	_recentIcons = [NSMutableArray array];
	_hoveredRecent = -1;

	_sectionLabel = [DIXControls sectionLabelWithTitle:
		NSLocalizedString( @"SOURCES", @"sidebar section, what can be scanned" )];
	[_sectionLabel setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _sectionLabel];

	//Only the folders scroll. The volumes are the fixed part of the section and
	//Choose Folder is how you add to it, so both stay put and the list between
	//them takes whatever room is left.
	_recentsView = [[DIXRecentsDocumentView alloc] initWithFrame: NSZeroRect];
	[_recentsView setOwner: self];

	_recentsScroll = [[NSScrollView alloc] initWithFrame: NSZeroRect];
	[_recentsScroll setDocumentView: _recentsView];
	[_recentsScroll setHasVerticalScroller: YES];
	[_recentsScroll setAutohidesScrollers: YES];
	[_recentsScroll setDrawsBackground: NO];
	[_recentsScroll setBorderType: NSNoBorder];
	[DIXControls useOverlayScrollersIn: _recentsScroll];
	[_recentsScroll setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _recentsScroll];

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
	[_chooseButton setContentTintColor: [DIXTheme detailText]];
	[self applyChooseButtonTitleColor];
	[_chooseButton setTranslatesAutoresizingMaskIntoConstraints: YES];
	[self addSubview: _chooseButton];

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(onVolumesChanged:)
												 name: DIXVolumeListChangedNotification
											   object: nil];

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(onVolumesChanged:)
												 name: DIXRecentScansChangedNotification
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

	[self rebuildRecents];
	[self applyCurrentVolumeStyling];
	[self layoutContents];
	[self setNeedsDisplay: YES];
}

//Folders scanned before, most recent first, one row each - the store gives one
//entry per folder, so scanning the same one twice moves it up rather than
//listing it again with an older total beside it.
//
//Volumes are left out: they are listed above under their own names, with a
//usage bar this row has no room and no figures for.
- (void) rebuildRecents
{
	[_recents removeAllObjects];
	[_recentIcons removeAllObjects];

	NSMutableSet<NSString*> *volumePaths = [NSMutableSet set];

	for ( DIXVolume *volume in [[DIXVolumeList sharedList] volumes] )
	{
		if ( [[volume url] path] != nil )
			[volumePaths addObject: [[volume url] path]];
	}

	for ( DIXRecentScan *scan in [[DIXRecentScans sharedList] scans] )
	{
		if ( [volumePaths containsObject: [[scan url] path]] )
			continue;

		[_recents addObject: scan];
		[_recentIcons addObject: [[NSWorkspace sharedWorkspace] iconForFile: [[scan url] path]]];
	}

	//The recents are drawn by the scroll view's document view, so the
	//-setNeedsDisplay: the caller sends itself does not reach them. Without
	//this these rows kept whatever "3 minutes ago" they were drawn with and
	//only came right when something else happened to invalidate them - the
	//refresh timer was redrawing everything except the one part that ages.
	[_recentsView setNeedsDisplay: YES];
}

- (void) onVolumesChanged: (NSNotification*) notification
{
	[self rebuildRows];
}

- (CGFloat) fittingHeight
{
	return kPadding + kLabelHeight + kLabelGap
		 + ( kRowHeight * (CGFloat) [_rowViews count] )
		 + ( kRecentRowHeight * (CGFloat) [_recents count] )
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

- (void) setCurrentRootURL: (NSURL*) url
{
	if ( url == _currentRootURL || [url isEqual: _currentRootURL] )
		return;

	_currentRootURL = url;
	[self setNeedsDisplay: YES];
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

//In the document view's own coordinates, counting down from its top.
- (NSRect) rectForRecentAtIndex: (NSUInteger) index
{
	const CGFloat contentHeight = kRecentRowHeight * (CGFloat) [_recents count];

	return NSMakeRect( 0.0, contentHeight - kRecentRowHeight * (CGFloat) ( index + 1 ),
					   NSWidth( [_recentsView bounds] ), kRecentRowHeight );
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

		//Measured down from the row's top padding rather than from a number that
		//happened to look right: with the row at its old height the bar had 4
		//points below it instead of 7 and the capacity figure sat at y=-1,
		//hanging out of the row altogether.
		const CGFloat textTop = NSHeight( rowRect ) - kRowPaddingV;
		const CGFloat textY   = textTop - kTextLine;

		//the icon is smaller than the line, so it centres on it
		[icon setFrame: NSMakeRect( kPadding,
									textY + floor( ( kTextLine - kIconSize ) / 2.0 ),
									kIconSize, kIconSize )];

		[free sizeToFit];

		const CGFloat freeWidth = MIN( NSWidth( [free frame] ), innerWidth * 0.5 );
		const CGFloat nameX = kPadding + kIconSize + kIconGap;

		[free setFrame: NSMakeRect( NSMaxX( rowRect ) - kPadding - freeWidth,
									textY, freeWidth, kTextLine )];
		[name setFrame: NSMakeRect( nameX, textY,
									MAX( 0.0, NSMaxX( [free frame] ) - freeWidth - 8.0 - nameX ), kTextLine )];

		if ( [parts count] > 3 )
		{
			//The bar runs from the name's leading edge and stops short of the
			//capacity, which sits at the end of the same line: the bar is a
			//proportion and that is the number it is a proportion of.
			const CGFloat capacityWidth = 62.0;

			//The bar and the capacity figure share a line, and the figure is the
			//taller of the two, so the line is its height and the bar centres in
			//it. Its bottom is the row's bottom padding, which is what puts the
			//7 points back underneath.
			const CGFloat lineBottom = kRowPaddingV;
			const CGFloat barY = lineBottom + floor( ( kCapacityLine - kBarHeight ) / 2.0 );

			[[parts objectAtIndex: 3] setFrame:
				NSMakeRect( nameX, barY,
							MAX( 0.0, NSMaxX( rowRect ) - kPadding - capacityWidth - 8.0 - nameX ),
							kBarHeight )];

			if ( [parts count] > 4 )
			{
				[[parts objectAtIndex: 4] setFrame:
					NSMakeRect( NSMaxX( rowRect ) - kPadding - capacityWidth, lineBottom,
								capacityWidth, kCapacityLine )];
			}
		}
	}

	//No rule above Choose Folder: the design has none there. The 2pt rule the
	//sidebar does have separates this whole section from FILE KINDS, and belongs
	//to neither view - MainWindowController draws it between them.
	//Choose Folder is pinned to the bottom of whatever height the section was
	//given, the volumes sit under the heading at the top, and the folder list
	//takes what is left between them - which is what scrolls when there is more
	//of it than there is room.
	[_chooseButton setFrame: NSMakeRect( kPadding - 2.0, kPadding,
										 contentWidth, kChooseHeight )];

	const CGFloat recentsTop = ( [_rowViews count] > 0 )
		? NSMinY( [self rectForRowAtIndex: [_rowViews count] - 1] )
		: NSMaxY( bounds ) - kPadding - kLabelHeight - kLabelGap;

	const CGFloat recentsBottom = kPadding + kChooseHeight;
	const CGFloat recentsHeight = MAX( 0.0, recentsTop - recentsBottom );

	[_recentsScroll setFrame: NSMakeRect( 0.0, recentsBottom, NSWidth( bounds ), recentsHeight )];
	[_recentsScroll setHidden: ( [_recents count] == 0 )];

	//The document view is as tall as the rows need. When that is more than the
	//scroll view can show, the scroller appears and this is what moves under it.
	[_recentsView setFrame: NSMakeRect( 0.0, 0.0, NSWidth( bounds ),
										MAX( recentsHeight,
											 kRecentRowHeight * (CGFloat) [_recents count] ) )];
}

//The design draws this row - folder glyph and label together - in the muted
//tone, not in ink: it is an offer, not a heading. -contentTintColor colours the
//symbol and leaves the title to the system's label colour, so the title has to
//be attributed, and an attributed one holds a resolved colour and has to be
//rebuilt when the appearance changes.
- (void) applyChooseButtonTitleColor
{
	if ( _chooseButton == nil )
		return;

	__block NSColor *color = nil;

	[[self effectiveAppearance] performAsCurrentDrawingAppearance: ^
	{
		color = [[DIXTheme detailText] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]]
				?: [DIXTheme detailText];
	}];

	[_chooseButton setAttributedTitle:
		[[NSAttributedString alloc] initWithString: [_chooseButton title]
										attributes: @{ NSForegroundColorAttributeName: color,
													   NSFontAttributeName: [_chooseButton font] }]];
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self applyChooseButtonTitleColor];
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
															xRadius: [DIXTheme rowCornerRadius]
															yRadius: [DIXTheme rowCornerRadius]];
		[path fill];
	}

}

//The same row treatment as a volume: name and total on one line, then where it
//is and when it was last scanned. A folder gets no usage bar - it has no
//capacity for one to be a proportion of.
- (void) drawRecentsInRect: (NSRect) dirtyRect
{
	if ( [_recents count] == 0 )
		return;

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	NSDictionary *nameAttributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize: 13.0 weight: NSFontWeightMedium],
		NSForegroundColorAttributeName: [DIXTheme ink],
	};
	NSDictionary *sizeAttributes = @{
		NSFontAttributeName: [DIXTheme tabularFontOfSize: 11.0],
		NSForegroundColorAttributeName: [DIXTheme detailText],
	};

	NSMutableParagraphStyle *middleTruncating = [[NSMutableParagraphStyle alloc] init];
	[middleTruncating setLineBreakMode: NSLineBreakByTruncatingMiddle];

	//The path is truncated in the *middle*: the two ends say which disk it is on
	//and which folder it is, and the part worth losing is between them.
	NSDictionary *detailAttributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize: 11.0],
		NSForegroundColorAttributeName: [DIXTheme muted],
		NSParagraphStyleAttributeName: middleTruncating,
	};

	for ( NSUInteger i = 0; i < [_recents count]; i++ )
	{
		const NSRect row = [self rectForRecentAtIndex: i];

		if ( !NSIntersectsRect( row, dirtyRect ) )
			continue;

		DIXRecentScan *scan = [_recents objectAtIndex: i];

		const BOOL isCurrent = ( _currentRootURL != nil && [[scan url] isEqual: _currentRootURL] );
		const BOOL isHovered = ( (NSInteger) i == _hoveredRecent );

		if ( isCurrent || isHovered )
		{
			[( isCurrent ? [DIXTheme selectedRowFill] : [DIXTheme controlFill] ) set];

			[[NSBezierPath bezierPathWithRoundedRect: NSInsetRect( row, kPadding - 6.0, 1.0 )
											 xRadius: [DIXTheme rowCornerRadius]
											 yRadius: [DIXTheme rowCornerRadius]] fill];
		}

		const CGFloat nameY = NSMaxY( row ) - kRowPaddingV - kTextLine;
		const CGFloat detailY = nameY - kRecentDetailLine;

		[[_recentIcons objectAtIndex: i]
			drawInRect: NSMakeRect( kPadding, nameY + floor( ( kTextLine - kIconSize ) / 2.0 ),
									kIconSize, kIconSize )
			  fromRect: NSZeroRect operation: NSCompositingOperationSourceOver
			  fraction: 1.0 respectFlipped: YES hints: nil];

		//The button that forgets a row only appears under the pointer. It takes
		//the space the total would use, so the two never overlap.
		CGFloat rightEdge = NSMaxX( row ) - kPadding;

		if ( isHovered )
		{
			const NSRect forget = [self forgetButtonRectForRecentAtIndex: i];

			[[DIXTheme muted] set];

			NSBezierPath *cross = [NSBezierPath bezierPath];
			const CGFloat inset = 4.5;
			[cross moveToPoint: NSMakePoint( NSMinX(forget) + inset, NSMinY(forget) + inset )];
			[cross lineToPoint: NSMakePoint( NSMaxX(forget) - inset, NSMaxY(forget) - inset )];
			[cross moveToPoint: NSMakePoint( NSMinX(forget) + inset, NSMaxY(forget) - inset )];
			[cross lineToPoint: NSMakePoint( NSMaxX(forget) - inset, NSMinY(forget) + inset )];
			[cross setLineWidth: 1.5];
			[cross setLineCapStyle: NSLineCapStyleRound];
			[cross stroke];

			rightEdge = NSMinX( forget ) - 6.0;
		}
		else
		{
			NSString *total = [sizeFormatter stringForObjectValue: @([scan size])];
			const NSSize extent = [total sizeWithAttributes: sizeAttributes];

			[total drawAtPoint: NSMakePoint( rightEdge - extent.width, nameY + 2.0 )
				withAttributes: sizeAttributes];

			rightEdge -= extent.width + 6.0;
		}

		const CGFloat nameX = kPadding + kIconSize + kIconGap;

		[[scan name] drawInRect: NSMakeRect( nameX, nameY, MAX( 0.0, rightEdge - nameX ), kTextLine )
				 withAttributes: nameAttributes];

		NSString *detail = [NSString stringWithFormat: @"%@ · %@",
			[scan abbreviatedPath],
			[DIXRecentScan relativeTimeStringForDate: [scan scannedAt]]];

		[detail drawInRect: NSMakeRect( nameX, detailY,
										MAX( 0.0, NSMaxX( row ) - kPadding - nameX ), kRecentDetailLine )
			withAttributes: detailAttributes];
	}
}

- (NSRect) forgetButtonRectForRecentAtIndex: (NSUInteger) index
{
	const NSRect row = [self rectForRecentAtIndex: index];

	return NSMakeRect( NSMaxX( row ) - kPadding - kForgetSize,
					   NSMaxY( row ) - kRowPaddingV - kTextLine
						 + floor( ( kTextLine - kForgetSize ) / 2.0 ),
					   kForgetSize, kForgetSize );
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

- (void) recentsMouseUp: (NSEvent*) event
{
	const NSPoint point = [_recentsView convertPoint: [event locationInWindow] fromView: nil];

	for ( NSUInteger i = 0; i < [_recents count]; i++ )
	{
		if ( !NSPointInRect( point, [self rectForRecentAtIndex: i] ) )
			continue;

		//the forget button sits inside the row, so it is tested first
		if ( NSPointInRect( point, [self forgetButtonRectForRecentAtIndex: i] ) )
		{
			[[DIXRecentScans sharedList] removeScanForURL: [[_recents objectAtIndex: i] url]];
			return;
		}

		[self openURL: [[_recents objectAtIndex: i] url]];
		return;
	}
}

- (void) recentsMouseMoved: (NSEvent*) event
{
	const NSPoint point = [_recentsView convertPoint: [event locationInWindow] fromView: nil];

	for ( NSUInteger i = 0; i < [_recents count]; i++ )
	{
		if ( NSPointInRect( point, [self rectForRecentAtIndex: i] ) )
		{
			[self setHoveredRow: -1];
			[self setHoveredRecent: (NSInteger) i];
			return;
		}
	}

	[self setHoveredRecent: -1];
}

- (void) recentsMouseExited
{
	[self setHoveredRecent: -1];
}

//Deferred to the next turn of the run loop, the way the Drives panel opened
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
			[self setHoveredRecent: -1];
			return;
		}
	}

	[self setHoveredRow: -1];
}

- (void) mouseExited: (NSEvent*) event
{
	[self setHoveredRow: -1];
	[self setHoveredRecent: -1];
}

- (void) setHoveredRecent: (NSInteger) row
{
	if ( row == _hoveredRecent )
		return;

	_hoveredRecent = row;
	[_recentsView setNeedsDisplay: YES];
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
