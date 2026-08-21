//
//  PrivacyPrefPage.h
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
#import "PrefsPageBase.h"

//What the application can read, and what it says when it cannot. The one tab
//whose top row is not a setting but a fact about the system - Full Disk Access
//is granted in System Settings and only reported here.
@interface PrivacyPrefPage : PrefsPageBase

@end
