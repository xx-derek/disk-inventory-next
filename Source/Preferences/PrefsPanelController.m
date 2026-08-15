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
#import "PrefsPageBase.h"
#import "PrefsPageRecord.h"
#import "Preferences.h"

//the strings table page titles are localized in
static NSString * const PrefsTitlesTable = @"Preferences";

@interface PrefsPanelController(Private)

+ (NSMutableDictionary*) _pageRecordsByIdentifier;
- (void) _ensureWindowBuilt;
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

	[window setTitle: NSLocalizedStringFromTable( @"Preferences", PrefsTitlesTable, @"preferences window title" )];
	[window setShowsToolbarButton: NO];
	[window setReleasedWhenClosed: NO];
	[window setFrameAutosaveName: @"PreferencesWindow"];

	NSArray *visibleRecords = [self _visiblePageRecords];

	//a single page needs no toolbar to switch between
	if ( [visibleRecords count] > 1 )
	{
		NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: @"PreferencesToolbar"];

		[toolbar setDelegate: self];
		[toolbar setAllowsUserCustomization: NO];
		[toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];

		[window setToolbar: toolbar];
	}

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

	NSRect contentRect = [window contentRectForFrameRect: [window frame]];
	const NSSize pageSize = [pageView frame].size;

	//grow downwards, so the title bar stays put
	contentRect.origin.y += NSHeight(contentRect) - pageSize.height;
	contentRect.size = pageSize;

	[window setFrame: [window frameRectForContentRect: contentRect]
			 display: YES
			 animate: [window isVisible]];

	[window setContentView: pageView];

	//hand the page its keyboard focus, and close the tab order back to the top
	NSView *firstResponder = [page initialFirstResponder];
	if ( firstResponder != nil )
	{
		[window setInitialFirstResponder: firstResponder];
		[window makeFirstResponder: firstResponder];

		[[page lastKeyView] setNextKeyView: firstResponder];
	}

	[[window toolbar] setSelectedItemIdentifier: [pageRecord identifier]];
	[window setTitle: [self _localizedTitleForRecord: pageRecord]];

	[[NSUserDefaults standardUserDefaults] setObject: [pageRecord identifier]
											  forKey: @"PreferencesSelection"];
}

- (IBAction) _selectPageFromToolbar: (id) sender
{
	[self setCurrentPageRecord: [[self class] pageRecordWithIdentifier: [sender itemIdentifier]]];
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

#pragma mark --------NSToolbarDelegate-----------------

- (NSArray<NSToolbarItemIdentifier>*) toolbarAllowedItemIdentifiers: (NSToolbar*) toolbar
{
	return [[self _visiblePageRecords] valueForKey: @"identifier"];
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarDefaultItemIdentifiers: (NSToolbar*) toolbar
{
	return [self toolbarAllowedItemIdentifiers: toolbar];
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarSelectableItemIdentifiers: (NSToolbar*) toolbar
{
	return [self toolbarAllowedItemIdentifiers: toolbar];
}

- (NSToolbarItem*) toolbar: (NSToolbar*) toolbar
	 itemForItemIdentifier: (NSToolbarItemIdentifier) identifier
 willBeInsertedIntoToolbar: (BOOL) willBeInserted
{
	PrefsPageRecord *record = [[self class] pageRecordWithIdentifier: identifier];
	if ( record == nil )
		return nil;

	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: identifier];

	NSString *title = [self _localizedTitleForRecord: record];

	[item setLabel: title];
	[item setPaletteLabel: title];

	if ( [record iconName] != nil )
		[item setImage: [NSImage imageNamed: [record iconName]]];

	[item setTarget: self];
	[item setAction: @selector(_selectPageFromToolbar:)];

	return item;
}

@end
