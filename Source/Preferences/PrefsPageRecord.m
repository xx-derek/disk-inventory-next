//
//  PrefsPageRecord.m
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

#import "PrefsPageRecord.h"

@implementation PrefsPageRecord

- (id) initWithIdentifier: (NSString*) identifier description: (NSDictionary*) description
{
	self = [super init];
	if ( self == nil )
		return nil;

	//the registration is keyed by class name, and the description may name a
	//different identifier for the toolbar item
	_className = [identifier copy];

	NSString *recordIdentifier = [description objectForKey: @"identifier"];
	_identifier = [( recordIdentifier != nil ? recordIdentifier : identifier ) copy];

	_title = [[description objectForKey: @"title"] copy];
	_symbolName = [[description objectForKey: @"symbol"] copy];
	_nibName = [[description objectForKey: @"nib"] copy];
	_category = [[description objectForKey: @"category"] copy];
	_ordering = [description objectForKey: @"ordering"];

	NSArray *defaultsArray = [description objectForKey: @"defaultsArray"];
	_defaultsArray = ( defaultsArray != nil ? defaultsArray : [NSArray array] );

	//Never nil: callers gather keys from both collections and concatenate them,
	//and an absent one would otherwise have to be special-cased at every site.
	NSDictionary *defaultsDictionary = [description objectForKey: @"defaultsDictionary"];
	_defaultsDictionary = ( defaultsDictionary != nil ? defaultsDictionary : [NSDictionary dictionary] );

	_hidden = [[description objectForKey: @"hidden"] boolValue];

	return self;
}


- (NSString*) identifier				{ return _identifier; }
- (NSString*) className					{ return _className; }
- (NSString*) title						{ return _title; }
- (NSString*) symbolName				{ return _symbolName; }
- (NSString*) nibName					{ return _nibName; }
- (NSString*) category					{ return _category; }
- (NSNumber*) ordering					{ return _ordering; }
- (NSArray*) defaultsArray				{ return _defaultsArray; }
- (NSDictionary*) defaultsDictionary	{ return _defaultsDictionary; }
- (BOOL) hidden							{ return _hidden; }

- (NSString*) description
{
	return [NSString stringWithFormat: @"<%@ %@ (%@)>",
			NSStringFromClass([self class]), _identifier, _className];
}

@end
