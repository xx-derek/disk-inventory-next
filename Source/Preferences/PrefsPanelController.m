//
//  PrefsPanelController.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 28.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "PrefsPanelController.h"
#import "NSImage-Extensions.h"
#import "PrefsPageBase.h"
#import "PrefsPageRecord.h"
#import "Preferences.h"
#import "DIXTheme.h"

//the strings table page titles are localized in
static NSString * const PrefsTitlesTable = @"Preferences";

//The design's own numbers for this window.
static const CGFloat kWindowWidth   = 560.0;
static const CGFloat kRailWidth     = 168.0;
static const CGFloat kRailInset     =  10.0;
static const CGFloat kRailTopInset  =  12.0;
static const CGFloat kRailRowHeight =  28.0;
static const CGFloat kPagePaddingX  =  22.0;
static const CGFloat kPagePaddingY  =  20.0;

//================ the rail ===========================================================

//The rail's own fill, drawn rather than left to the window: the design gives it
//the sidebar tone against the pane's surface, and the two must not be the same.
@interface DIXSettingsRailView : NSView
@end

@implementation DIXSettingsRailView

- (void) drawRect: (NSRect) dirtyRect
{
	[[DIXTheme sidebar] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );
}

@end

//One tab. Not an NSButton: the design's row is a 7pt rounded fill behind 13pt
//medium text with no bezel of any kind, and every button bezel AppKit offers
//draws something.
@interface DIXSettingsRailRow : NSControl
{
	NSString *_title;
	NSString *_rowIdentifier;
	BOOL _selected;
}
- (void) setTitle: (NSString*) title;
- (void) setIdentifier: (NSString*) identifier;
- (NSString*) identifier;
- (void) setSelected: (BOOL) selected;
@end

@implementation DIXSettingsRailRow

- (void) setTitle: (NSString*) title
{
	_title = [title copy];

	//Three separate things, and each was needed. -setAccessibilityElement: makes
	//it an element at all - an NSControl with no cell is not one by default, so
	//the rail was missing from the tree entirely. The setters rather than
	//overrides, because AppKit reads a control's attributes through them. And
	//-setAccessibilityTitle:, not -setAccessibilityLabel:: the label is a
	//description, the title is the name, and only the title is what a screen
	//reader announces for a control.
	[self setAccessibilityElement: YES];
	[self setAccessibilityTitle: title];
	[self setAccessibilityRole: NSAccessibilityRadioButtonRole];

	[self setNeedsDisplay: YES];
}

- (void) setIdentifier: (NSString*) identifier   { _rowIdentifier = [identifier copy]; }
- (NSString*) identifier                          { return _rowIdentifier; }

- (void) setSelected: (BOOL) selected
{
	if ( _selected == selected )
		return;

	_selected = selected;
	[self setAccessibilityValue: @(selected)];
	[self setNeedsDisplay: YES];
}

- (void) mouseDown: (NSEvent*) event
{
	[self sendAction: [self action] to: [self target]];
}

//What VoiceOver and every other assistive client send. A custom NSControl gets
//no press behaviour for free - AppKit's own comes from the cell this has none
//of - so without this the rail could be read and not used.
- (BOOL) accessibilityPerformPress
{
	[self sendAction: [self action] to: [self target]];

	return YES;
}

- (void) drawRect: (NSRect) dirtyRect
{
	const NSRect bounds = [self bounds];

	if ( _selected )
	{
		[[DIXTheme selectedRowFill] set];
		[[NSBezierPath bezierPathWithRoundedRect: bounds
										 xRadius: [DIXTheme rowCornerRadius]
										 yRadius: [DIXTheme rowCornerRadius]] fill];
	}

	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize: 13.0
											   weight: _selected ? NSFontWeightMedium : NSFontWeightRegular],
		NSForegroundColorAttributeName: [DIXTheme ink] };

	const NSSize size = [_title sizeWithAttributes: attributes];

	[_title drawAtPoint: NSMakePoint( NSMinX( bounds ) + 10.0,
									  NSMidY( bounds ) - size.height / 2.0 )
		 withAttributes: attributes];
}

@end

@interface PrefsPanelController(Private)

+ (NSMutableDictionary*) _pageRecordsByIdentifier;
- (void) _ensureWindowBuilt;
+ (NSString*) _settingsWindowTitle;
- (NSView*) _contentViewWrappingPage: (NSView*) pageView;
- (PrefsPageBase*) _pageForRecord: (PrefsPageRecord*) pageRecord;
- (NSArray*) _visiblePageRecords;
- (NSString*) _localizedTitleForRecord: (PrefsPageRecord*) pageRecord;
- (void) _restoreDefaultsSheetDidEnd: (NSWindow*) sheet
						  returnCode: (NSInteger) returnCode
						 contextInfo: (void*) contextInfo;

@end

@implementation PrefsPanelController

+ (PrefsPanelController*) sharedPreferenceController
{
	static PrefsPanelController *sharedPreferenceController = nil;

	if (sharedPreferenceController == nil)
		sharedPreferenceController = [[self alloc] init];

	return sharedPreferenceController;
}

#pragma mark --------the registry-----------------

+ (NSMutableDictionary*) _pageRecordsByIdentifier
{
	static NSMutableDictionary *records = nil;
	if ( records != nil )
		return records;

	records = [[NSMutableDictionary alloc] init];

	//The page list lives in Info.plist beside the factory defaults, keyed by
	//this class's own name.
	NSDictionary *registrations = [[[NSBundle mainBundle] infoDictionary] objectForKey: AppRegistrationsKey];
	NSDictionary *pageDescriptions = [registrations objectForKey: NSStringFromClass( self )];

	for ( NSString *className in pageDescriptions )
		[self registerPageName: className description: [pageDescriptions objectForKey: className]];

	return records;
}

+ (void) registerPageName: (NSString*) pageName description: (NSDictionary*) description
{
	//A page can be registered for a feature that is no longer built, so a
	//missing class is expected rather than an error.
	if ( NSClassFromString( pageName ) == Nil )
		return;

	PrefsPageRecord *record = [[PrefsPageRecord alloc] initWithIdentifier: pageName description: description];

	[[self _pageRecordsByIdentifier] setObject: record forKey: [record identifier]];

}

+ (NSArray*) allPageRecords
{
	return [[[self _pageRecordsByIdentifier] allValues] sortedArrayUsingComparator:
		^NSComparisonResult( PrefsPageRecord *left, PrefsPageRecord *right )
	{
		NSComparisonResult byOrdering = [[left ordering] compare: [right ordering]];

		//a stable order for pages that did not ask for one
		return ( byOrdering != NSOrderedSame )
			   ? byOrdering
			   : [[left identifier] caseInsensitiveCompare: [right identifier]];
	}];
}

+ (PrefsPageRecord*) pageRecordWithIdentifier: (NSString*) identifier
{
	return [[self _pageRecordsByIdentifier] objectForKey: identifier];
}

#pragma mark --------lifetime-----------------

- (id) init
{
	self = [super initWithWindow: nil];
	if ( self == nil )
		return nil;

	_pagesByIdentifier = [[NSMutableDictionary alloc] init];

	return self;
}


- (NSArray*) _visiblePageRecords
{
	NSMutableArray *visible = [NSMutableArray array];

	for ( PrefsPageRecord *record in [[self class] allPageRecords] )
	{
		if ( ![record hidden] )
			[visible addObject: record];
	}

	return visible;
}

- (NSString*) _localizedTitleForRecord: (PrefsPageRecord*) pageRecord
{
	NSString *title = [pageRecord title];
	if ( title == nil )
		return [pageRecord identifier];

	return NSLocalizedStringFromTable( title, PrefsTitlesTable, @"preference page title" );
}

#pragma mark --------the window-----------------

//NSWindowController only calls -loadWindow for a controller that was given a
//nib to load. This one is created with -init, which counts as already loaded, so
//the window is built on first use instead.
- (NSWindow*) window
{
	[self _ensureWindowBuilt];

	return [super window];
}

- (void) _ensureWindowBuilt
{
	if ( _windowBuilt )
		return;

	//set before anything below can ask for the window again
	_windowBuilt = YES;

	//built in code rather than a nib, since the pages themselves supply all the
	//content and the frame around them is the same either way
	NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect( 0.0, 0.0, 400.0, 200.0 )
												   styleMask: NSWindowStyleMaskTitled
															  | NSWindowStyleMaskClosable
															  | NSWindowStyleMaskMiniaturizable
													 backing: NSBackingStoreBuffered
													   defer: YES];

	[window setTitle: [[self class] _settingsWindowTitle]];
	[window setShowsToolbarButton: NO];
	[window setReleasedWhenClosed: NO];
	[window setTitlebarAppearsTransparent: YES];
	[window setBackgroundColor: [DIXTheme surface]];

	//Deliberately not autosaved. The window's height follows the tab, so a
	//remembered frame would open the next tab at the last one's height and then
	//jump - and there is nothing else about the position worth keeping, since
	//it centres on the screen anyway.

	NSArray *visibleRecords = [self _visiblePageRecords];

	//The design's rail rather than a toolbar: four tabs with a heading each,
	//which is how current macOS settings windows are laid out. A toolbar on
	//macOS 26 would also draw every item in a glass capsule.
	if ( [visibleRecords count] > 1 )
		[self _buildRailForRecords: visibleRecords];

	[self setWindow: window];

	//opens on the page the user was last looking at, or the first one
	NSString *lastIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey: @"PreferencesSelection"];

	PrefsPageRecord *initialRecord = ( lastIdentifier != nil )
									 ? [[self class] pageRecordWithIdentifier: lastIdentifier]
									 : nil;

	if ( initialRecord == nil || [initialRecord hidden] )
		initialRecord = [visibleRecords firstObject];

	[self setCurrentPageRecord: initialRecord];
}

- (IBAction) showPreferencesPanel: (id) sender
{
	[self showWindow: sender];
	[[self window] makeKeyAndOrderFront: sender];
}

#pragma mark --------pages-----------------

- (PrefsPageBase*) currentPage
{
	return _currentPage;
}

- (PrefsPageBase*) _pageForRecord: (PrefsPageRecord*) pageRecord
{
	if ( pageRecord == nil )
		return nil;

	PrefsPageBase *page = [_pagesByIdentifier objectForKey: [pageRecord identifier]];
	if ( page != nil )
		return page;

	Class pageClass = NSClassFromString( [pageRecord className] );
	if ( pageClass == Nil )
		return nil;

	page = [[pageClass alloc] initWithPageRecord: pageRecord];

	//pages are built once and kept, so switching back is instant and any state
	//in the page's controls survives
	[_pagesByIdentifier setObject: page forKey: [pageRecord identifier]];

	return page;
}

- (void) setCurrentPageRecord: (PrefsPageRecord*) pageRecord
{
	if ( pageRecord == nil || pageRecord == _currentPageRecord )
		return;

	PrefsPageBase *page = [self _pageForRecord: pageRecord];
	NSView *pageView = [page controlBox];
	if ( pageView == nil )
		return;

	_currentPageRecord = pageRecord;

	_currentPage = page;

	NSWindow *window = [self window];

	//Swap in an empty view first: resizing the window with the outgoing page
	//still installed would stretch it on the way.
	[window setContentView: [[NSView alloc] initWithFrame: NSZeroRect]];

	NSView *content = [self _contentViewWrappingPage: pageView];

	NSRect contentRect = [window contentRectForFrameRect: [window frame]];
	const NSSize contentSize = [content frame].size;

	//grow downwards, so the title bar stays put
	contentRect.origin.y += NSHeight(contentRect) - contentSize.height;
	contentRect.size = contentSize;

	[window setFrame: [window frameRectForContentRect: contentRect]
			 display: YES
			 animate: [window isVisible]];

	//Centred the first time, and held by its title bar after that. The frame is
	//not autosaved - the height follows the tab, so a remembered one would open
	//the next tab at the last one's height and then jump.
	if ( ![window isVisible] )
		[window center];

	[window setContentView: content];

	//Close the tab order back to the top, but do not *take* focus. Focusing the
	//first control draws a focus ring on it the moment the window opens, which
	//the design has nowhere - and a settings pane is read before it is typed
	//into. Tab still walks the page from the top.
	NSView *firstResponder = [page initialFirstResponder];
	if ( firstResponder != nil )
		[[page lastKeyView] setNextKeyView: firstResponder];

	for ( DIXSettingsRailRow *row in _railRows )
		[row setSelected: [[row identifier] isEqualToString: [pageRecord identifier]]];

	//The design titles the window with the tab rather than with the word
	//"Settings", which is what current macOS settings windows do.
	[window setTitle: [self _localizedTitleForRecord: pageRecord]];

	[[NSUserDefaults standardUserDefaults] setObject: [pageRecord identifier]
											  forKey: @"PreferencesSelection"];
}

//macOS 13 renamed Preferences to Settings across the system. The deployment
//target is 11.0, where "Preferences" was still right, so this follows whichever
//system the user is actually on rather than picking one and being wrong on the
//other.
+ (NSString*) _settingsWindowTitle
{
	NSString *key = @"Preferences";

	if ( @available( macOS 13.0, * ) )
		key = @"Settings";

	return NSLocalizedStringFromTable( key, PrefsTitlesTable, @"settings window title" );
}

//The rail is built once and kept; only its selection changes as tabs are
//switched. Rows are drawn rather than bezelled - a 7pt rounded fill behind
//13pt medium text, which is not a shape any NSButton bezel offers.
- (void) _buildRailForRecords: (NSArray*) records
{
	_railView = [[DIXSettingsRailView alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, kRailWidth, 0.0 )];

	_railRows = [NSMutableArray array];

	for ( PrefsPageRecord *record in records )
	{
		DIXSettingsRailRow *row = [[DIXSettingsRailRow alloc] initWithFrame: NSZeroRect];

		[row setTitle: [self _localizedTitleForRecord: record]];
		[row setIdentifier: [record identifier]];
		[row setTarget: self];
		[row setAction: @selector(_selectPageFromRail:)];

		[_railView addSubview: row];
		[_railRows addObject: row];
	}
}

- (void) _layoutRailToHeight: (CGFloat) height
{
	[_railView setFrame: NSMakeRect( 0.0, 0.0, kRailWidth, height )];

	CGFloat y = height - kRailTopInset;

	for ( DIXSettingsRailRow *row in _railRows )
	{
		y -= kRailRowHeight;
		[row setFrame: NSMakeRect( kRailInset, y, kRailWidth - kRailInset * 2.0, kRailRowHeight )];
	}
}

//The rail beside the page, both full height, with the page inset by the pane's
//own padding. The window's height is whatever the taller of the two comes to.
- (NSView*) _contentViewWrappingPage: (NSView*) pageView
{
	const CGFloat railHeight = kRailTopInset
							   + kRailRowHeight * (CGFloat) [_railRows count]
							   + kRailTopInset;

	const CGFloat pageHeight = NSHeight( [pageView frame] ) + kPagePaddingY * 2.0;
	const CGFloat height = MAX( railHeight, pageHeight );

	NSView *content = [[NSView alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, kWindowWidth, height )];

	if ( _railView != nil )
	{
		[self _layoutRailToHeight: height];
		[content addSubview: _railView];
	}

	const CGFloat pageX = ( _railView != nil ? kRailWidth : 0.0 ) + kPagePaddingX;

	[pageView setFrameOrigin: NSMakePoint( pageX, height - kPagePaddingY - NSHeight( [pageView frame] ) )];

	[content addSubview: pageView];

	return content;
}

- (IBAction) _selectPageFromRail: (id) sender
{
	[self setCurrentPageRecord:
		[[self class] pageRecordWithIdentifier: [(DIXSettingsRailRow*) sender identifier]]];
}

#pragma mark --------restoring defaults-----------------

- (IBAction) restoreDefaults: (id) sender
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert setMessageText: NSLocalizedStringFromTable( @"Reset preferences to their original values?",
													   PrefsTitlesTable, @"" )];
	[alert setInformativeText: NSLocalizedStringFromTable( @"Any changes you have made will be lost.",
														   PrefsTitlesTable, @"" )];

	//first button is the default, which is what the sheet handler tests for
	[alert addButtonWithTitle: NSLocalizedStringFromTable( @"Reset", PrefsTitlesTable, @"" )];
	[alert addButtonWithTitle: NSLocalizedStringFromTable( @"Cancel", PrefsTitlesTable, @"" )];

	NSWindow *window = [self window];

	[alert beginSheetModalForWindow: window completionHandler: ^( NSModalResponse returnCode )
	{
		[self _restoreDefaultsSheetDidEnd: window returnCode: returnCode contextInfo: NULL];
	}];
}

//A non-NULL contextInfo means "wipe the whole defaults domain"; otherwise only
//the keys the pages actually present are reset.
- (void) _restoreDefaultsSheetDidEnd: (NSWindow*) sheet
						  returnCode: (NSInteger) returnCode
						 contextInfo: (void*) contextInfo
{
	//NSInteger, not int: the sheet's response is an NSModalResponse, and reading
	//only the low 32 bits of it would compare against garbage on 64-bit
	if (returnCode != NSAlertFirstButtonReturn)
		return;

	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

	if (contextInfo != NULL)
	{
		// warn & wipe the entire defaults domain
		NSString *domain = [[NSBundle mainBundle] bundleIdentifier];
		if ( domain != nil )
			[prefs removePersistentDomainForName: domain];

		[prefs synchronize];
	}
	else
	{
		// warn & wipe all prefs shown in all pages
		//(the preferences shown in each page must be declared properly in Info.plist)
		for ( PrefsPageRecord *aPageRecord in [[self class] allPageRecords] )
		{
			NSArray *preferenceKeys = [[aPageRecord defaultsDictionary] allKeys];
			preferenceKeys = [preferenceKeys arrayByAddingObjectsFromArray: [aPageRecord defaultsArray]];

			for ( NSString *aKey in preferenceKeys )
			{
				//removeObjectForKey: is not key-value observing compliant, so
				//make sure any bound control still hears about it
				[prefs willChangeValueForKey: aKey];
				[prefs removeObjectForKey: aKey];
				[prefs didChangeValueForKey: aKey];
			}
		}
	}

	[_currentPage valuesHaveChanged];
}

@end
