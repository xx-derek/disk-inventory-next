//
//  DonationPanelController.h
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

//The panel shown once at first launch, until "Don't show again" is ticked.
//
//It asks for two different things and must not blur them: support for this
//fork, which goes to a crypto address, and support for Tjark Derlien, who wrote
//most of the code and whose website takes donations that do not reach the fork.
//The inherited panel solicited under this app's name and sent the money to him
//without saying so, which was true of neither party.
//
//Built in code rather than from the four localized nibs it replaces, because
//the address and its QR code have to come from one constant. A QR that
//disagreed with the address printed beside it would send someone's money
//somewhere neither of us chose.

@interface DonationPanelController : NSObject
{
	NSPanel *_panel;
	NSTextField *_headlineField;
	NSTextField *_addressField;
	NSButton *_copyButton;

	//once per run, however many times space is freed
	BOOL _shownThisSession;
}

+ (DonationPanelController*) sharedController;

//the EVM address the QR encodes; the same string is shown and copied
+ (NSString*) donationAddress;

//shows the panel unless the user has asked not to see it again
//Shown once, after a session in which space was actually reclaimed - not at
//launch. Asking for support the moment the application opens asks before it has
//done anything; asking after it has just freed something asks about that.
//
//"bytes" is what was freed, which the panel says out loud.
- (void) showPanelAfterReclaiming: (unsigned long long) bytes;

- (IBAction) copyAddress: (id) sender;
- (IBAction) visitOriginalAuthorSite: (id) sender;
- (IBAction) closePanel: (id) sender;

@end
