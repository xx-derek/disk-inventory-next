//
//  NSAlert-Extensions.h
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

@interface NSAlert(Extensions)

//Replaces NSBeginInformationalAlertSheet, deprecated in 10.10, which this app
//used in half a dozen places to say something and offer only "OK". Runs the
//alert as a sheet on "window", or application-modal if there is no window.
+ (void) showInformationalSheetWithMessage: (NSString*) message
							   explanation: (NSString*) explanation
								 forWindow: (NSWindow*) window;

@end
