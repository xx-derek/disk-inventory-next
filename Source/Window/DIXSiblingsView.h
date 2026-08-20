//
//  DIXSiblingsView.h
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
@class FSItem;

//The bottom half of the inspector: everything else of the selection's kind,
//with a tick box per row, and a reclaim bar that appears once anything is
//ticked.
//
//It answers the question the rest of the window cannot. The map and the list
//both say where the space is; this says "and here is the rest of what is like
//it" - the other twelve disk images, the other four hundred movies - which is
//how a clear-out actually gets done. The basket behind it has existed since the
//first commit on this branch with nothing to fill it.
@interface DIXSiblingsView : NSView

//The selection. Everything of the same kind *except* this item is listed,
//largest first; pass nil to empty the section.
- (void) setDocument: (FileSystemDoc*) document item: (FSItem*) item;

//Sent when Move to Trash is pressed. The view does not empty the basket itself:
//trashing is the window controller's, along with its confirmation and its poof
//effect, and the basket is only cleared once that has actually happened.
- (void) setTrashTarget: (id) target action: (SEL) action;

//What the section needs, so the inspector can give it exactly that and no more.
- (CGFloat) fittingHeight;

@end
