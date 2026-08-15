//
//  TMVItem.m
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

#import "TMVItem.h"
#import "TreeMapView.h"
#import <math.h>

//Height of the parabola added at the top level, and the factor it shrinks by at
//each level below. Taken from the cushion treemap paper; deeper cells get
//flatter ridges so the nesting stays readable instead of turning into noise.
static const double TMVInitialCushionHeight = 0.5;
static const double TMVCushionHeightScale   = 0.75;

//Cells below this size in either direction cannot show anything useful, so the
//layout stops descending into them. On a big volume this is what keeps the
//renderer tree from mirroring every last file on disk.
static const double TMVMinimumCellSize = 2.0;

@interface TMVItem(Private)

- (void) createChildRenderers;
- (void) layoutChilds;
- (void) drawCushionInBitmap: (NSBitmapImageRep*) bitmap
			   parentCushion: (TMVCushionRenderer*) parentCushion
		 cushionHeightFactor: (double) heightFactor;

@end

@implementation TMVItem

- (id) initWithDataSource: (id) dataSource
				 delegate: (id) delegate
			 renderedItem: (id) item
			  treeMapView: (TreeMapView*) view
{
	self = [super init];
	if ( self == nil )
		return nil;

	//the data source and delegate outlive us; the view owns the renderer tree
	_dataSource = dataSource;
	_delegate = delegate;
	_view = view;
	_item = item;
	_rect = NSZeroRect;
	_childRenderers = nil;
	_cushionRenderer = [[TMVCushionRenderer alloc] init];

	return self;
}


- (void) refreshWithItem: (id) item
{
	if ( item != _item )
	{
		_item = item;
	}

	//child renderers are rebuilt lazily on the next layout
	_childRenderers = nil;
}

#pragma mark --------accessors-----------------

- (id) item
{
	return _item;
}

- (NSRect) rect
{
	return _rect;
}

- (unsigned long long) weight
{
	return [_dataSource treeMapView: _view weightByItem: _item];
}

- (BOOL) isLeaf
{
	//the data source decides what counts as a folder; anything else is a leaf,
	//and so is a folder that turned out to be empty
	if ( ![_dataSource treeMapView: _view isNode: _item] )
		return YES;

	return [_dataSource treeMapView: _view numberOfChildrenOfItem: _item] == 0;
}

- (NSUInteger) childCount
{
	return [_childRenderers count];
}

- (TMVItem*) childAtIndex: (NSUInteger) index
{
	return [_childRenderers objectAtIndex: index];
}

- (NSEnumerator*) childEnumerator
{
	return [_childRenderers objectEnumerator];
}

- (void) setCushionColor: (NSColor*) color
{
	[_cushionRenderer setColor: color];
}

#pragma mark --------layout-----------------

- (void) calcLayout: (NSRect) rect
{
	_rect = rect;
	[_cushionRenderer setRect: rect];

	//stop descending once a cell is too small to show its contents
	if ( [self isLeaf]
		 || NSWidth(rect) < TMVMinimumCellSize
		 || NSHeight(rect) < TMVMinimumCellSize )
	{
		_childRenderers = nil;
		return;
	}

	if ( _childRenderers == nil )
		[self createChildRenderers];

	[self layoutChilds];
}

- (void) createChildRenderers
{
	const NSUInteger childCount = [_dataSource treeMapView: _view numberOfChildrenOfItem: _item];

	_childRenderers = [[NSMutableArray alloc] initWithCapacity: childCount];

	for ( NSUInteger i = 0; i < childCount; i++ )
	{
		id childItem = [_dataSource treeMapView: _view child: i ofItem: _item];

		TMVItem *childRenderer = [[TMVItem alloc] initWithDataSource: _dataSource
														   delegate: _delegate
													   renderedItem: childItem
														treeMapView: _view];

		//let the delegate pick the cell's color before it is ever drawn
		if ( [_delegate respondsToSelector: @selector(treeMapView:willDisplayItem:withRenderer:)] )
			[_delegate treeMapView: _view willDisplayItem: childItem withRenderer: childRenderer];

		[_childRenderers addObject: childRenderer];
	}
}

//The squarified treemap cost function: given a strip of the given length
//holding cells of the given total, smallest and largest area, how far from
//square is the worst cell in it?
static inline double WorstAspectRatio( double rowArea, double minArea, double maxArea, double rowLength )
{
	if ( rowArea <= 0.0 || rowLength <= 0.0 || minArea <= 0.0 )
		return INFINITY;

	const double rowLengthSquared = rowLength * rowLength;
	const double rowAreaSquared = rowArea * rowArea;

	const double widest   = ( rowLengthSquared * maxArea ) / rowAreaSquared;
	const double thinnest = rowAreaSquared / ( rowLengthSquared * minArea );

	return MAX( widest, thinnest );
}

- (void) layoutChilds
{
	const NSUInteger childCount = [_childRenderers count];
	if ( childCount == 0 )
		return;

	//Children arrive largest first, which is what makes the squarified layout
	//work; the document keeps them sorted by size for us.
	unsigned long long remainingWeight = 0;
	for ( TMVItem *child in _childRenderers )
		remainingWeight += [child weight];

	NSRect rect = _rect;
	NSUInteger index = 0;

	while ( index < childCount )
	{
		//anything we cannot fit gets an empty rect so it is never drawn or hit
		if ( remainingWeight == 0 || NSWidth(rect) <= 0.0 || NSHeight(rect) <= 0.0 )
		{
			for ( ; index < childCount; index++ )
				[[_childRenderers objectAtIndex: index] calcLayout: NSZeroRect];
			break;
		}

		//area each unit of weight is worth in what is left of the rect
		const double areaPerWeight = ( NSWidth(rect) * NSHeight(rect) ) / (double) remainingWeight;

		//strips run along the shorter side, which is what keeps cells square
		const BOOL rowIsHorizontal = NSWidth(rect) < NSHeight(rect);
		const double rowLength = rowIsHorizontal ? NSWidth(rect) : NSHeight(rect);

		//grow the strip while doing so makes its worst cell more square
		double rowArea = 0.0, minArea = 0.0, maxArea = 0.0;
		double currentWorst = INFINITY;
		NSUInteger childsUsed = 0;

		for ( NSUInteger i = index; i < childCount; i++ )
		{
			const double area = [[_childRenderers objectAtIndex: i] weight] * areaPerWeight;

			const double newRowArea = rowArea + area;
			const double newMinArea = ( childsUsed == 0 ) ? area : MIN( minArea, area );
			const double newMaxArea = ( childsUsed == 0 ) ? area : MAX( maxArea, area );

			const double newWorst = WorstAspectRatio( newRowArea, newMinArea, newMaxArea, rowLength );

			//keep at least one cell per strip, otherwise zero-area items stall us
			if ( childsUsed > 0 && newWorst > currentWorst )
				break;

			rowArea = newRowArea;
			minArea = newMinArea;
			maxArea = newMaxArea;
			currentWorst = newWorst;
			childsUsed++;
		}

		const double thickness = rowArea / rowLength;

		//place the strip's cells along it, then cut the strip off the rect
		double offset = rowIsHorizontal ? NSMinX(rect) : NSMinY(rect);

		for ( NSUInteger i = 0; i < childsUsed; i++ )
		{
			TMVItem *child = [_childRenderers objectAtIndex: index + i];
			const double area = [child weight] * areaPerWeight;
			const double extent = ( rowArea > 0.0 ) ? ( area / rowArea ) * rowLength : 0.0;

			NSRect childRect;
			if ( rowIsHorizontal )
				childRect = NSMakeRect( offset, NSMinY(rect), extent, thickness );
			else
				childRect = NSMakeRect( NSMinX(rect), offset, thickness, extent );

			//the last cell absorbs the rounding so the strip fills exactly
			if ( i == childsUsed - 1 )
			{
				if ( rowIsHorizontal )
					childRect.size.width = MAX( 0.0, NSMaxX(rect) - offset );
				else
					childRect.size.height = MAX( 0.0, NSMaxY(rect) - offset );
			}

			[child calcLayout: childRect];

			offset += extent;
			remainingWeight -= [child weight];
		}

		if ( rowIsHorizontal )
		{
			rect.origin.y += thickness;
			rect.size.height -= thickness;
		}
		else
		{
			rect.origin.x += thickness;
			rect.size.width -= thickness;
		}

		index += childsUsed;
	}
}

#pragma mark --------drawing-----------------

- (void) drawCushionInBitmap: (NSBitmapImageRep*) bitmap
{
	[self drawCushionInBitmap: bitmap
				parentCushion: nil
		  cushionHeightFactor: TMVInitialCushionHeight];
}

- (void) drawCushionInBitmap: (NSBitmapImageRep*) bitmap
			   parentCushion: (TMVCushionRenderer*) parentCushion
		 cushionHeightFactor: (double) heightFactor
{
	if ( NSIsEmptyRect(_rect) )
		return;

	//inherit the enclosing cell's height field, then add our own ridge on top;
	//that accumulation is what makes nested cells look like stacked pillows
	if ( parentCushion != nil )
		[_cushionRenderer setSurface: [parentCushion surface]];

	[_cushionRenderer setRect: _rect];
	[_cushionRenderer addRidgeByHeightFactor: heightFactor];

	const NSUInteger childCount = [_childRenderers count];

	if ( childCount == 0 )
	{
		[_cushionRenderer renderCushionInBitmap: bitmap];
		return;
	}

	for ( TMVItem *child in _childRenderers )
	{
		[child drawCushionInBitmap: bitmap
					 parentCushion: _cushionRenderer
			   cushionHeightFactor: heightFactor * TMVCushionHeightScale];
	}
}

#pragma mark --------hit testing-----------------

- (TMVItem*) hitTest: (NSPoint) point
{
	if ( !NSPointInRect( point, _rect ) )
		return nil;

	//descend to the deepest cell under the point
	for ( TMVItem *child in _childRenderers )
	{
		TMVItem *hit = [child hitTest: point];
		if ( hit != nil )
			return hit;
	}

	return self;
}

@end
