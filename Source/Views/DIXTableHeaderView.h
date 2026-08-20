//
//  DIXTableHeaderView.h
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

//The file list's column header, as the design draws it: a flat 28pt band, one
//0.5pt rule along the bottom, and nothing else. AppKit's own header draws a
//bezel, a gradient and a separator between every column, none of which appear
//anywhere in the design.
//
//The cell goes with the view. NSTableHeaderCell draws its own background before
//its text, so restyling the view alone leaves the system bezel sitting inside
//the flat band.
@interface DIXTableHeaderView : NSTableHeaderView
+ (CGFloat) preferredHeight;
@end

@interface DIXTableHeaderCell : NSTableHeaderCell
@end
