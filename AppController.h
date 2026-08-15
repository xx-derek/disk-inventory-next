//
//  AppController.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 17.02.2019.
//
//  Copyright (C) 2019 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

//Was an OAController, whose one job here was to be named by OFControllerClass in
//Info.plist so the OmniGroup bootstrap would instantiate it. Nothing does that
//now, and nothing in the nibs refers to this class either.
@interface AppController : NSObject
{
//    IBOutlet NSMenu* _zoomStackMenu;
//    IBOutlet NSPanel* _donationPanel;
}
/*
- (IBAction) showPreferencesPanel: (id) sender;
- (IBAction) gotoHomepage: (id) sender;
- (IBAction) closeDonationPanel: (id) sender;
*/
@end

NS_ASSUME_NONNULL_END
