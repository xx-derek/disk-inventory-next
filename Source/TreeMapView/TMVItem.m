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
#import "NSView-BackingCoordsHelpers.h"
#import <math.h>

//Height of the parabola each cell adds to the surface it inherits, and the
//factor it shrinks by at each level below. The paper's figures.
//
//Tried and reverted: 0.20 with no decay, to flatten the broad dome a big group
//gets and give every cell a rim of its own the way the design draws it. It is
//very nearly a no-op. Intensity here is Ia + Is * (N . L) with N *normalized*,
//so once the surface has any real slope the normal saturates toward the
//horizontal and amplitude stops mattering - 2.5x the height was
//indistinguishable in a rendered comparison. These constants are a weak knob and
//not the one that separates our shading from the design's.
//
//What would separate them is the surface *function*: the design gives every cell
//a rim of fixed width whatever its size, where a parabola scaled to the cell
//spreads across a large rectangle as a soft radial gradient. That is a change to
//the renderer's character, and the handoff explicitly does not ask for it - it
//calls the CSS a browser approximation of what this already does.
static const double TMVInitialCushionHeight = 0.5;
static const double TMVCushionHeightScale   = 0.75;

//Cells below this size in either direction cannot show anything useful, so the
//layout stops descending into them. On a big volume this is what keeps the
//renderer tree from mirroring every last file on disk.
static const double TMVMinimumCellSize = 2.0;

//Below this a cell is not worth a rectangle of its own: too small to label, too
//small to aim at. Children that would land under it are packed into one
//remainder cell instead.
//
//The old 2 pt floor stays as a backstop, but on its own it was the defect: a
//71,000-file scan drew thousands of sub-pixel slivers and silently dropped the
//rest, so the cells did not sum to the total the window printed. 14 points is a
//real hit target.
//
//In points. The layout runs in backing pixels, so this is multiplied by the
//scale at the point of use - a threshold expressed in pixels would merge
//differently at 1x and 2x, and the same scan would look different on two
//displays.
static const double TMVRemainderCellSize = 14.0;

//A folder below this size that has almost nothing to show is drawn as part of
//its parent's remainder rather than as a cell of its own, so that a deep tree of
//near-identical folders produces one block per branch instead of one per folder.
//Also in points, for the same reason as above.
static const double TMVUninformativeCellSize = 48.0;

//How many cells a folder has to be able to show before subdividing it is worth
//the space. Three cells and a hatch block is the case this is aimed at.
static const NSUInteger TMVMinimumUsefulCells = 4;

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
					depth: (NSInteger) depth
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
	_isLeafCache = -1;	//not asked yet
	_cushionRenderer = [[TMVCushionRenderer alloc] init];
	_depth = depth;
	_cellStyle = TMVCellStyleCushion;

	return self;
}


- (id) initAsRemainderWithItems: (NSArray*) items
						 weight: (unsigned long long) weight
					   delegate: (id) delegate
					treeMapView: (TreeMapView*) view
						  depth: (NSInteger) depth
{
	self = [super init];
	if ( self == nil )
		return nil;

	_delegate = delegate;
	_view = view;
	_item = nil;
	_rect = NSZeroRect;
	_childRenderers = nil;
	_isLeafCache = -1;	//not asked yet - -isLeaf answers YES from _isRemainder first
	_cushionRenderer = [[TMVCushionRenderer alloc] init];
	_depth = depth;
	_cellStyle = TMVCellStyleRemainder;

	_isRemainder = YES;
	_remainderWeight = weight;
	_mergedItems = items;

	return self;
}

- (BOOL) isRemainder
{
	return _isRemainder;
}

- (NSArray*) mergedItems
{
	return _mergedItems != nil ? _mergedItems : @[];
}

- (void) refreshWithItem: (id) item
{
	if ( item != _item )
	{
		_item = item;
	}

	//child renderers are rebuilt lazily on the next layout
	_childRenderers = nil;
	_drawnChildren = nil;
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
	//A remainder has no data item; its weight is the sum it was built with.
	if ( _isRemainder )
		return _remainderWeight;

	return [_dataSource treeMapView: _view weightByItem: _item];
}

- (BOOL) isLeaf
{
	//Nothing is drawn inside a remainder - that is the point of it - and it has no
	//data item to ask about, so this comes before the cache as well as before the
	//data source.
	if ( _isRemainder )
		return YES;

	//Asked once, and remembered. A renderer stands for one data item for as long
	//as it exists, and any reload builds the tree again from scratch, so the data
	//source cannot change its answer underneath us.
	//
	//It is worth remembering because -calcLayout: asks at every cell on every
	//pass, twice over, and for a file system data source neither callback is
	//arithmetic: answering isNode: for an FSItem reaches an NSURL resource
	//lookup, keyed by string. Sampling a layout of a 435,461-item tree found
	//__CFStringHash and __CFURLResourceInfoPtr among the hottest symbols in what
	//ought to be nothing but rectangles.
	if ( _isLeafCache < 0 )
	{
		//the data source decides what counts as a folder; anything else is a leaf,
		//and so is a folder that turned out to be empty
		const BOOL leaf = ![_dataSource treeMapView: _view isNode: _item]
						  || [_dataSource treeMapView: _view numberOfChildrenOfItem: _item] == 0;

		_isLeafCache = leaf ? 1 : 0;
	}

	return _isLeafCache == 1;
}

//All three answer with what was actually laid out, not with what the data
//source described: the view walks these to draw, to label and to hit test, and
//a run of children too small to draw has been replaced by one remainder cell.
- (NSUInteger) childCount
{
	return [_drawnChildren count];
}

- (TMVItem*) childAtIndex: (NSUInteger) index
{
	return [_drawnChildren objectAtIndex: index];
}

- (NSEnumerator*) childEnumerator
{
	return [_drawnChildren objectEnumerator];
}

- (NSInteger) depth
{
	return _depth;
}

- (void) setCushionColor: (NSColor*) color
{
	[_cushionRenderer setColor: color];
}

- (NSColor*) fillColor
{
	return [_cushionRenderer color];
}

- (TMVCellStyle) cellStyle
{
	return _cellStyle;
}

- (void) setCellStyle: (TMVCellStyle) style
{
	_cellStyle = style;
}

- (NSColor*) outlineColor
{
	return _outlineColor;
}

- (NSColor*) labelColor
{
	return _labelColor;
}

- (void) setLabelColor: (NSColor*) color
{
	_labelColor = color;
}

- (void) setOutlineColor: (NSColor*) color
{
	_outlineColor = color;
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
		_drawnChildren = nil;
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
														treeMapView: _view
															  depth: _depth + 1];

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

//How many backing pixels a point covers here. The layout is in pixels; the
//remainder threshold is in points.
- (double) backingScale
{
	const NSSize unit = [_view convertSizeToBackingRespectingFlipped: NSMakeSize( 1.0, 1.0 )];

	return ( unit.height > 0.0 ) ? unit.height : 1.0;
}

//Replaces the tail of the child list with one remainder cell when those
//children would each get less area than a hit target's worth.
//
//The tail is the right run to take: the squarified algorithm needs its children
//largest-first and the document already sorts them that way, so the too-small
//ones are exactly the end of the list. The remainder carries their summed
//weight, so the area it is then given is the area they would have had between
//them - which is what keeps every cell's area proportional to its size, and
//keeps the drawn cells summing to the total the window prints.
//
//This is a function of the laid-out rect and is redone on every layout, so
//zooming in or widening the window dissolves remainders and shrinking re-forms
//them, with no extra machinery.
//How many cells a subtree would actually show at this scale, giving up as soon
//as "limit" is reached. Two things make this cheap: children arrive largest
//first, and a child never outweighs its parent - so the scan can stop at the
//first child below the threshold, because nothing after it and nothing inside
//it can clear the threshold either.
static NSUInteger DrawableCellCount( id dataSource, TreeMapView *view, id item,
									 double areaPerWeight, double minimumArea,
									 NSUInteger limit )
{
	if ( limit == 0 )
		return 0;

	const NSUInteger childCount = [dataSource treeMapView: view numberOfChildrenOfItem: item];
	NSUInteger count = 0;

	for ( NSUInteger i = 0; i < childCount; i++ )
	{
		id child = [dataSource treeMapView: view child: i ofItem: item];

		if ( [dataSource treeMapView: view weightByItem: child] * areaPerWeight < minimumArea )
			break;

		count++;

		if ( count >= limit )
			return count;

		if ( [dataSource treeMapView: view isNode: child] )
		{
			count += DrawableCellCount( dataSource, view, child, areaPerWeight,
										minimumArea, limit - count );

			if ( count >= limit )
				return count;
		}
	}

	return count;
}

//Whether this child should be drawn as a cell of its own or packed into its
//parent's remainder. Two reasons to pack it, and the second is the interesting
//one:
//
//  it is too small to be a cell        - the original rule
//  it is a folder that would show      - a folder whose cell has room for two
//  almost nothing if subdivided          or three children and a hatch block is
//                                        not showing structure, it is showing
//                                        clutter, and one block in the parent
//                                        says the same thing once
//
//The second test needs both of its bounds. On few-cells alone a 195 GB folder
//holding three enormous files would be hatched away; on size alone a small
//folder with real structure inside would be. Measured on a bazel cache: 98
//remainders, all the same size, each filling about half of a 40x40 pt folder
//that had room for three other cells - one per folder, which is what "scattered"
//looks like.
static BOOL ShouldMergeChild( TMVItem *child, id dataSource, TreeMapView *view,
							  double areaPerWeight, double minimumArea, double foldArea )
{
	const double area = [child weight] * areaPerWeight;

	if ( area < minimumArea )
		return YES;

	if ( area >= foldArea )
		return NO;

	if ( ![dataSource treeMapView: view isNode: [child item]] )
		return NO;

	return DrawableCellCount( dataSource, view, [child item], areaPerWeight,
							  minimumArea, TMVMinimumUsefulCells ) < TMVMinimumUsefulCells;
}

- (NSArray*) childRenderersMergingTailForRect: (NSRect) rect
{
	//Classic mode draws the map the way the original application did, and the
	//original drew every cell it could down to the two-pixel floor. Merging is
	//the modern behaviour, so it belongs to the modern look; asking for one and
	//getting the other would make the setting mean two unrelated things.
	if ( [_view usesClassicCushions] )
		return _childRenderers;

	const NSUInteger childCount = [_childRenderers count];

	if ( childCount < 2 )
		return _childRenderers;

	unsigned long long totalWeight = 0;
	for ( TMVItem *child in _childRenderers )
		totalWeight += [child weight];

	if ( totalWeight == 0 )
		return _childRenderers;

	const double scale = [self backingScale];
	const double minimumArea = ( TMVRemainderCellSize * scale ) * ( TMVRemainderCellSize * scale );
	const double foldArea = ( TMVUninformativeCellSize * scale ) * ( TMVUninformativeCellSize * scale );
	const double areaPerWeight = ( NSWidth(rect) * NSHeight(rect) ) / (double) totalWeight;

	//A partition rather than a tail. When the only rule was "too small", the
	//merged children really were the tail of a list sorted largest-first; a
	//folder that is big enough to draw but has nothing to show is not, so the
	//two groups are collected separately and the kept ones stay in order.
	NSMutableArray *kept = [NSMutableArray arrayWithCapacity: childCount];
	NSMutableArray *toMerge = [NSMutableArray array];

	for ( TMVItem *child in _childRenderers )
	{
		if ( ShouldMergeChild( child, _dataSource, _view, areaPerWeight, minimumArea, foldArea ) )
			[toMerge addObject: child];
		else
			[kept addObject: child];
	}

	//One cell replaced by one cell is not worth the indirection: it would lose
	//its name and gain a hatch for nothing.
	if ( [toMerge count] < 2 )
		return _childRenderers;

	//Everything merged means the parent is itself too small to subdivide; let
	//the existing minimum-cell-size rule handle that rather than drawing a
	//remainder that fills its own parent and says nothing.
	if ( [kept count] == 0 )
		return _childRenderers;

	NSMutableArray *mergedItems = [NSMutableArray arrayWithCapacity: [toMerge count]];
	unsigned long long mergedWeight = 0;

	for ( TMVItem *child in toMerge )
	{
		mergedWeight += [child weight];

		if ( [child item] != nil )
			[mergedItems addObject: [child item]];

		//a merged child is not drawn and must not be hit
		[child calcLayout: NSZeroRect];
	}

	TMVItem *remainder = [[TMVItem alloc] initAsRemainderWithItems: mergedItems
														   weight: mergedWeight
														 delegate: _delegate
													  treeMapView: _view
															depth: _depth + 1];

	if ( [_delegate respondsToSelector: @selector(treeMapView:willDisplayRemainderItems:withRenderer:)] )
		[_delegate treeMapView: _view willDisplayRemainderItems: mergedItems withRenderer: remainder];

	//Placed by weight, not appended. The squarified layout takes its children
	//largest-first and gets worse aspect ratios if that is broken - which used
	//not to matter when a remainder was a handful of slivers, and does now that
	//it can outweigh most of its siblings.
	NSUInteger insertAt = [kept count];

	for ( NSUInteger i = 0; i < [kept count]; i++ )
	{
		if ( [[kept objectAtIndex: i] weight] < mergedWeight )
		{
			insertAt = i;
			break;
		}
	}

	[kept insertObject: remainder atIndex: insertAt];

	return kept;
}

- (void) layoutChilds
{
	//_childRenderers stays as the data source described it, so the next layout
	//can merge differently; _drawnChildren is what actually gets rectangles.
	_drawnChildren = [self childRenderersMergingTailForRect: _rect];

	const NSUInteger childCount = [_drawnChildren count];
	if ( childCount == 0 )
		return;

	//Children arrive largest first, which is what makes the squarified layout
	//work; the document keeps them sorted by size for us.
	unsigned long long remainingWeight = 0;
	for ( TMVItem *child in _drawnChildren )
		remainingWeight += [child weight];

	NSRect rect = _rect;
	NSUInteger index = 0;

	while ( index < childCount )
	{
		//anything we cannot fit gets an empty rect so it is never drawn or hit
		if ( remainingWeight == 0 || NSWidth(rect) <= 0.0 || NSHeight(rect) <= 0.0 )
		{
			for ( ; index < childCount; index++ )
				[[_drawnChildren objectAtIndex: index] calcLayout: NSZeroRect];
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
			const double area = [[_drawnChildren objectAtIndex: i] weight] * areaPerWeight;

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
			TMVItem *child = [_drawnChildren objectAtIndex: index + i];
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

	//A cell that is not a cushion is left out of the bitmap entirely and
	//painted by the view afterwards. Neither a flat fill nor a dashed outline
	//is something the height field can express, and a cell drawn here and then
	//painted over would only cost a shading pass nobody sees.
	if ( _cellStyle != TMVCellStyleCushion )
		return;

	//inherit the enclosing cell's height field, then add our own ridge on top;
	//that accumulation is what makes nested cells look like stacked pillows
	if ( parentCushion != nil )
		[_cushionRenderer setSurface: [parentCushion surface]];

	[_cushionRenderer setRect: _rect];
	[_cushionRenderer addRidgeByHeightFactor: heightFactor];

	const NSUInteger childCount = [_drawnChildren count];

	if ( childCount == 0 )
	{
		[_cushionRenderer renderCushionInBitmap: bitmap];
		return;
	}

	for ( TMVItem *child in _drawnChildren )
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
	for ( TMVItem *child in _drawnChildren )
	{
		TMVItem *hit = [child hitTest: point];
		if ( hit != nil )
			return hit;
	}

	return self;
}

@end
