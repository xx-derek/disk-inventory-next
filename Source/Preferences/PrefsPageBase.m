//
//  PrefsPageBase.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 29.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "PrefsPageBase.h"
#import "PrefsPageRecord.h"
#import "PrefsPageLayout.h"
#import "PrefsPanelController.h"

@interface PrefsPageBase()
- (void) restoreDefaultsForKeys: (NSArray<NSString*>*) keys;
@end

//Equality that treats nil as a value in its own right. Plain -isEqual: cannot:
//sending it to nil answers NO, so two absent values would compare as different.
static BOOL ValuesDiffer( id valueA, id valueB )
{
	if ( valueA == valueB )
		return NO;

	if ( valueA == nil || valueB == nil )
		return YES;

	return ![valueA isEqual: valueB];
}

//the strings table the page text is localized in
static NSString * const PrefsTitlesTable = @"Preferences";

@implementation PrefsPageBase

//560 wide, a 168pt rail, and 22pt of padding either side of the pane - the
//design's numbers, arrived at here so that no page can disagree with the rail.
+ (CGFloat) contentWidth
{
	return 560.0 - 168.0 - 22.0 * 2.0;
}

- (id) initWithPageRecord: (PrefsPageRecord*) pageRecord
{
	self = [super init];
	if ( self == nil )
		return nil;

	_pageRecord = pageRecord;

	return self;
}


- (PrefsPageRecord*) pageRecord
{
	return _pageRecord;
}

- (NSString*) title
{
	return [_pageRecord title];
}

- (NSView*) buildControlBox
{
	return nil;
}

- (void) setLayout: (PrefsPageLayout*) layout
{
	_layout = layout;
}

- (NSView*) controlBox
{
	if ( controlBox != nil )
		return controlBox;

	//a page that builds itself never touches the nib machinery below
	controlBox = [self buildControlBox];
	if ( controlBox != nil )
	{
		initialFirstResponder = [_layout firstControl];
		lastKeyView = [_layout lastControl];
		return controlBox;
	}

	NSString *nibName = [_pageRecord nibName];
	if ( nibName == nil )
		return nil;

	NSArray *topLevelObjects = nil;

	if ( ![[NSBundle mainBundle] loadNibNamed: nibName owner: self topLevelObjects: &topLevelObjects] )
	{
		NSLog( @"preference page '%@' could not load its nib '%@'", [_pageRecord identifier], nibName );
		return nil;
	}

	//The nib's top-level objects come back autoreleased, and nothing else holds
	//the page's view, so the page has to keep them itself.
	_nibTopLevelObjects = topLevelObjects;

	if ( controlBox == nil )
		NSLog( @"preference page '%@' loaded '%@' but its controlBox outlet is not connected",
			   [_pageRecord identifier], nibName );

	return controlBox;
}

- (NSView*) initialFirstResponder
{
	//loading the nib is what connects it
	[self controlBox];

	return initialFirstResponder;
}

- (NSView*) lastKeyView
{
	[self controlBox];

	return lastKeyView;
}

#pragma mark --------defaults-----------------

//The preferences shown in each page are declared in Info.plist, under
//Registrations, and that list is what these work from.

- (void) addRestoreDefaultsSectionTo: (PrefsPageLayout*) layout help: (NSString*) help
{
	[layout beginSectionWithLabel: @"Defaults"];

	//Not destructive in the design's sense: it puts settings back, and every one
	//of them can be set again. The things that cannot be undone - deleting the
	//scan history - are the accent ones.
	[layout addButtonTitled: @"Restore defaults"
					   help: help
				buttonTitle: @"Restore…"
				destructive: NO
					 target: self
					 action: @selector(restoreThisPage:)];
}

- (IBAction) restoreThisPage: (id) sender
{
	//Option resets every page. The General tab says so; the others do not, since
	//one place to learn it is enough and four would be noise.
	const BOOL everyPage =
		( [NSEvent modifierFlags] & NSEventModifierFlagOption ) != 0;

	NSAlert *alert = [[NSAlert alloc] init];

	[alert setMessageText: NSLocalizedStringFromTable(
		everyPage ? @"Restore every tab to its factory settings?"
				  : @"Restore this tab to its factory settings?",
		PrefsTitlesTable, @"" )];

	[alert setInformativeText: NSLocalizedStringFromTable(
		@"Any changes you have made will be lost.", PrefsTitlesTable, @"" )];

	//first button is the default, which is what the handler tests for
	[alert addButtonWithTitle: NSLocalizedStringFromTable( @"Restore", PrefsTitlesTable, @"" )];
	[alert addButtonWithTitle: NSLocalizedStringFromTable( @"Cancel", PrefsTitlesTable, @"" )];

	NSWindow *window = [[self controlBox] window];

	void (^respond)( NSModalResponse ) = ^( NSModalResponse returnCode )
	{
		if ( returnCode != NSAlertFirstButtonReturn )
			return;

		if ( everyPage )
		{
			for ( PrefsPageRecord *record in [PrefsPanelController allPageRecords] )
				[self restoreDefaultsForKeys: [record defaultsArray]];
		}
		else
		{
			[self restoreDefaultsNoPrompt];
		}

		[self valuesHaveChanged];
	};

	if ( window != nil )
		[alert beginSheetModalForWindow: window completionHandler: respond];
	else
		respond( [alert runModal] );
}

- (void) restoreDefaultsForKeys: (NSArray<NSString*>*) keys
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	for ( NSString *key in keys )
	{
		//removeObjectForKey: is not key-value observing compliant, so bound
		//controls have to be told by hand
		[defaults willChangeValueForKey: key];
		[defaults removeObjectForKey: key];
		[defaults didChangeValueForKey: key];
	}
}

- (void) restoreDefaultsNoPrompt
{
	[self restoreDefaultsForKeys: [_pageRecord defaultsArray]];
}

- (BOOL) haveAnyDefaultsChanged
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *registeredDefaults = [defaults volatileDomainForName: NSRegistrationDomain];

	for ( NSString *key in [_pageRecord defaultsArray] )
	{
		if ( ValuesDiffer( [defaults objectForKey: key], [registeredDefaults objectForKey: key] ) )
			return YES;
	}

	return NO;
}

- (void) valuesHaveChanged
{
	//Nothing to do: the pages drive their controls through bindings to
	//NSUserDefaultsController, which picks the new values up on its own.
}

@end
