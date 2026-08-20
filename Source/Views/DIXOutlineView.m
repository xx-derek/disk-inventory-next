//
//  DIXOutlineView.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 29.03.05.
//
//  Copyright (C) 2005 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "DIXOutlineView.h"
#import "DIXTheme.h"

//The accent stripe down the leading edge of a selected row.
static const CGFloat kSelectionEdgeWidth = 3.0;

@implementation DIXOutlineView

#pragma mark --------the selected row-----------------

//The design marks the selected item with one accent treatment in both places it
//appears: the map outlines its cell, and the list tints its row and puts an
//accent edge down the leading side. Left alone this drew the system's
//emphasized blue, so the same file was blue here and red over there - which is
//exactly the connection the design is making.
//
//Kept in this view rather than in the controller that styles the columns:
//the outline is rebuilt in code later in this phase, and a highlight that lives
//on the class survives that where one bolted on from outside would not.
- (void) highlightSelectionInClipRect: (NSRect) clipRect
{
	//deliberately no super: it is what paints the blue
	NSIndexSet *selection = [self selectedRowIndexes];

	if ( [selection count] == 0 )
		return;

	const NSRange rows = [self rowsInRect: clipRect];

	[selection enumerateIndexesInRange: rows
							   options: 0
							usingBlock: ^( NSUInteger row, BOOL *stop )
	{
		const NSRect rowRect = [self rectOfRow: (NSInteger) row];

		[[DIXTheme accentTint] set];
		NSRectFill( rowRect );

		NSRect edge = rowRect;
		edge.size.width = kSelectionEdgeWidth;

		[[DIXTheme accent] set];
		NSRectFill( edge );
	}];
}

//The selected row is now a pale tint, not the emphasized system fill, so its
//cells have to keep their own colours. AppKit sets NSBackgroundStyleEmphasized
//on a cell in a selected row, which turns its text white - invisible on #fdf1ef.
- (NSCell*) preparedCellAtColumn: (NSInteger) col row: (NSInteger) row
{
	NSCell *cell = [super preparedCellAtColumn: col row: row];

	[cell setBackgroundStyle: NSBackgroundStyleNormal];

	return cell;
}

// return the selected item
- (id) selectedItem
{
    NSInteger row = [self selectedRow];
    return row >= 0 ? [self itemAtRow: row] : nil;
}

// ask the delegate which menu to show
-(NSMenu*) menuForEvent:(NSEvent*)evt
{
    NSPoint point = [self convertPoint: [evt locationInWindow] fromView: nil];
    
    NSInteger columnIndex = [self columnAtPoint:point];
    NSInteger rowIndex = [self rowAtPoint:point];
	
    if ( rowIndex >= 0 && [self numberOfSelectedRows] <= 1)
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection: NO];
	
    id delegate = [self delegate];
    
    if ( columnIndex >= 0 && rowIndex >= 0
         && [delegate respondsToSelector:@selector(outlineView:menuForTableColumn:item:)] )
    {
		//get context menu
        NSTableColumn *column = [[self tableColumns] objectAtIndex: columnIndex];
        NSMenu *contextMenu = [delegate outlineView:self menuForTableColumn: column item: [self itemAtRow: rowIndex]];
		
		//set first responder if we will show a context menu
		//(isn't necessary for proper function, but makes sense as the user opens the context menu)
		if ( contextMenu != nil
			 && [self acceptsFirstResponder]
			 && [[self window] firstResponder] != self )
		{
			[[self window] makeFirstResponder: self];
		}
		
		return contextMenu;
    }
    else
        return NULL;
}

//ask the delegate which drag operations are supported (if we are the dragging source)
//
//AppKit stopped calling -draggingSourceOperationMaskForLocal: in 10.7, so the
//override that used to live here was dead code and the mask fell back to the
//NSTableView default -- which is NSDragOperationNone for a drag leaving the
//application. That is why dragging a file to the Finder did nothing. This is the
//method AppKit actually calls; it forwards to the delegate exactly as before, so
//the delegates are unchanged.
- (NSDragOperation) draggingSession: (NSDraggingSession*) session
sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    const BOOL isLocal = ( context == NSDraggingContextWithinApplication );

    id delegate = [self delegate];

	//forward to our delegate, if possible
	if ( [delegate  respondsToSelector:@selector(dragOperationMaskForLocalDestination:)] )
		return [delegate dragOperationMaskForLocalDestination: isLocal];
	else
		return [super draggingSession: session sourceOperationMaskForDraggingContext: context];
}

@end
