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
	TMVCushionRenderer *_cushionRenderer;
}

- (id) initWithDataSource: (id) dataSource
				 delegate: (id) delegate
			 renderedItem: (id) item
			  treeMapView: (TreeMapView*) view;

//re-reads this cell from the data source, dropping any cached child renderers
- (void) refreshWithItem: (id) item;

- (id) item;
- (unsigned long long) weight;
- (NSRect) rect;
- (BOOL) isLeaf;

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

//shades this subtree into the bitmap; coordinates are bitmap pixels
- (void) drawCushionInBitmap: (NSBitmapImageRep*) bitmap;

//deepest cell containing "point", or nil
- (TMVItem*) hitTest: (NSPoint) point;

@end
