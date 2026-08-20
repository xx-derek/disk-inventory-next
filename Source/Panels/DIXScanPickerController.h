//
//  DIXScanPickerController.h
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

//"Where did the space go?" - the window the application opens with, and what
//replaces the Drives panel.
//
//Built in code rather than in a nib, like the settings pages: it is a heading,
//a list of cards and a row of buttons, and a nib of that in four languages buys
//nothing over one file that can be read.
@interface DIXScanPickerController : NSObject

+ (DIXScanPickerController*) sharedController;

- (void) showPicker;
- (BOOL) pickerIsVisible;

- (IBAction) scanSelection: (id) sender;
- (IBAction) chooseFolder: (id) sender;

@end
