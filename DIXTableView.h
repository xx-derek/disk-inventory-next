//
//  DIXTableView.h
//  Disk Inventory Next
//
// DIXTableView derives from NSOutlineView and add some commonly used functionality
// (e.g. context menu support, drag&drop support)
//
//  Created by Tjark Derlien on 31.03.05.
//
//  Copyright (C) 2005 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import <Cocoa/Cocoa.h>

@interface DIXTableView : NSTableView {

}

@end

@interface NSObject(DIXTableViewDelegate)
- (NSMenu*) tableView: (NSTableView *) tableView menuForTableColumn: (NSTableColumn*) column row: (NSInteger) row;
	//delegate will be asked what menu to show (if not implemented by delegate [self menu] is used)

- (NSDragOperation) dragOperationMaskForLocalDestination:(BOOL)isLocal;
	//ask the delegate which drag operations are supported (if TableView is the dragging source)
	//
	//This used to be spelled -draggingSourceOperationMaskForLocal:, which came
	//from NSDraggingSource and so did not need declaring here. That method was
	//deprecated in 10.7, so the name is now the app's own and has to be
	//declared.
@end
