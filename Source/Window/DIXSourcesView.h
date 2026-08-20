//
//  DIXSourcesView.h
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

//The SOURCES section at the top of the sidebar: what can be scanned, and how
//full it is. A mounted volume per row - name, free space, a 4 pt usage bar -
//then Choose Folder….
//
//It replaces reaching for a floating Drives panel through a menu. The panel
//still exists and still opens volumes; this puts the same list where it is
//looked at, next to the map of whichever one is open. Both read
//DIXVolumeList, so they cannot disagree.
@interface DIXSourcesView : NSView

//What the view needs to show its rows without scrolling. The volume list is
//short and does not change while anyone is reading it, so the sidebar gives this
//section exactly its height and lets FILE KINDS have the rest.
- (CGFloat) fittingHeight;

//Marks the row for the document's own root, so the sidebar says which of the
//volumes is the one on screen. Pass nil for a scan that is not a volume.
- (void) setCurrentVolumeURL: (NSURL*) url;

//What this window actually scanned. Marks the matching row among the recent
//folders, the way -setCurrentVolumeURL: marks one among the volumes; a scan of
//a whole volume matches up there instead and nothing here.
- (void) setCurrentRootURL: (NSURL*) url;

@end
