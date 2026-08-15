//
//  TreeMapView.m
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

#import "TreeMapView.h"
#import "NSBitmapImageRep-CreationExtensions.h"
#import "NSView-BackingCoordsHelpers.h"
#import "ZoomInfo.h"

NSString *TreeMapViewItemTouchedNotification = @"TreeMapViewItemTouchedNotification";
NSString *TMVTouchedItem = @"TMVTouchedItem";
NSString *TreeMapViewSelectionIsChangingNotification = @"TreeMapViewSelectionIsChangingNotification";
NSString *TreeMapViewSelectionDidChangedNotification = @"TreeMapViewSelectionDidChangedNotification";

@interface TreeMapView(Private)

- (void) drawInCache;
- (void) deallocContentCache;
- (void) recalcLayout;
- (TMVItem*) findTMVItemByPathToDataItem: (NSArray*) path;
- (void) setTouchedRenderer: (TMVItem*) renderer;
- (void) selectRendererFromEvent: (NSEvent*) event notificationName: (NSString*) notificationName;
- (NSImage*) contentSnapshot;
- (void) startZoomWithImage: (NSImage*) image fromRect: (NSRect) fromRect toRect: (NSRect) toRect;
- (void) performZoom: (ZoomInfo*) zoomer;

@end

@implementation TreeMapView

- (id) initWithFrame: (NSRect) frame
{
	self = [super initWithFrame: frame];
	if ( self == nil )
		return nil;

	[self setPostsFrameChangedNotifications: YES];

	return self;
}

- (void) awakeFromNib
{
	[super awakeFromNib];

	[self setPostsFrameChangedNotifications: YES];

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(viewFrameDidChangeNotification:)
												 name: NSViewFrameDidChangeNotification
											   object: self];

	[self reloadData];
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver: self];

	//stop the animation before its timer can call back into a half-dead view
	[_zoomer cancel];


}

#pragma mark --------data source and delegate-----------------

- (id) delegate
{
	return delegate;
}

- (void) setDelegate: (id) newDelegate
{
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

	if ( delegate != nil )
	{
		[notificationCenter removeObserver: delegate name: TreeMapViewItemTouchedNotification object: self];
		[notificationCenter removeObserver: delegate name: TreeMapViewSelectionIsChangingNotification object: self];
		[notificationCenter removeObserver: delegate name: TreeMapViewSelectionDidChangedNotification object: self];
	}

	//delegates are not retained, as everywhere else in AppKit
	delegate = newDelegate;

	//A delegate gets subscribed to whichever of the notifications it implements
	//a handler for, so it never has to register by hand.
#define OBSERVE_IF_IMPLEMENTED( handler, notificationName )								\
	if ( [delegate respondsToSelector: @selector(handler)] )							\
		[notificationCenter addObserver: delegate									 	\
							   selector: @selector(handler)								\
								   name: notificationName								\
								 object: self];

	OBSERVE_IF_IMPLEMENTED( treeMapViewItemTouched:, TreeMapViewItemTouchedNotification )
	OBSERVE_IF_IMPLEMENTED( treeMapViewSelectionIsChanging:, TreeMapViewSelectionIsChangingNotification )
	OBSERVE_IF_IMPLEMENTED( treeMapViewSelectionDidChange:, TreeMapViewSelectionDidChangedNotification )

#undef OBSERVE_IF_IMPLEMENTED
}

- (id) dataSource
{
	return dataSource;
}

- (void) setDataSource: (id) newDataSource
{
	dataSource = newDataSource;

	[self reloadData];
}

#pragma mark --------reloading and layout-----------------

- (void) invalidateCanvasCache
{
	[self deallocContentCache];
	[self setNeedsDisplay: YES];
}

- (void) deallocContentCache
{
	_cachedContent = nil;
}

- (void) reloadData
{
	//cells from the old tree are about to become garbage
	_selectedRenderer = nil;
	_touchedRenderer = nil;

	_rootItemRenderer = nil;

	if ( dataSource != nil )
	{
		//the data source addresses the root as nil, the way NSOutlineView does
		_rootItemRenderer = [[TMVItem alloc] initWithDataSource: dataSource
													   delegate: delegate
												   renderedItem: nil
													treeMapView: self];

		if ( [delegate respondsToSelector: @selector(treeMapView:willDisplayItem:withRenderer:)] )
			[delegate treeMapView: self willDisplayItem: nil withRenderer: _rootItemRenderer];
	}

	[self recalcLayout];
	[self invalidateCanvasCache];
}

- (void) recalcLayout
{
	if ( _rootItemRenderer == nil )
		return;

	//The layout is computed in backing pixels, not points, so that on a Retina
	//display the cushions are shaded at full resolution instead of being
	//rendered once per point and scaled up.
	const NSSize backingSize = [self convertSizeToBackingRespectingFlipped: [self bounds].size];

	[_rootItemRenderer calcLayout: NSMakeRect( 0.0, 0.0,
											   floor( backingSize.width ),
											   floor( backingSize.height ) )];
}

#pragma mark --------drawing-----------------

- (void) drawInCache
{
	[self deallocContentCache];

	_cachedContent = [NSBitmapImageRep imageRepCompatibleWithView: self];
	if ( _cachedContent == nil )
		return;

	//start from black; the cells cover the whole rect, but rounding can still
	//leave hairline seams between them
	unsigned char *bitmapData = [_cachedContent bitmapData];
	if ( bitmapData != NULL )
		memset( bitmapData, 0, [_cachedContent bytesPerRow] * [_cachedContent pixelsHigh] );

	[_rootItemRenderer drawCushionInBitmap: _cachedContent];
}

- (void) drawRect: (NSRect) dirtyRect
{
	//While zooming, the snapshot stands in for the whole view; the new layout
	//is already in place behind it and appears when the effect finishes.
	if ( _zoomer != nil )
	{
		[[NSColor windowBackgroundColor] set];
		NSRectFill( dirtyRect );
		[_zoomer drawImage];
		return;
	}

	if ( _cachedContent == nil )
		[self drawInCache];

	if ( _cachedContent != nil )
	{
		//stretched to the view during a live resize, exact everywhere else
		[_cachedContent drawInRect: [self bounds]
						  fromRect: NSZeroRect
						 operation: NSCompositingOperationCopy
						  fraction: 1.0
					respectFlipped: YES
							 hints: nil];
	}
	else
	{
		[[NSColor windowBackgroundColor] set];
		NSRectFill( dirtyRect );
	}

	if ( _selectedRenderer != nil )
	{
		NSRect selectionRect = [self itemRectByCellId: _selectedRenderer];

		if ( !NSIsEmptyRect(selectionRect) )
		{
			//A cell can be a single point wide, so the frame is drawn just
			//inside it and stroked in two tones to stay visible over any
			//cushion color underneath.
			NSRect frame = NSInsetRect( selectionRect, 0.5, 0.5 );
			if ( NSIsEmptyRect(frame) )
				frame = selectionRect;

			NSBezierPath *path = [NSBezierPath bezierPathWithRect: frame];
			[path setLineWidth: 1.0];

			[[NSColor blackColor] set];
			[path stroke];

			[[NSColor whiteColor] set];
			[[NSBezierPath bezierPathWithRect: NSInsetRect( frame, 1.0, 1.0 )] stroke];
		}
	}
}

- (BOOL) isOpaque
{
	return YES;
}

- (BOOL) isFlipped
{
	//cells are laid out top-down, matching the row order of the bitmap
	return YES;
}

- (void) drawFocusRingMask
{
	NSRectFill( [self bounds] );
}

- (NSRect) focusRingMaskBounds
{
	return [self bounds];
}

#pragma mark --------cells-----------------

- (TMVCellId) cellIdByPoint: (NSPoint) point inViewCoords: (BOOL) viewCoords
{
	if ( _rootItemRenderer == nil )
		return nil;

	const NSPoint viewPoint = viewCoords ? point : [self convertPoint: point fromView: nil];

	//the layout lives in backing pixels, so the hit test has to as well
	return [_rootItemRenderer hitTest: [self convertPointToBackingRespectingFlipped: viewPoint]];
}

- (id) itemByCellId: (TMVCellId) cellId
{
	return [cellId item];
}

- (NSRect) itemRectByCellId: (TMVCellId) cellId
{
	if ( cellId == nil )
		return NSZeroRect;

	return [self convertRectFromBackingRespectingFlipped: [cellId rect]];
}

- (NSRect) itemRectByPathToItem: (NSArray*) path
{
	return [self itemRectByCellId: [self findTMVItemByPathToDataItem: path]];
}

- (TMVItem*) findTMVItemByPathToDataItem: (NSArray*) path
{
	if ( _rootItemRenderer == nil || [path count] == 0 )
		return nil;

	//path[0] is the root, which the data source refers to as nil
	TMVItem *renderer = _rootItemRenderer;

	for ( NSUInteger i = 1; i < [path count]; i++ )
	{
		id dataItem = [path objectAtIndex: i];
		TMVItem *match = nil;

		for ( TMVItem *child in [renderer childEnumerator] )
		{
			if ( [child item] == dataItem )
			{
				match = child;
				break;
			}
		}

		//The layout stops descending into cells too small to draw, so an item
		//deep in the tree may have no cell of its own. Its nearest drawn
		//ancestor is the cell that actually covers it on screen.
		if ( match == nil )
			break;

		renderer = match;
	}

	return renderer;
}

#pragma mark --------selection-----------------

- (id) selectedItem
{
	return [_selectedRenderer item];
}

- (void) selectItemByCellId: (TMVCellId) cellId
{
	if ( cellId == _selectedRenderer )
		return;

	_selectedRenderer = cellId;

	//only the frame changes, so the cached cushions stay valid
	[self setNeedsDisplay: YES];
}

- (void) selectItemByPathToItem: (NSArray*) path
{
	[self selectItemByCellId: [self findTMVItemByPathToDataItem: path]];
}

#pragma mark --------mouse handling-----------------

- (BOOL) acceptsFirstResponder
{
	return YES;
}

- (BOOL) canBecomeKeyView
{
	return YES;
}

- (BOOL) becomeFirstResponder
{
	[self setNeedsDisplay: YES];

	return [super becomeFirstResponder];
}

- (BOOL) resignFirstResponder
{
	[self setNeedsDisplay: YES];

	return [super resignFirstResponder];
}

//Selection is posted only for changes the user made. Selecting a cell
//programmatically stays silent, so a controller syncing the view to a model
//cannot bounce the change straight back at itself.
- (void) selectRendererFromEvent: (NSEvent*) event notificationName: (NSString*) notificationName
{
	TMVItem *hit = [self cellIdByPoint: [event locationInWindow] inViewCoords: NO];

	const BOOL selectionChanged = ( hit != _selectedRenderer );

	[self selectItemByCellId: hit];

	if ( selectionChanged || [notificationName isEqualToString: TreeMapViewSelectionDidChangedNotification] )
		[[NSNotificationCenter defaultCenter] postNotificationName: notificationName object: self];
}

- (void) mouseDown: (NSEvent*) event
{
	[[self window] makeFirstResponder: self];

	[self selectRendererFromEvent: event notificationName: TreeMapViewSelectionIsChangingNotification];
}

- (void) mouseDragged: (NSEvent*) event
{
	[self selectRendererFromEvent: event notificationName: TreeMapViewSelectionIsChangingNotification];
}

- (void) mouseUp: (NSEvent*) event
{
	[self selectRendererFromEvent: event notificationName: TreeMapViewSelectionDidChangedNotification];
}

- (NSMenu*) menuForEvent: (NSEvent*) event
{
	//lets the delegate move the selection to the clicked cell first, so the
	//menu visibly applies to what was clicked
	if ( [delegate respondsToSelector: @selector(treeMapView:willShowMenuForEvent:)] )
		[delegate treeMapView: self willShowMenuForEvent: event];

	return [super menuForEvent: event];
}

- (void) setTouchedRenderer: (TMVItem*) renderer
{
	if ( renderer == _touchedRenderer )
		return;

	_touchedRenderer = renderer;

	//no entry at all once the pointer is off the map, which is how an observer
	//tells "nothing under the pointer" from "a cell with no data item"
	NSDictionary *userInfo = ( [_touchedRenderer item] != nil )
							 ? [NSDictionary dictionaryWithObject: [_touchedRenderer item] forKey: TMVTouchedItem]
							 : [NSDictionary dictionary];

	[[NSNotificationCenter defaultCenter] postNotificationName: TreeMapViewItemTouchedNotification
														object: self
													  userInfo: userInfo];
}

- (void) mouseMoved: (NSEvent*) event
{
	[self setTouchedRenderer: [self cellIdByPoint: [event locationInWindow] inViewCoords: NO]];
}

- (void) mouseExited: (NSEvent*) event
{
	[self setTouchedRenderer: nil];
}

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];

	for ( NSTrackingArea *area in [[self trackingAreas] copy] )
		[self removeTrackingArea: area];

	NSTrackingArea *trackingArea =
		[[NSTrackingArea alloc] initWithRect: NSZeroRect		//ignored, tracks the visible rect
									options: NSTrackingMouseMoved
											 | NSTrackingMouseEnteredAndExited
											 | NSTrackingActiveInKeyWindow
											 | NSTrackingInVisibleRect
									  owner: self
								   userInfo: nil];

	[self addTrackingArea: trackingArea];

	//one tooltip region over the whole view; the string is resolved per point
	[self removeAllToolTips];
	[self addToolTipRect: [self visibleRect] owner: self userData: NULL];
}

- (NSString*) view: (NSView*) view
   stringForToolTip: (NSToolTipTag) tag
			  point: (NSPoint) point
		   userData: (void*) userData
{
	if ( ![delegate respondsToSelector: @selector(treeMapView:getToolTipByItem:)] )
		return nil;

	TMVItem *cell = [self cellIdByPoint: point inViewCoords: YES];
	if ( cell == nil )
		return nil;

	return [delegate treeMapView: self getToolTipByItem: [cell item]];
}

#pragma mark --------resizing-----------------

- (void) viewFrameDidChangeNotification: (NSNotification*) notification
{
	//A relayout walks the whole tree, which is far too slow to do on every
	//frame of a drag. The cached bitmap is stretched instead, and the real
	//layout is recomputed once the drag ends.
	if ( [self inLiveResize] )
	{
		[self setNeedsDisplay: YES];
		return;
	}

	[self recalcLayout];
	[self invalidateCanvasCache];
}

- (void) viewWillStartLiveResize
{
	[super viewWillStartLiveResize];
}

- (void) viewDidEndLiveResize
{
	[super viewDidEndLiveResize];

	[self recalcLayout];
	[self invalidateCanvasCache];
}

- (void) viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];

	//moved between displays of different scale, so the layout is now the wrong
	//size in pixels
	[self recalcLayout];
	[self invalidateCanvasCache];
}

- (void) windowDidBecomeKey: (NSNotification*) notification
{
	[self setNeedsDisplay: YES];
}

- (void) windowDidResignKey: (NSNotification*) notification
{
	[self setNeedsDisplay: YES];
}

#pragma mark --------zooming-----------------

- (BOOL) zoomingInProgress
{
	return _zoomer != nil;
}

- (NSImage*) contentSnapshot
{
	if ( _cachedContent == nil )
		[self drawInCache];

	if ( _cachedContent == nil )
		return nil;

	//the image keeps its own reference to the bitmap, so the reload that
	//follows is free to throw the cache away
	return [_cachedContent suitableImageForView: self];
}

- (void) startZoomWithImage: (NSImage*) image fromRect: (NSRect) fromRect toRect: (NSRect) toRect
{
	if ( image == nil || NSIsEmptyRect(fromRect) || NSIsEmptyRect(toRect) )
		return;

	_zoomer = [[ZoomInfo alloc] initWithImage: image
									 delegate: self
									 selector: @selector(performZoom:)];

	[_zoomer calculateZoomFromRect: fromRect toRect: toRect];

	[self setNeedsDisplay: YES];
}

- (void) performZoom: (ZoomInfo*) zoomer
{
	if ( [zoomer hasFinished] )
	{
		//autoreleased, because we are being called from inside the zoomer
		_zoomer = nil;
	}

	[self setNeedsDisplay: YES];
}

- (void) reloadAndPerformZoomIntoItem: (NSArray*) path
{
	NSImage *snapshot = [self contentSnapshot];

	//the cell is only in the old layout, so it has to be measured before reload
	const NSRect itemRect = [self itemRectByPathToItem: path];
	const NSRect bounds = [self bounds];

	[self reloadData];

	if ( NSIsEmptyRect(itemRect) || NSIsEmptyRect(bounds) )
		return;

	//Blow the snapshot up about the zoomed-in cell, so that cell ends up
	//filling the view exactly as the new layout appears behind it.
	const CGFloat scaleX = NSWidth(bounds) / NSWidth(itemRect);
	const CGFloat scaleY = NSHeight(bounds) / NSHeight(itemRect);

	const NSRect toRect = NSMakeRect( NSMinX(bounds) - ( NSMinX(itemRect) - NSMinX(bounds) ) * scaleX,
									  NSMinY(bounds) - ( NSMinY(itemRect) - NSMinY(bounds) ) * scaleY,
									  NSWidth(bounds) * scaleX,
									  NSHeight(bounds) * scaleY );

	[self startZoomWithImage: snapshot fromRect: bounds toRect: toRect];
}

#pragma mark --------benchmarks-----------------

- (void) benchmarkLayoutCalculationWithImageSize: (NSSize) size count: (unsigned) count
{
	const NSRect rect = NSMakeRect( 0.0, 0.0, size.width, size.height );

	for ( unsigned i = 0; i < count; i++ )
		[_rootItemRenderer calcLayout: rect];

	//the layout just run is at the benchmark's size, not the view's
	[self recalcLayout];
	[self invalidateCanvasCache];
}

- (void) benchmarkRenderingWithImageSize: (NSSize) size count: (unsigned) count
{
	NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initRGBBitmapWithWidth: (NSInteger) size.width
																		height: (NSInteger) size.height];

	const NSRect rect = NSMakeRect( 0.0, 0.0, size.width, size.height );

	//laid out once at the benchmark's size, so every pass shades the same cells
	[_rootItemRenderer calcLayout: rect];

	for ( unsigned i = 0; i < count; i++ )
		[_rootItemRenderer drawCushionInBitmap: bitmap];

	[self recalcLayout];
	[self invalidateCanvasCache];
}

- (void) reloadAndPerformZoomOutofItem: (NSArray*) path
{
	NSImage *snapshot = [self contentSnapshot];
	const NSRect bounds = [self bounds];

	[self reloadData];

	//zooming out, the cell is the place in the *new* layout that the old view
	//shrinks into, so this has to be measured after the reload
	const NSRect itemRect = [self itemRectByPathToItem: path];

	if ( NSIsEmptyRect(itemRect) || NSIsEmptyRect(bounds) )
		return;

	[self startZoomWithImage: snapshot fromRect: bounds toRect: itemRect];
}

@end
