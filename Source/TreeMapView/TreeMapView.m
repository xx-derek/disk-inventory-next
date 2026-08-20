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
NSString *TMVTouchedCell = @"TMVTouchedCell";
NSString *TreeMapViewSelectionIsChangingNotification = @"TreeMapViewSelectionIsChangingNotification";
NSString *TreeMapViewSelectionDidChangedNotification = @"TreeMapViewSelectionDidChangedNotification";
NSString *TreeMapViewLayoutChangedNotification = @"TreeMapViewLayoutChangedNotification";

//How narrow a remainder cell may get and still be drawn as one. Its area has
//to clear the merge threshold, but nothing stops it being a long sliver - a few
//points on the short side and hundreds on the long one - and neither of these
//marks survives that. A hatch needs room for more than one stripe or it is a
//smear, and a border stroked around a four-point cell is not an edge on a cell,
//it is the whole cell. Below these the remainder keeps its fill and loses the
//marks; it is still drawn, and its area is still its share.
static const CGFloat TMVMinimumHatchedCellSize  = 10.0;
static const CGFloat TMVMinimumOutlinedCellSize =  6.0;

//One piece of precomputed overlay geometry: a plain cell, a gutter outline or
//a placed label. One class for all three because they are all a rectangle and
//at most two colours, and three near-identical classes would be worse.
@interface TMVOverlayItem : NSObject
@property (nonatomic, assign) NSRect rect;
@property (nonatomic, assign) NSRect outlineRect;
@property (nonatomic, strong) NSAttributedString *text;
@property (nonatomic, strong) NSColor *fill;
@property (nonatomic, strong) NSColor *outline;
@property (nonatomic, assign) BOOL hatched;
@end

@implementation TMVOverlayItem
@end

@interface TreeMapView(Private)

- (void) applyDefaultAppearance;
- (void) drawInCache;
- (void) deallocContentCache;
- (void) recalcLayout;
- (void) invalidateOverlay;
- (void) buildOverlay;
- (void) drawOverlay;
- (NSRect) overlayRect: (NSRect) rect scaledBy: (NSSize) scale;
- (NSSize) overlayScale;
- (void) beginObservingFrameChanges;
- (void) collectPlainCellsForRenderer: (TMVItem*) renderer;
- (void) collectGutters;
- (void) collectGuttersForRenderer: (TMVItem*) renderer;
- (void) collectLabelsForRenderer: (TMVItem*) renderer claimedRects: (NSMutableArray<NSValue*>*) claimed;
- (void) collectLabelForRenderer: (TMVItem*) renderer claimedRects: (NSMutableArray<NSValue*>*) claimed;
- (BOOL) text: (NSString*) text fitsInRect: (NSRect) rect withAttributes: (NSDictionary*) attributes;
- (NSDictionary*) cellLabelAttributes;
- (void) drawSelectionOutline;
- (void) drawHatchInRect: (NSRect) rect color: (NSColor*) color;
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

	[self beginObservingFrameChanges];
	[self applyDefaultAppearance];

	return self;
}

- (id) initWithCoder: (NSCoder*) coder
{
	self = [super initWithCoder: coder];
	if ( self == nil )
		return nil;

	//the view comes out of a nib, so this initialiser is the one that runs in
	//the running application; -initWithFrame: is the probes' path
	[self beginObservingFrameChanges];
	[self applyDefaultAppearance];

	return self;
}

//Sensible values so the view is usable on its own. The controller overrides
//the colours with the application's palette.
- (void) applyDefaultAppearance
{
	_gutterWidth    = 2.0;
	_contentInset   = 0.0;
	_gutterColor    = [NSColor controlBackgroundColor];
	_drawsCellLabels = YES;
	//rgba(0,0,0,.66), from the design file; the README says .62 and the HTML is
	//the value that was actually drawn.
	_cellLabelColor = [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.66];
	_selectionColor = [NSColor controlAccentColor];
}

- (void) setGutterWidth: (CGFloat) width
{
	if ( _gutterWidth == width )
		return;

	_gutterWidth = width;
	[self invalidateOverlay];
	[self setNeedsDisplay: YES];	//an overlay: the cushion cache stays valid
}

- (void) setContentInset: (CGFloat) inset
{
	if ( _contentInset == inset )
		return;

	_contentInset = inset;

	//a layout change, not a redraw: every cell rect moves
	[self recalcLayout];
	[self invalidateCanvasCache];
	[self setNeedsDisplay: YES];
}

- (void) setGutterColor: (NSColor*) color
{
	_gutterColor = color;
	[self setNeedsDisplay: YES];
}

- (void) setDrawsCellLabels: (BOOL) draws
{
	if ( _drawsCellLabels == draws )
		return;

	_drawsCellLabels = draws;
	[self invalidateOverlay];
	[self setNeedsDisplay: YES];
}

- (void) setCellLabelColor: (NSColor*) color
{
	_cellLabelColor = color;
	[self setNeedsDisplay: YES];
}

- (void) setSelectionColor: (NSColor*) color
{
	_selectionColor = color;
	[self setNeedsDisplay: YES];
}

//Registered from every initialiser, not from -awakeFromNib. It used to be set
//up there alone, which meant a TreeMapView created in code never recomputed its
//layout when it was resized - it stretched its cached bitmap forever. In the
//application the view always comes from a nib, so this was invisible; it is
//only reachable from a test harness, which is exactly where a silently wrong
//layout is most expensive.
- (void) beginObservingFrameChanges
{
	[self setPostsFrameChangedNotifications: YES];

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(viewFrameDidChangeNotification:)
												 name: NSViewFrameDidChangeNotification
											   object: self];
}

- (void) awakeFromNib
{
	[super awakeFromNib];

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
		[notificationCenter removeObserver: delegate name: TreeMapViewLayoutChangedNotification object: self];
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
	OBSERVE_IF_IMPLEMENTED( treeMapViewLayoutChanged:, TreeMapViewLayoutChangedNotification )

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

- (BOOL) usesClassicCushions
{
	return _usesClassicCushions;
}

- (void) setUsesClassicCushions: (BOOL) classic
{
	if ( _usesClassicCushions == classic )
		return;

	_usesClassicCushions = classic;

	//the shading is baked into the bitmap, so this is a re-shade and not a redraw
	[self invalidateCanvasCache];
}

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
													treeMapView: self
														  depth: 0];

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

	//The inset is given in points and applied here, in backing pixels, so it is
	//the same width on screen at 1x and 2x. Expressing it in pixels instead
	//would halve it on a Retina display.
	const CGFloat scale = [self convertSizeToBackingRespectingFlipped: NSMakeSize( 1.0, 1.0 )].width;
	const CGFloat inset = floor( _contentInset * scale );

	//Never so much that there is nothing left to lay out: a narrow pane during a
	//drag can be thinner than two margins.
	const CGFloat width  = floor( backingSize.width )  - inset * 2.0;
	const CGFloat height = floor( backingSize.height ) - inset * 2.0;

	if ( width <= 0.0 || height <= 0.0 )
		[_rootItemRenderer calcLayout: NSMakeRect( 0.0, 0.0,
												   floor( backingSize.width ),
												   floor( backingSize.height ) )];
	else
		[_rootItemRenderer calcLayout: NSMakeRect( inset, inset, width, height )];

	[self invalidateOverlay];
}

#pragma mark --------drawing-----------------

- (void) drawInCache
{
	[self deallocContentCache];

	//The cushion constants are numbers, not colours, so they cannot come from
	//the asset catalog and the appearance has to be read here instead. Read at
	//cache-build time rather than per pixel, and the cache is thrown away when
	//the appearance changes - see -viewDidChangeEffectiveAppearance.
	NSAppearanceName matched =
		[[self effectiveAppearance] bestMatchFromAppearancesWithNames:
			@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];

	[TMVCushionRenderer setUsesDarkShading:
		[matched isEqualToString: NSAppearanceNameDarkAqua]];

	//Both are process-wide on the renderer rather than per instance, for the same
	//reason the dark flag is: the shading runs in a tight per-pixel loop and this
	//keeps a branch and a lookup out of it.
	[TMVCushionRenderer setUsesRimShading: !_usesClassicCushions];
	[TMVCushionRenderer setBackingScale:
		[self convertSizeToBackingRespectingFlipped: NSMakeSize( 1.0, 1.0 )].width];

	_cachedContent = [NSBitmapImageRep imageRepCompatibleWithView: self];
	if ( _cachedContent == nil )
		return;

	//The ground the cells sit on. It shows in two places: the hairline seams
	//rounding can leave between cells, and - once there is a content inset - the
	//margin around the whole map, which is most of what anyone sees of it.
	//
	//Drawn rather than memset, because the bitmap's layout comes from
	//+imageRepCompatibleWithView: and writing bytes into it assumes an order and
	//a channel count that are not ours to assume. Classic mode keeps the black
	//it always had: it has no gutters and no inset, so this is only ever the
	//seams there, and they are part of how the original looked.
	if ( _usesClassicCushions || _gutterColor == nil )
	{
		unsigned char *bitmapData = [_cachedContent bitmapData];
		if ( bitmapData != NULL )
			memset( bitmapData, 0, [_cachedContent bytesPerRow] * [_cachedContent pixelsHigh] );
	}
	else
	{
		NSGraphicsContext *context =
			[NSGraphicsContext graphicsContextWithBitmapImageRep: _cachedContent];

		if ( context != nil )
		{
			[NSGraphicsContext saveGraphicsState];
			[NSGraphicsContext setCurrentContext: context];

			[_gutterColor set];
			NSRectFill( NSMakeRect( 0.0, 0.0,
									[_cachedContent pixelsWide], [_cachedContent pixelsHigh] ) );

			[NSGraphicsContext restoreGraphicsState];
		}
	}

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

	//Everything from here down is painted over the shaded bitmap, in view
	//coordinates. None of it touches the cache, so a selection change or a
	//label toggle costs a redraw and not a re-shade.
	//Rebuilt only when the layout changed, and never in the middle of a drag -
	//a live resize replays the last one stretched, the way the bitmap under it
	//is stretched.
	if ( !_overlayValid && ![self inLiveResize] )
		[self buildOverlay];

	[self drawOverlay];

	[self drawSelectionOutline];
}

#pragma mark --------the overlay-----------------

//Everything painted over the shaded bitmap - the plain cells, the gutters
//between the top-level groups and the labels on large cells - is geometry that
//only changes when the layout does. Working it out inside -drawRect: meant
//walking the whole renderer tree, converting every cell rect out of backing
//coordinates and measuring every candidate label, on every single frame.
//Measured on a 37,449-node tree that was 7.2ms per redraw against 1.2ms for
//the bare bitmap blit - seven times the cost of the thing it decorates, repeated
//for every frame of a window drag.
//
//So it is computed once per layout and replayed. The selection outline is not
//part of it: it changes on its own schedule and is a single rectangle.
- (void) invalidateOverlay
{
	_overlayValid = NO;
}

- (void) buildOverlay
{
	if ( _overlayPlainCells == nil )
	{
		_overlayPlainCells = [NSMutableArray array];
		_overlayGutters = [NSMutableArray array];
		_overlayLabels = [NSMutableArray array];
	}

	[_overlayPlainCells removeAllObjects];
	[_overlayGutters removeAllObjects];
	[_overlayLabels removeAllObjects];

	//The size the geometry below is expressed in. A live resize replays it
	//scaled to the new bounds rather than rebuilding, exactly as the cached
	//bitmap underneath is stretched rather than re-shaded.
	_overlayLayoutSize = [self bounds].size;
	_overlayValid = YES;

	_mergedItemCount = 0;
	_mergedItemWeight = 0;

	if ( _rootItemRenderer != nil )
	{
		[self collectPlainCellsForRenderer: _rootItemRenderer];
		[self collectGutters];

		if ( _drawsCellLabels )
			[self collectLabelsForRenderer: _rootItemRenderer claimedRects: [NSMutableArray array]];
	}

	//Posted even when nothing was merged, because going from some to none is
	//exactly what an observer showing the figure needs to hear.
	//
	//Deferred a run-loop turn, and coalesced. The overlay is built from inside
	//-drawRect:, and an observer of this is going to put the numbers on screen -
	//so posting it synchronously would have a view mutating its siblings in the
	//middle of a display pass. The figures it describes are ivars and stay put
	//until the next layout, so reading them one turn later reads the same thing.
	if ( !_layoutChangePostPending )
	{
		_layoutChangePostPending = YES;

		__weak TreeMapView *weakSelf = self;

		dispatch_async( dispatch_get_main_queue(), ^{
			TreeMapView *strongSelf = weakSelf;

			if ( strongSelf == nil )
				return;

			strongSelf->_layoutChangePostPending = NO;

			[[NSNotificationCenter defaultCenter]
				postNotificationName: TreeMapViewLayoutChangedNotification object: strongSelf];
		} );
	}
}

- (NSUInteger) mergedItemCount
{
	return _mergedItemCount;
}

- (unsigned long long) mergedItemWeight
{
	return _mergedItemWeight;
}

//Free space and space used outside the scanned folder. They are skipped by the
//bitmap pass, so the overlay is the only thing that paints them.
- (void) collectPlainCellsForRenderer: (TMVItem*) renderer
{
	const TMVCellStyle style = [renderer cellStyle];

	if ( style != TMVCellStyleCushion )
	{
		const NSRect rect = [self itemRectByCellId: renderer];

		if ( !NSIsEmptyRect(rect) )
		{
			TMVOverlayItem *item = [[TMVOverlayItem alloc] init];

			[item setRect: rect];
			[item setFill: [renderer fillColor]];

			if ( style == TMVCellStyleRemainder )
			{
				//The hatch is the whole signal: it says "this is a group, not a
				//file", and no real file may ever be drawn with it. Diagonal
				//because every other line in the map is axis-aligned, so it
				//cannot be mistaken for a cell edge.
				_mergedItemCount += [[renderer mergedItems] count];
				_mergedItemWeight += [renderer weight];

				const CGFloat shortSide = MIN( NSWidth( rect ), NSHeight( rect ) );
				const BOOL hatched = ( shortSide >= TMVMinimumHatchedCellSize );

				[item setHatched: hatched];

				//A remainder's fill is the dominant kind lightened, so that a
				//block of them reads as a group rather than as a file. On a
				//sliver that backfires: with no room for the hatch, a pale tint a
				//few points wide is just a light line ruled across the map - and
				//where the dominant kind is one of the greys, a white one. Below
				//the hatch it takes the darker step instead, which reads as an
				//ordinary thin cell.
				if ( !hatched )
					[item setFill: [renderer outlineColor]];

				//The colour is set either way - the hatch draws with it too - and
				//an empty outline rect is what says "no border".
				[item setOutline: [renderer outlineColor]];

				//half the line width in, so the stroke lands inside the cell
				//rather than straddling its edge and bleeding onto the neighbour
				if ( shortSide >= TMVMinimumOutlinedCellSize )
					[item setOutlineRect: NSInsetRect( rect, 0.5, 0.5 )];
			}
			else if ( style == TMVCellStyleOutlined )
			{
				//Pulled inside the gutter, not just inside the cell. The gutter
				//is stroked along the cell's boundary and covers half its width
				//on either side of it, so an outline drawn at the boundary is
				//painted over and vanishes. The half-point on top of that puts
				//a 1pt line on one row of pixels instead of straddling two.
				const CGFloat gutterInset = ( [renderer depth] == 1 ) ? _gutterWidth / 2.0 : 0.0;
				const CGFloat inset = gutterInset + 0.5;

				const NSRect outlineRect = NSInsetRect( rect, inset, inset );

				if ( !NSIsEmptyRect( outlineRect ) )
				{
					[item setOutlineRect: outlineRect];
					[item setOutline: [renderer outlineColor]];
				}
			}

			[_overlayPlainCells addObject: item];
		}

		//a plain cell has nothing drawn inside it
		return;
	}

	for ( TMVItem *child in [renderer childEnumerator] )
		[self collectPlainCellsForRenderer: child];
}

//The boundaries of the top-level groups, painted as gaps. Stroking the outline
//of each cell puts half the width either side of a shared edge, which is what
//makes neighbouring groups separate by the full gutter.
//Below this a cell cannot give up a separator without most of it going: the
//gutter is stroked on the boundary, so it takes half its width from each side.
static const CGFloat TMVMinimumSeparatedCellSize = 6.0;

//One width at every depth - see -collectGuttersForRenderer:. A hairline rather
//than the design's 2px because the design's cells are all large: 2pt taken off
//every side of a 12pt cell is a third of it, and a cell drawn a third smaller
//than its size misrepresents the one thing the map is for.
static const CGFloat TMVCellSeparatorWidth = 1.0;

//The design puts a gap between every pair of cells, not only between the
//top-level groups, and it is what makes a dense map readable - cushion shading
//alone leaves two same-coloured neighbours running together.
//
//**One width for every depth.** Giving the top level a heavier line, which is
//what the README describes and what this did first, produces exactly what the
//design does not have: some edges bolder than others, and worse, boldest where a
//group's edge and an inner cell's edge fall on the same coordinates and both get
//stroked. The design's markup is `gap: 2px` at every level and the gaps are
//uniform.
//
//Snapped to whole backing pixels, and that is not cosmetic either: an unsnapped
//stroke lands across two pixel columns and is drawn as two half-covered ones,
//so identical lines come out looking different weights depending on where the
//layout happened to put them.
//
//Stroked over the cushions, never inset into the layout. A fixed inset takes
//proportionally more area from a thin cell than from a square one, so insetting
//would break area-proportional-to-weight; drawing over changes no rect, and hit
//testing still treats the gap as part of the cell.
- (NSRect) pixelAlignedRect: (NSRect) rect
{
	const CGFloat scale = [[self window] backingScaleFactor] > 0.0
		? [[self window] backingScaleFactor] : 1.0;

	//round the edges to pixel boundaries, then put the stroke's centre half a
	//line width in so it covers whole pixels rather than straddling them
	const CGFloat minX = round( NSMinX(rect) * scale ) / scale;
	const CGFloat minY = round( NSMinY(rect) * scale ) / scale;
	const CGFloat maxX = round( NSMaxX(rect) * scale ) / scale;
	const CGFloat maxY = round( NSMaxY(rect) * scale ) / scale;

	const CGFloat half = ( TMVCellSeparatorWidth / 2.0 );

	return NSMakeRect( minX + half, minY + half,
					   MAX( 0.0, maxX - minX - TMVCellSeparatorWidth ),
					   MAX( 0.0, maxY - minY - TMVCellSeparatorWidth ) );
}

- (void) collectGuttersForRenderer: (TMVItem*) renderer
{
	if ( [renderer depth] > 0 )
	{
		const NSRect rect = [self itemRectByCellId: renderer];
		const CGFloat shortSide = MIN( NSWidth( rect ), NSHeight( rect ) );

		if ( !NSIsEmptyRect( rect ) && shortSide >= TMVMinimumSeparatedCellSize )
		{
			TMVOverlayItem *item = [[TMVOverlayItem alloc] init];

			[item setRect: [self pixelAlignedRect: rect]];

			[_overlayGutters addObject: item];
		}
	}

	for ( TMVItem *child in [renderer childEnumerator] )
		[self collectGuttersForRenderer: child];
}

- (void) collectGutters
{
	//The original drew cell to cell with nothing between them: the cushion was
	//the boundary. Separating the cells as well would be the modern map with an
	//old light model, which is not what the setting offers.
	if ( _gutterWidth <= 0.0 || _usesClassicCushions )
		return;

	[self collectGuttersForRenderer: _rootItemRenderer];
}

//Margin between a label and its cell's top-left corner, and the type size.
static const CGFloat TMVCellLabelInset    = 8.0;
static const CGFloat TMVCellLabelFontSize = 11.0;

- (NSDictionary*) cellLabelAttributesInColor: (NSColor*) color
{
	if ( color == nil )
		color = ( _cellLabelColor != nil ) ? _cellLabelColor : [NSColor labelColor];

	return @{
		NSFontAttributeName: [NSFont systemFontOfSize: TMVCellLabelFontSize
												weight: NSFontWeightSemibold],
		NSForegroundColorAttributeName: color,
	};
}

- (NSDictionary*) cellLabelAttributes
{
	return [self cellLabelAttributesInColor: nil];
}

//Labels go on the top-level groups and on cells with nothing drawn inside
//them - labelling every level would write a name into every nested cell.
//
//That alone is not enough. A group and its largest child share a top-left
//corner, so their labels land on exactly the same pixels and render as
//unreadable overstrike ("DerivedData" over "Build"). So each label that is
//placed claims its rectangle, and a later one that would overlap is dropped.
//The walk is depth first and parents come first, which means the outer cell
//keeps its name and the child inside it gives way - the right way round, since
//the outer name is the one that orients you.
- (void) collectLabelsForRenderer: (TMVItem*) renderer claimedRects: (NSMutableArray<NSValue*>*) claimed
{
	const NSInteger depth = [renderer depth];

	//A remainder always tries for a label whatever its depth: it is the only
	//thing telling you those items exist at all.
	if ( depth > 0 && ( depth == 1 || [renderer childCount] == 0 || [renderer isRemainder] ) )
		[self collectLabelForRenderer: renderer claimedRects: claimed];

	for ( TMVItem *child in [renderer childEnumerator] )
		[self collectLabelsForRenderer: child claimedRects: claimed];
}

- (void) collectLabelForRenderer: (TMVItem*) renderer claimedRects: (NSMutableArray<NSValue*>*) claimed
{
	if ( ![delegate respondsToSelector: @selector(treeMapView:labelForItem:)] )
		return;

	const NSRect rect = [self itemRectByCellId: renderer];

	//cheap rejection before asking the delegate for strings, since this runs
	//over every drawn cell
	if ( NSWidth(rect) < TMVCellLabelInset * 2.0
		 || NSHeight(rect) < TMVCellLabelInset * 2.0 )
		return;

	NSString *name = nil;
	NSString *detail = nil;

	if ( [renderer isRemainder] )
	{
		if ( ![delegate respondsToSelector: @selector(treeMapView:labelForRemainderItems:)] )
			return;

		name = [delegate treeMapView: self labelForRemainderItems: [renderer mergedItems]];

		if ( [delegate respondsToSelector: @selector(treeMapView:detailLabelForRemainderItems:)] )
			detail = [delegate treeMapView: self detailLabelForRemainderItems: [renderer mergedItems]];
	}
	else
	{
		name = [delegate treeMapView: self labelForItem: [renderer item]];

		if ( [delegate respondsToSelector: @selector(treeMapView:detailLabelForItem:)] )
			detail = [delegate treeMapView: self detailLabelForItem: [renderer item]];
	}

	if ( [name length] == 0 )
		return;

	//A cell that carries its own label colour also gets its own layout: the two
	//synthetic cells sit their name over their size at the *bottom* left, which
	//is where the design puts them and what keeps them from being read as a file
	//name with a size after it.
	const BOOL isSpecialCell = ( [renderer labelColor] != nil );

	NSDictionary *attributes = [self cellLabelAttributesInColor: [renderer labelColor]];

	//"name · size" when it fits, the name alone when it does not, and nothing
	//at all when even that would be clipped - a truncated name in the middle of
	//a coloured tile reads as a rendering fault rather than as a label
	NSString *text = name;

	if ( [detail length] > 0 )
	{
		//A remainder's two lines stack, and so do the synthetic cells'; a file's
		//name and size sit on one.
		NSString *both = ( [renderer isRemainder] || isSpecialCell )
			? [NSString stringWithFormat: @"%@\n%@", name, detail]
			: [NSString stringWithFormat: @"%@ · %@", name, detail];

		if ( [self text: both fitsInRect: rect withAttributes: attributes] )
			text = both;
	}

	if ( ![self text: text fitsInRect: rect withAttributes: attributes] )
		return;

	const NSSize size = [text sizeWithAttributes: attributes];

	//the view is flipped, so the cell's top edge is its minimum y and its bottom
	//edge its maximum
	const NSPoint origin = isSpecialCell
		? NSMakePoint( NSMinX(rect) + TMVCellLabelInset,
					   NSMaxY(rect) - TMVCellLabelInset - size.height )
		: NSMakePoint( NSMinX(rect) + TMVCellLabelInset,
					   NSMinY(rect) + TMVCellLabelInset );
	const NSRect textRect = NSMakeRect( origin.x, origin.y, size.width, size.height );

	for ( NSValue *value in claimed )
	{
		if ( NSIntersectsRect( textRect, [value rectValue] ) )
			return;
	}

	[claimed addObject: [NSValue valueWithRect: textRect]];

	TMVOverlayItem *item = [[TMVOverlayItem alloc] init];
	[item setRect: textRect];

	//Attributed once here rather than per frame. -drawAtPoint:withAttributes:
	//builds one of these internally on every call, and there can be hundreds
	//of labels on a full map.
	[item setText: [[NSAttributedString alloc] initWithString: text attributes: attributes]];

	[_overlayLabels addObject: item];
}

- (BOOL) text: (NSString*) text fitsInRect: (NSRect) rect withAttributes: (NSDictionary*) attributes
{
	const NSSize size = [text sizeWithAttributes: attributes];

	return ( size.width  + TMVCellLabelInset * 2.0 ) <= NSWidth(rect)
		&& ( size.height + TMVCellLabelInset * 2.0 ) <= NSHeight(rect);
}

#pragma mark --------replaying the overlay-----------------

//During a live resize the bitmap underneath is stretched rather than re-shaded,
//so the overlay is stretched with it by the same factor. Rebuilding it every
//frame of a drag is what this whole arrangement exists to avoid, and drawing
//it unscaled over a stretched bitmap would put every gutter in the wrong place.
- (NSRect) overlayRect: (NSRect) rect scaledBy: (NSSize) scale
{
	if ( scale.width == 1.0 && scale.height == 1.0 )
		return rect;

	return NSMakeRect( NSMinX(rect) * scale.width, NSMinY(rect) * scale.height,
					   NSWidth(rect) * scale.width, NSHeight(rect) * scale.height );
}

- (NSSize) overlayScale
{
	if ( _overlayLayoutSize.width <= 0.0 || _overlayLayoutSize.height <= 0.0 )
		return NSMakeSize( 1.0, 1.0 );

	return NSMakeSize( NSWidth( [self bounds] )  / _overlayLayoutSize.width,
					   NSHeight( [self bounds] ) / _overlayLayoutSize.height );
}

- (void) drawOverlay
{
	const NSSize scale = [self overlayScale];

	for ( TMVOverlayItem *item in _overlayPlainCells )
	{
		if ( [item fill] != nil )
		{
			[[item fill] set];
			NSRectFill( [self overlayRect: [item rect] scaledBy: scale] );
		}

		if ( [item hatched] )
			[self drawHatchInRect: [self overlayRect: [item rect] scaledBy: scale]
							color: [item outline]];

		if ( [item outline] != nil && !NSIsEmptyRect( [item outlineRect] ) )
		{
			NSBezierPath *path = [NSBezierPath bezierPathWithRect:
				[self overlayRect: [item outlineRect] scaledBy: scale]];

			if ( [item hatched] )
			{
				//A hairline, one step darker than the fill. 2pt was the first
				//try, and where the design shows one remainder a real scan has
				//hundreds - at that count a 2pt border stops reading as an edge
				//and becomes the thing you see instead of the map.
				[path setLineWidth: 1.0];
			}
			else
			{
				const CGFloat pattern[] = { 4.0, 3.0 };
				[path setLineDash: pattern count: 2 phase: 0.0];
				[path setLineWidth: 1.0];
			}

			[[item outline] set];
			[path stroke];
		}
	}

	if ( [_overlayGutters count] > 0 && _gutterColor != nil )
	{
		//One path for the whole map, not one per cell. Now that every cell is
		//separated and not just the top-level groups there are thousands of
		//these, and a path object plus a -stroke each costs more than the rest of
		//the overlay put together - 24.1 ms a redraw against 15.7 ms, on a tree
		//this pass exists to keep off the per-frame path.
		NSBezierPath *edges = [NSBezierPath bezierPath];

		for ( TMVOverlayItem *item in _overlayGutters )
			[edges appendBezierPathWithRect: [self overlayRect: [item rect] scaledBy: scale]];

		[_gutterColor set];

		[edges setLineWidth: TMVCellSeparatorWidth];
		[edges stroke];
	}

	for ( TMVOverlayItem *item in _overlayLabels )
	{
		//the text keeps its size while a drag is in flight; only where it sits
		//follows the stretch
		const NSRect rect = [self overlayRect: [item rect] scaledBy: scale];

		[[item text] drawAtPoint: NSMakePoint( NSMinX(rect), NSMinY(rect) )];
	}
}

//45 degrees, 6pt apart, clipped to the cell. Drawn rather than tiled with a
//pattern image because the stripes must not shift when the cell moves - a
//pattern is anchored to the view, so a remainder that changed size between
//layouts would appear to slide underneath its own border.
- (void) drawHatchInRect: (NSRect) rect color: (NSColor*) color
{
	if ( color == nil || NSIsEmptyRect( rect ) )
		return;

	[NSGraphicsContext saveGraphicsState];
	[NSBezierPath clipRect: rect];

	NSBezierPath *hatch = [NSBezierPath bezierPath];
	[hatch setLineWidth: 1.0];

	const CGFloat spacing = 6.0;
	const CGFloat extent = NSWidth( rect ) + NSHeight( rect );

	for ( CGFloat offset = 0.0; offset <= extent; offset += spacing )
	{
		[hatch moveToPoint: NSMakePoint( NSMinX(rect) + offset, NSMinY(rect) )];
		[hatch lineToPoint: NSMakePoint( NSMinX(rect) + offset - NSHeight(rect),
										 NSMaxY(rect) )];
	}

	[[color colorWithAlphaComponent: 0.55] set];
	[hatch stroke];

	[NSGraphicsContext restoreGraphicsState];
}

- (void) drawSelectionOutline
{
	if ( _selectedRenderer == nil || _selectionColor == nil )
		return;

	//Scaled like the overlay: during a live resize the layout underneath is
	//stale, so an unscaled cell rect puts the outline somewhere the cell is not
	//- far outside the view once the window has shrunk much at all.
	const NSRect selectionRect = [self overlayRect: [self itemRectByCellId: _selectedRenderer]
										  scaledBy: [self overlayScale]];

	if ( NSIsEmptyRect(selectionRect) )
		return;

	//Inset by half the line width so the whole stroke lands inside the cell:
	//the outline marks the selection without covering a neighbour, and the cell
	//keeps its kind colour rather than being recoloured to show selection.
	const CGFloat width = 2.0;

	NSRect frame = NSInsetRect( selectionRect, width / 2.0, width / 2.0 );

	//a cell can be a single point wide, and an inset rect can invert
	if ( NSIsEmptyRect(frame) )
		frame = selectionRect;

	NSBezierPath *path = [NSBezierPath bezierPathWithRect: frame];
	[path setLineWidth: width];

	[_selectionColor set];
	[path stroke];
}

//Nothing else in the application overrides this, and until now nothing needed
//to: every other colour comes from the asset catalog and follows the appearance
//on its own. The shaded bitmap does not - it is pixels, baked with whichever
//constants were current when it was built - so switching appearance with a
//window open left light-mode cushions on a dark ground until something else
//happened to invalidate the cache.
- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];

	[self invalidateCanvasCache];
	[self invalidateOverlay];
	[self setNeedsDisplay: YES];
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

- (TMVCellId) selectedCellId
{
	return _selectedRenderer;
}

//Searched from the root rather than read from a back-pointer. A renderer has no
//parent pointer, and adding one would put a second reference on every cell in a
//tree that runs to tens of thousands of them, to be maintained correctly on
//every layout - for something only a click needs, and only on the one cell in a
//parent that can be a remainder.
static TMVItem* ParentOfRenderer( TMVItem *root, TMVItem *target )
{
	for ( TMVItem *child in [root childEnumerator] )
	{
		if ( child == target )
			return root;

		TMVItem *found = ParentOfRenderer( child, target );

		if ( found != nil )
			return found;
	}

	return nil;
}

- (id) enclosingItemByCellId: (TMVCellId) cellId
{
	TMVItem *renderer = (TMVItem*) cellId;

	//In practice this steps at most once - a remainder is the only kind of cell
	//without an item of its own, and its parent always has one - but it is
	//written as a walk so that a second itemless cell type would not need it
	//rewritten.
	while ( renderer != nil && [renderer item] == nil )
		renderer = ParentOfRenderer( _rootItemRenderer, renderer );

	return [renderer item];
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

	//Reported on the second mouse-up rather than on the second mouse-down, so
	//the selection notification the first click posted has already been through
	//the delegate. The single-click behaviour is not suppressed while AppKit
	//waits to see whether a double follows: a double click here is a zoom into
	//what was just selected, so doing the selection twice is harmless.
	if ( [event clickCount] == 2
		 && [delegate respondsToSelector: @selector(treeMapView:doubleClickedCellId:)] )
		[delegate treeMapView: self doubleClickedCellId: _selectedRenderer];
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

	//Three cases, and an observer has to be able to tell them apart:
	//
	//  nothing at all      the pointer is off the map
	//  a cell, no item     a cell that stands for no single data item - a
	//                      remainder, which is exactly the thing worth naming
	//  a cell and an item  the ordinary case
	//
	//Before the remainder cells existed the second case could not arise, so the
	//cell was left out and the empty dictionary meant "off the map". A
	//remainder then reported as nothing under the pointer, and hovering one
	//cleared the status bar instead of describing it.
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];

	if ( _touchedRenderer != nil )
	{
		[userInfo setObject: _touchedRenderer forKey: TMVTouchedCell];

		if ( [_touchedRenderer item] != nil )
			[userInfo setObject: [_touchedRenderer item] forKey: TMVTouchedItem];
	}

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
