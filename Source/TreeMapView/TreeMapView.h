//
//  TreeMapView.h
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

//A treemap: every item in a tree becomes a rectangle whose area is proportional
//to its weight, nested inside its parent's rectangle. The view is driven by a
//data source and delegate in the same way as NSOutlineView, so a data source
//written for one reads much like the other.

#import <Cocoa/Cocoa.h>
#import "TMVItem.h"

//Opaque handle for one cell. Cells are transient: any reload invalidates every
//id handed out before it, so do not hold on to them across a -reloadData.
typedef TMVItem* TMVCellId;

@interface TreeMapView : NSView
{
	TMVItem *_rootItemRenderer;
	//not retained, as everywhere else in AppKit; weak so that a controller torn
	//down before the view leaves nil here rather than a dangling pointer
	IBOutlet __weak id delegate;
	IBOutlet __weak id dataSource;
	TMVItem *_selectedRenderer;
	TMVItem *_touchedRenderer;
	NSBitmapImageRep *_cachedContent;
	id _zoomer;

	//Precomputed geometry for everything drawn over the shaded bitmap. Built
	//once per layout and replayed, because working it out per frame cost seven
	//times what blitting the bitmap did.
	NSMutableArray *_overlayPlainCells;
	NSMutableArray *_overlayGutters;
	NSMutableArray *_overlayLabels;
	NSSize _overlayLayoutSize;
	BOOL _overlayValid;

	//What the current layout had to aggregate. Summed while the overlay is
	//built, because merging is a function of the laid-out rects: the same tree
	//in a bigger window merges less.
	NSUInteger _mergedItemCount;
	unsigned long long _mergedItemWeight;
	BOOL _layoutChangePostPending;
	BOOL _usesClassicCushions;
}

- (id) delegate;
- (void) setDelegate: (id) delegate;
- (id) dataSource;
- (void) setDataSource: (id) dataSource;

#pragma mark --------appearance-----------------

//Everything below is drawn over the shaded bitmap, in view coordinates, so
//none of it invalidates the cushion cache. The colours are properties rather
//than constants because this widget knows nothing about the application's
//palette - the controller supplies them.

//Gaps painted along the boundaries of the top-level groups, so the first level
//of structure reads at a glance. Zero switches them off.
//
//This is drawn on top rather than inset into the layout, and deliberately: a
//cell's area is proportional to its weight, and shrinking every rect by a
//fixed margin takes proportionally far more area from a long thin cell than
//from a square one. The gap is cosmetic; the geometry underneath stays exact.
@property (nonatomic, assign) CGFloat  gutterWidth;     //points, default 2
@property (nonatomic, strong) NSColor *gutterColor;

//A margin in points between the view's edge and the outermost cells, drawn in
//-gutterColor like the gaps between the cells themselves. 0 by default: it is a
//design decision, not something the widget assumes.
//
//It is part of the layout rather than something drawn on top, so the cells are
//laid out inside it and hit testing follows without any change - a point in the
//margin belongs to no cell, which is the truth.
@property (nonatomic) CGFloat contentInset;

//Names written into cells big enough to hold them. The strings come from the
//delegate; a cell is labelled only if the text fits with its margins.
@property (nonatomic, assign) BOOL     drawsCellLabels;
@property (nonatomic, strong) NSColor *cellLabelColor;

//The selected cell keeps its own colour and is marked by an inset outline, so
//that selecting something never misrepresents which kind it is.
@property (nonatomic, strong) NSColor *selectionColor;

//Which shading model the cells are drawn with. The classic cushion encodes
//nesting depth, the design's bevel encodes only where a cell begins and ends.
//The widget has no opinion on which; the application decides and sets it.
- (BOOL) usesClassicCushions;
- (void) setUsesClassicCushions: (BOOL) classic;

//throws away the rendered bitmap but keeps the layout
- (void) invalidateCanvasCache;

//re-reads everything from the data source
- (void) reloadData;

//Reloads, preceded by a zoom effect. "path" runs from a root to the item zoomed
//in or out of, as <root><child>...<item>. For zooming in the path is relative
//to the old root, because that is the tree the effect starts from; for zooming
//out it is relative to the new one, for the same reason.
- (void) reloadAndPerformZoomIntoItem: (NSArray*) path;
- (void) reloadAndPerformZoomOutofItem: (NSArray*) path;

//zoom effects are animated, so commands that would reload have to wait
- (BOOL) zoomingInProgress;

//hit test; "point" is in window coordinates unless "viewCoords" is YES
- (TMVCellId) cellIdByPoint: (NSPoint) point inViewCoords: (BOOL) viewCoords;

//the data item a cell stands for, as supplied by the data source
- (id) itemByCellId: (TMVCellId) cellId;

- (id) selectedItem;

//The cell the selection sits on, whether or not it stands for a data item.
- (TMVCellId) selectedCellId;

//The data item a cell belongs to: an ordinary cell's own item, and for a
//remainder - which stands for many items and is none of them - the item of the
//nearest enclosing cell that has one, which is the folder they were merged out
//of. That folder is what a controller can select, show and zoom into; the
//remainder itself is not anything the rest of the app can name.
- (id) enclosingItemByCellId: (TMVCellId) cellId;

- (void) selectItemByCellId: (TMVCellId) cellId;
- (void) selectItemByPathToItem: (NSArray*) path;

//cell rects, in view coordinates
- (NSRect) itemRectByCellId: (TMVCellId) cellId;
- (NSRect) itemRectByPathToItem: (NSArray*) path;

//How much of what is on screen is aggregated rather than drawn item by item:
//how many data items went into remainder cells, and their combined weight.
//Both zero when nothing was merged. They change with the window size and with
//the zoom, so they only describe the layout that produced them - read them when
//TreeMapViewLayoutChangedNotification says they are fresh.
- (NSUInteger) mergedItemCount;
- (unsigned long long) mergedItemWeight;

//Time the two expensive halves of drawing separately, at a fixed size so the
//figures mean the same thing on any display. Both leave the view's own layout
//and cached bitmap alone.
- (void) benchmarkLayoutCalculationWithImageSize: (NSSize) size count: (unsigned) count;
- (void) benchmarkRenderingWithImageSize: (NSSize) size count: (unsigned) count;

@end

#pragma mark --------data source-----------------

@interface NSObject(TreeMapViewDataSource)

//"item" is nil for the root of the tree
- (NSUInteger) treeMapView: (TreeMapView*) view numberOfChildrenOfItem: (id) item;
- (id) treeMapView: (TreeMapView*) view child: (NSUInteger) index ofItem: (id) item;
- (BOOL) treeMapView: (TreeMapView*) view isNode: (id) item;

//what the cell's area is proportional to
- (unsigned long long) treeMapView: (TreeMapView*) view weightByItem: (id) item;

@end

#pragma mark --------delegate-----------------

@interface NSObject(TreeMapViewDelegate)

//called before a cell is first drawn, to give it a color
- (void) treeMapView: (TreeMapView*) view willDisplayItem: (id) item withRenderer: (TMVItem*) renderer;

//The same, for the synthetic cell that stands in for a run of items too small
//to draw. "items" are the data items it replaced, largest first. The view knows
//nothing about them beyond that they exist, so the colours and the strings are
//the delegate's to decide.
- (void) treeMapView: (TreeMapView*) view
	willDisplayRemainderItems: (NSArray*) items
				 withRenderer: (TMVItem*) renderer;

- (NSString*) treeMapView: (TreeMapView*) view labelForRemainderItems: (NSArray*) items;
- (NSString*) treeMapView: (TreeMapView*) view detailLabelForRemainderItems: (NSArray*) items;

- (NSString*) treeMapView: (TreeMapView*) view getToolTipByItem: (id) item;

//The text written into a large cell, and the detail appended after a middle
//dot when there is room for both. Not implementing them turns labels off as
//surely as -setDrawsCellLabels:NO does.
- (NSString*) treeMapView: (TreeMapView*) view labelForItem: (id) item;
- (NSString*) treeMapView: (TreeMapView*) view detailLabelForItem: (id) item;

//The layout was rebuilt, so the cell rects and -mergedItemCount /
//-mergedItemWeight have all changed. Sent for a resize and a zoom as well as
//for a reload, since all three change which cells are too small to draw.
- (void) treeMapViewLayoutChanged: (NSNotification*) notification;

//A double click, after the selection has already moved to the cell under the
//pointer - so this says "act on the selection", not "here is another cell".
//The cell may be a remainder, so resolve it with -enclosingItemByCellId: rather
//than assuming it has an item.
- (void) treeMapView: (TreeMapView*) view doubleClickedCellId: (TMVCellId) cellId;

//a chance to sync the selection to the click before the context menu appears
- (void) treeMapView: (TreeMapView*) view willShowMenuForEvent: (NSEvent*) event;

//A delegate implementing these is subscribed to the matching notifications
//automatically, so it does not have to register for them itself.
- (void) treeMapViewItemTouched: (NSNotification*) notification;
- (void) treeMapViewSelectionIsChanging: (NSNotification*) notification;
- (void) treeMapViewSelectionDidChange: (NSNotification*) notification;

@end

#pragma mark --------notifications-----------------

//The cell under the pointer changed. userInfo carries the cell under
//TMVTouchedCell and, when the cell stands for one, its data item under
//TMVTouchedItem - a remainder cell has the first and not the second. An empty
//userInfo means the pointer has left the view.
extern NSString *TreeMapViewItemTouchedNotification;
extern NSString *TMVTouchedItem;
extern NSString *TMVTouchedCell;

extern NSString *TreeMapViewSelectionIsChangingNotification;
extern NSString *TreeMapViewSelectionDidChangedNotification;
extern NSString *TreeMapViewLayoutChangedNotification;
