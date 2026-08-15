//
//  NSAlert-Extensions.m
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

#import "NSAlert-Extensions.h"

@implementation NSAlert(Extensions)

+ (void) showInformationalSheetWithMessage: (NSString*) message
							   explanation: (NSString*) explanation
								 forWindow: (NSWindow*) window
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert setAlertStyle: NSAlertStyleInformational];
	[alert setMessageText: message];

	if ( [explanation length] > 0 )
		[alert setInformativeText: explanation];

	//NSAlert supplies an OK button by default, which is all these ever offered

	if ( window != nil )
		[alert beginSheetModalForWindow: window completionHandler: nil];
	else
		[alert runModal];
}

@end
