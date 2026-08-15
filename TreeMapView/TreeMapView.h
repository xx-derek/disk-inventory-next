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
}

- (id) delegate;
- (void) setDelegate: (id) delegate;
- (id) dataSource;
- (void) setDataSource: (id) dataSource;

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
- (void) selectItemByCellId: (TMVCellId) cellId;
- (void) selectItemByPathToItem: (NSArray*) path;

//cell rects, in view coordinates
- (NSRect) itemRectByCellId: (TMVCellId) cellId;
- (NSRect) itemRectByPathToItem: (NSArray*) path;

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

- (NSString*) treeMapView: (TreeMapView*) view getToolTipByItem: (id) item;

//a chance to sync the selection to the click before the context menu appears
- (void) treeMapView: (TreeMapView*) view willShowMenuForEvent: (NSEvent*) event;

//A delegate implementing these is subscribed to the matching notifications
//automatically, so it does not have to register for them itself.
- (void) treeMapViewItemTouched: (NSNotification*) notification;
- (void) treeMapViewSelectionIsChanging: (NSNotification*) notification;
- (void) treeMapViewSelectionDidChange: (NSNotification*) notification;

@end

#pragma mark --------notifications-----------------

//the cell under the pointer changed; userInfo has the data item under
//TMVTouchedItem, and no entry at all once the pointer leaves the view
extern NSString *TreeMapViewItemTouchedNotification;
extern NSString *TMVTouchedItem;

extern NSString *TreeMapViewSelectionIsChangingNotification;
extern NSString *TreeMapViewSelectionDidChangedNotification;
