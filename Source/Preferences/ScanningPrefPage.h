//
//  ScanningPrefPage.h
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

//How long scan snapshots are kept, where they are kept, and how much is there.
//The tab exists because the change window does: without a stored history there
//is nothing to compare a scan against, and this is where that is admitted to
//and controlled.
@interface ScanningPrefPage : PrefsPageBase

@end
