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

@implementation PrefsPageBase

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
//Registrations, and that list is what these two work from.

- (void) restoreDefaultsNoPrompt
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	for ( NSString *key in [_pageRecord defaultsArray] )
	{
		//removeObjectForKey: is not key-value observing compliant, so bound
		//controls have to be told by hand
		[defaults willChangeValueForKey: key];
		[defaults removeObjectForKey: key];
		[defaults didChangeValueForKey: key];
	}
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
