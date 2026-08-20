//
//  TMVItem.h
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

#import <Foundation/Foundation.h>
#import "TMVCushionRenderer.h"

@class TreeMapView;

//How a cell is painted. Almost every cell is a cushion; the exceptions are the
//synthetic ones - free space and space used outside the scanned folder - which
//are drawn deliberately plain so they read as "not a file kind" against a
//palette that is entirely coloured.
typedef NS_ENUM( NSInteger, TMVCellStyle )
{
	TMVCellStyleCushion = 0,	//shaded, the normal case
	TMVCellStyleFlat,			//one solid colour, no shading
	TMVCellStyleOutlined,		//pale fill with a dashed outline: an empty cell
	TMVCellStyleRemainder,		//hatched: many items too small to draw separately
};

//Holds the display state of one cell in the treemap: where it ended up, how it
//is shaded, and the data item it stands for. The renderer tree mirrors the data
//source's tree, but only as deep as there is room to draw.

@interface TMVItem : NSObject
{
	//All three point back at objects that outlive the renderer tree: the view
	//owns the cells, so strong references here would be cycles. Unretained
	//rather than weak because a big treemap holds tens of thousands of cells.
	__unsafe_unretained id _dataSource;
	__unsafe_unretained id _delegate;
	id _item;
	__unsafe_unretained TreeMapView *_view;
	NSRect _rect;
	NSMutableArray *_childRenderers;
	//-isLeaf's answer, or <0 before it has been asked - see -isLeaf
	int8_t _isLeafCache;

	//What was actually laid out: the children above, with any run too small to
	//draw replaced by a single remainder cell. Recomputed every layout.
	NSArray *_drawnChildren;
	TMVCushionRenderer *_cushionRenderer;

	//Distance from the root, which is 0. The view uses it to tell the top-level
	//groups apart from everything nested inside them.
	NSInteger _depth;

	TMVCellStyle _cellStyle;
	NSColor *_outlineColor;
	NSColor *_labelColor;

	//The second line of a two-line label, and the hint under it. Nil means the
	//whole label is one tone, which is every cell except a remainder.
	NSColor *_detailLabelColor;

	//A remainder cell stands for a run of children too small to draw. It has no
	//data item of its own, so it carries its weight explicitly rather than
	//asking the data source, and remembers what it replaced.
	BOOL _isRemainder;
	unsigned long long _remainderWeight;
	NSArray *_mergedItems;

	//How many things those replaced children stand for, which is not how many of
	//them there are: one of them can be a whole folder. Summed once, when the
	//remainder is built, because the data source may have to walk a subtree to
	//answer and this is read on every draw.
	NSUInteger _mergedItemCount;
}

- (id) initWithDataSource: (id) dataSource
				 delegate: (id) delegate
			 renderedItem: (id) item
			  treeMapView: (TreeMapView*) view
					depth: (NSInteger) depth;

//re-reads this cell from the data source, dropping any cached child renderers
- (void) refreshWithItem: (id) item;

- (id) item;
- (unsigned long long) weight;
- (NSRect) rect;
- (BOOL) isLeaf;
- (NSInteger) depth;

- (NSUInteger) childCount;
- (TMVItem*) childAtIndex: (NSUInteger) index;
- (NSEnumerator*) childEnumerator;

//lays the receiver and its whole subtree out inside "rect", using the
//squarified treemap algorithm described in
//
//    Mark Bruls, Kees Huizing and Jarke J. van Wijk, "Squarified Treemaps",
//    Proc. Joint Eurographics and IEEE TCVG Symposium on Visualization, 2000.
- (void) calcLayout: (NSRect) rect;

- (void) setCushionColor: (NSColor*) color;

//The colour the cell was given, whatever its style. Cushion cells are shaded
//from it; flat and outlined cells are filled with it as it stands.
- (NSColor*) fillColor;

//Set from the delegate's -treeMapView:willDisplayItem:withRenderer:, alongside
//the colour. A cell that is not a cushion is skipped by the bitmap pass and
//painted by the view instead - a dashed outline is not something a height
//field can express.
- (TMVCellStyle) cellStyle;
- (void) setCellStyle: (TMVCellStyle) style;

//the dash colour for TMVCellStyleOutlined; ignored by the other styles
- (NSColor*) outlineColor;

//The colour of this cell's label, when the usual dark ink will not do. Nil for
//an ordinary cell: the cushions stay light in both appearances, so one ink
//serves them all. The two synthetic cells are the exception - free space is the
//darkest thing on a dark map - and dark ink on them is invisible.
- (NSColor*) labelColor;
- (void) setLabelColor: (NSColor*) color;

//The tone for the second line of a stacked label and for the hint below it.
//Nil - every cell but a remainder - means the label is one tone throughout.
- (NSColor*) detailLabelColor;
- (void) setDetailLabelColor: (NSColor*) color;

- (void) setOutlineColor: (NSColor*) color;

//shades this subtree into the bitmap; coordinates are bitmap pixels
- (void) drawCushionInBitmap: (NSBitmapImageRep*) bitmap;

//deepest cell containing "point", or nil
- (TMVItem*) hitTest: (NSPoint) point;

#pragma mark --------remainder cells-----------------

//YES for the synthetic cell that stands in for a run of children too small to
//be worth their own rectangle.
- (BOOL) isRemainder;

//The data items it replaced, largest first. Empty for every other cell.
- (NSArray*) mergedItems;

//How many things the cell stands for. Not -mergedItems.count: one merged item
//can be a folder that was packed in whole, and then it stands for everything
//inside it. The data source says how many through
//-treeMapView:itemCountByItem:, and answers 1 each if it does not implement it.
- (NSUInteger) mergedItemCount;

//Builds one. "weight" must be the sum of the merged items' weights - that is
//what keeps a cell's area proportional to what it represents, which is the
//whole claim a treemap makes.
- (id) initAsRemainderWithItems: (NSArray*) items
						 weight: (unsigned long long) weight
					  dataSource: (id) dataSource
					   delegate: (id) delegate
					treeMapView: (TreeMapView*) view
						  depth: (NSInteger) depth;

@end
