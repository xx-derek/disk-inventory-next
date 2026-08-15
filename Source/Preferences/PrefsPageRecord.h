//
//  PrefsPageRecord.h
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

#import <Cocoa/Cocoa.h>

//One page of the preferences window, as described in Info.plist under
//Registrations. The record is only the description; the page itself is not
//instantiated until the user first switches to it.
//
//(Previously OmniAppKit's OAPreferenceClientRecord.)

@interface PrefsPageRecord : NSObject
{
	NSString *_identifier;
	NSString *_className;
	NSString *_title;
	NSString *_symbolName;
	NSString *_nibName;
	NSString *_category;
	NSNumber *_ordering;
	NSArray *_defaultsArray;
	NSDictionary *_defaultsDictionary;
	BOOL _hidden;
}

- (id) initWithIdentifier: (NSString*) identifier description: (NSDictionary*) description;

@property (readonly, copy) NSString *identifier;

//the PrefsPageBase subclass that runs the page
@property (readonly, copy) NSString *className;

@property (readonly, copy) NSString *title;
@property (readonly, copy) NSString *symbolName;
@property (readonly, copy) NSString *nibName;
@property (readonly, copy) NSString *category;

//sort order in the preferences window's toolbar
@property (readonly, retain) NSNumber *ordering;

//the defaults keys this page presents, which is what "Restore Defaults" acts on
@property (readonly, retain) NSArray *defaultsArray;
@property (readonly, retain) NSDictionary *defaultsDictionary;

//hidden pages are still registered, but are not offered in the toolbar
@property (readonly) BOOL hidden;

@end
