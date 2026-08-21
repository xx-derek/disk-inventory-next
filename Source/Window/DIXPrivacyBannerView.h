//
//  DIXPrivacyBannerView.h
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

//"3 folders were skipped" - what the total in front of you is missing, said at
//the moment the total is in front of you.
//
//This replaces a modal alert shown *before* the scan, which asked people to
//agree to something they had not seen yet. The alert still exists behind the
//"Warn before scanning them" setting, because it is what explains the macOS
//prompt the first time it appears; this is the other half, and it is the half
//that makes the number honest.
@interface DIXPrivacyBannerView : NSView

//How tall it needs to be at "width" points across, for whatever it was last
//given. Measured rather than estimated: the body wraps, and how many lines it
//wraps to depends on the folder names in it.
- (CGFloat) preferredHeightForWidth: (CGFloat) width;

//The folders that were asked for and could not be read, and the total they are
//missing from.
- (void) setSkippedFolders: (NSArray<NSURL*>*) folders
				totalShown: (NSString*) totalShown;

- (void) setTarget: (id) target
	  settingsAction: (SEL) settingsAction
	     scanAction: (SEL) scanAction
	  dismissAction: (SEL) dismissAction;

@end
