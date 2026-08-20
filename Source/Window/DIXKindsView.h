//
//  DIXKindsView.h
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

@class FileSystemDoc;

//The FILE KINDS section of the sidebar: a colour chip, the kind's name, its
//total size and a 3 pt share bar, largest first and no column headers.
//
//It replaces the cell-based NSTableView in TreeMap.nib, its two
//NSArrayControllers and the column that drew a cushion-shaded swatch per row.
//The chip is the same colour the treemap gives that kind, which is what makes
//this a legend rather than a second table of numbers.
//
//It is also where the kind filter finally gets a control. The document has had
//-setKindFilter: since the first commit on this branch with nothing to drive it:
//clicking a row filters the map to that kind, clicking it again clears.
@interface DIXKindsView : NSView

//Reads the kind statistics and follows the document's changes; pass nil to
//detach. The view keeps no strong reference - it is a subview of the window the
//document owns, so a strong one would be a cycle through the responder chain.
- (void) setDocument: (FileSystemDoc*) document;

@end
