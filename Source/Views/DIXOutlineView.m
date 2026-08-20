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
//
//And it marks the cell highlighted, which makes the cell fill its own frame
//with the emphasized blue - a blue block over each column's content, inside a
//row already tinted by the method above. It only shows while the list has the
//keyboard focus, which is why it does not appear in a screenshot taken of a
//window whose focus is elsewhere.
//
//Not -setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone, which
//looks like the tidier answer and is not: with that set AppKit stops calling
//-highlightSelectionInClipRect: at all, so the tint and the accent edge go with
//the blue and a selected row becomes invisible. Verified both ways in a probe.
- (NSCell*) preparedCellAtColumn: (NSInteger) col row: (NSInteger) row
{
	NSCell *cell = [super preparedCellAtColumn: col row: row];

	[cell setBackgroundStyle: NSBackgroundStyleNormal];
	[cell setHighlighted: NO];

	//The design's selected row carries its name in bold - the one weight change
	//in the list, and the thing that says "this row" once the emphasized fill
	//is gone. Only the name: the size and the share stay as they are, so the
	//columns of figures keep reading as columns.
	//
	//The size comes from the cell rather than from a constant, because the
	//small-font preference changes it; the weight is put back on every row, so
	//the shared data cell cannot be left bold behind a moving selection.
	if ( col >= 0 && col < (NSInteger) [[self tableColumns] count]
		 && [[self tableColumns] objectAtIndex: col] == [self outlineTableColumn] )
	{
		NSFont *font = [cell font];
		const CGFloat size = font != nil ? [font pointSize] : [NSFont systemFontSize];

		[cell setFont: [NSFont systemFontOfSize: size
										 weight: [self isRowSelected: row]
												 ? NSFontWeightBold : NSFontWeightRegular]];
	}

	return cell;
}

//A row is 26pt and a line of 12pt text is not, and NSTextFieldCell draws its
//text at the top of whatever rect it is handed - so every row's text sat about
//5pt above the middle of its own tint. Centring the *rect* rather than the text
//puts the names, the figures and the kind chips right in one place: the chip is
//already centred in the frame it is given, and the cells draw from the top of
//theirs.
- (NSRect) frameOfCellAtColumn: (NSInteger) column row: (NSInteger) row
{
	NSRect frame = [super frameOfCellAtColumn: column row: row];

	if ( column < 0 || column >= (NSInteger) [[self tableColumns] count] )
		return frame;

	NSCell *cell = [[[self tableColumns] objectAtIndex: column] dataCell];
	const CGFloat contentHeight = ceil( [cell cellSize].height );

	if ( contentHeight <= 0.0 || contentHeight >= NSHeight( frame ) )
		return frame;

	frame.origin.y += floor( ( NSHeight( frame ) - contentHeight ) / 2.0 );
	frame.size.height = contentHeight;

	return frame;
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
