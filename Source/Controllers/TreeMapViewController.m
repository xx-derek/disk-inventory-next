//
//  FSItem.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on Mon Sep 29 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "TreeMapViewController.h"
#import <TreeMapView/TreeMapView.h>
#import "MainWindowController.h"
#import "FileSizeFormatter.h"
#import "FSItem-Utilities.h"
#import "DIXTheme.h"
#import "DIXStatusBarView.h"

@interface TreeMapViewController(Private)

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context;
- (void) onDocumentSelectionChanged;
- (void) reloadData;

@end

@interface TreeMapViewController()
- (void) applyTreeMapAppearance;
- (NSColor*) dominantKindColorForItems: (NSArray*) items;
- (NSString*) dominantKindForItems: (NSArray*) items;
- (void) reportRemainder: (TMVItem*) cell inStatusBar: (DIXStatusBarView*) statusBar;
@end

@implementation TreeMapViewController

- (void) awakeFromNib
{
	FileSystemDoc *doc = [self document];
	
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	
    [notificationCenter addObserver: self
						   selector: @selector(zoomedItemChanged:)
							   name: ZoomedItemChangedNotification
							 object: doc];
	
    [notificationCenter addObserver: self
						   selector: @selector(viewOptionChanged:)
							   name: ViewOptionChangedNotification
							 object: doc];
	
    [notificationCenter addObserver: self
						   selector: @selector(itemsChanged:)
							   name: FSItemsChangedNotification
							 object: doc];

    [notificationCenter addObserver: self
						   selector: @selector(focusedPileChanged:)
							   name: FocusedPileChangedNotification
							 object: doc];
	
    [notificationCenter addObserver: self
						   selector: @selector(windowWillClose:)
							   name: NSWindowWillCloseNotification
							 object: [_treeMapView window]];
	
    [_fileNameTextField setStringValue: @""];
    [_fileSizeTextField setStringValue: @""];
	
	//set up KVO
	[doc addObserver: self forKeyPath: DocKeySelectedItem options: NSKeyValueObservingOptionNew context: nil];
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver: self
															  forKeyPath: [@"values." stringByAppendingString: ShareKindColors]
																 options: 0
																 context: (__bridge void*) ShareKindColors];

	[[NSUserDefaultsController sharedUserDefaultsController] addObserver: self
															  forKeyPath: [@"values." stringByAppendingString: LabelLargeCells]
																 options: 0
																 context: (__bridge void*) LabelLargeCells];

	[[NSUserDefaultsController sharedUserDefaultsController] addObserver: self
															  forKeyPath: [@"values." stringByAppendingString: ClassicCushions]
																 options: 0
																 context: (__bridge void*) ClassicCushions];

	//The widget knows nothing about the application's palette, so the colours
	//it draws over the cushions come from here.
	[self applyTreeMapAppearance];

	//create "free space" and "other space" items
	//(don't use [self rootItem] as we want the root, not the zoomed item)
	FSItem *rootItem =  [[self document] rootItem];
	
	_otherSpaceItem = [[FSItem alloc] initAsOtherSpaceItemForParent: rootItem];
	_freeSpaceItem = [[FSItem alloc] initAsFreeSpaceItemForParent: rootItem];
	
	[self reloadData];
}


- (FileSystemDoc*) document
{
    if ( _document == nil && _treeMapView != nil )
        _document = [MainWindowController documentForView: _treeMapView];

    return _document;
}

- (FSItem*) rootItem
{
    return [[self document] zoomedItem];
}

//The items a merged cell stood for, while one is open, or nil. The map lays
//these out as its whole content: that is what gives them the room they did not
//have beside their larger siblings, and it is the only way "zoom in" can mean
//anything for a pile of items that are not folders. See -focusedPile.
- (NSArray*) focusedPile
{
    return [[self document] focusedPile];
}

#pragma mark --------TreeMapView data source-----------------

- (id) treeMapView: (TreeMapView*) view child: (NSUInteger) index ofItem: (id) item
{
    //nil is the root, the way NSOutlineView addresses it
    if ( item == nil && [self focusedPile] != nil )
        return [[self focusedPile] objectAtIndex: index];

    FSItem *fsItem = ( item == nil ? [self rootItem] : item );
	
	if ( fsItem == [self rootItem]
		 && index >= [fsItem childCount] )
	{
		if ( ( index - [fsItem childCount] ) == 0 )
			return [[self document] showOtherSpace] ? _otherSpaceItem : _freeSpaceItem;
		else
			return _freeSpaceItem;
	}
	else
		return [fsItem childAtIndex: index];
}

- (BOOL) treeMapView: (TreeMapView*) view isNode: (id) item
{
    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

    return ![fsItem isSpecialItem] && [[self document] itemIsNode: fsItem];
}

- (NSUInteger) treeMapView: (TreeMapView*) view numberOfChildrenOfItem: (id) item
{
    if ( item == nil && [self focusedPile] != nil )
        return [[self focusedPile] count];

    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

    NSUInteger childCount = [fsItem childCount];
	
	//items representing other space and free space
	if ( fsItem == [self rootItem] )
	{
		FileSystemDoc *doc = [self document];
		if ( [doc showFreeSpace] )
			childCount ++;
		if ( [doc showOtherSpace] )
			childCount ++;
	}
	
	return childCount;
}

- (unsigned long long) treeMapView: (TreeMapView*) view weightByItem: (id) item
{
    //The root's weight has to be the pile's total, or the cells would be laid
    //out as a fraction of a whole they are no longer part of.
    if ( item == nil && [self focusedPile] != nil )
    {
        unsigned long long total = 0;

        for ( FSItem *pileItem in [self focusedPile] )
            total += [pileItem sizeValue];

        return total;
    }

    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

	unsigned long long size = [fsItem sizeValue];
	
	//add sizes of items representing other space and free space
	if ( fsItem == [self rootItem] )
	{
		FileSystemDoc *doc = [self document];
		if ( [doc showFreeSpace] )
			size += [_freeSpaceItem sizeValue];
		if ( [doc showOtherSpace] )
			size += [_otherSpaceItem sizeValue];
	}
	
    return size;
}

#pragma mark --------TreeMapView delegates-----------------

- (NSString*) treeMapView: (TreeMapView*) view getToolTipByItem: (id) item
{
    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

    return [fsItem displayName];
}

- (void) treeMapView: (TreeMapView*) view willDisplayItem: (id) item withRenderer: (TMVItem*) renderer
{
    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

	switch ( [fsItem type] )
	{
		case FileFolderItem:
			[renderer setCellStyle: TMVCellStyleCushion];
			[renderer setCushionColor: [self cellColorForItem: fsItem]];
			break;

		//The two synthetic cells are deliberately neutral, so they read as "not
		//a file kind" against a palette that is entirely coloured. They are also
		//drawn plain rather than shaded: a cushion is what says "this is a file",
		//and giving free space one made it look like the largest file on the
		//disk.
		//Both carry their own label colour. The cushions stay light in either
		//appearance so one dark ink serves all of them, but these two do not:
		//free space is the darkest thing on a dark map, and dark ink on it is
		//invisible. Setting the colour is also what tells the view to lay their
		//labels out the way the design does, at the bottom left over two lines.
		case FreeSpaceItem:
			//an absence, not a tile: a pale fill inside a dashed outline
			[renderer setCellStyle: TMVCellStyleOutlined];
			[renderer setCushionColor: [DIXTheme freeSpaceFill]];
			[renderer setOutlineColor: [DIXTheme freeSpaceDash]];
			[renderer setLabelColor: [DIXTheme secondaryText]];
			break;

		case OtherSpaceItem:
			[renderer setCellStyle: TMVCellStyleFlat];
			[renderer setCushionColor: [DIXTheme neutralFill]];
			//a mid grey in both appearances, so the label has to invert with the
			//appearance rather than pick a side
			[renderer setLabelColor: [DIXTheme ink]];
			break;
	}
}

//A kind filter dims what it excludes rather than removing it. Removing would
//mean relaying out the map, so every cell would move and the totals along the
//bottom would stop describing what is drawn - and the one thing this window is
//built around is that a cell's area is its size. Dimming leaves every rectangle
//where it was and lets the filtered kind be the only colour on it, which is what
//makes the legend a filter rather than a highlighter.
- (NSColor*) cellColorForItem: (FSItem*) fsItem
{
	FileSystemDoc *doc = [self document];
	NSColor *kindColor = [[doc fileTypeColors] colorForItem: fsItem];

	if ( [doc kindFilter] == nil || [doc itemPassesKindFilter: fsItem] )
		return kindColor;

	//Toward the neutral tile rather than toward grey: that is already the colour
	//this map uses for "not a file kind", so an excluded cell reads as being of
	//the same nothing-in-particular.
	return [kindColor blendedColorWithFraction: 0.86 ofColor: [DIXTheme neutralFill]];
}

#pragma mark --------remainder cells-----------------

//A remainder's fill: the dominant kind moved toward a light neutral, so a block
//of them reads as a group and not as one big file - with a cap on how light the
//result may be.
//
//The cap is the point. The twelve-colour palette runs out and everything past
//it gets a pale grey ramp, which is what most remainders end up mostly made of;
//lightening one of those produced a white block, and where the cell was thin, a
//white line ruled across the map. Blending toward a *light neutral* rather than
//toward white also means a kind that is already paler than the target gets
//darker instead of lighter, which is the right direction for exactly those greys.
static const CGFloat TMVRemainderNeutral       = 0.86;
static const CGFloat TMVRemainderMaxBrightness = 0.82;

static NSColor* RemainderFillColor( NSColor *kindColor )
{
	NSColor *tint = [kindColor blendedColorWithFraction: 0.45
											   ofColor: [NSColor colorWithWhite: TMVRemainderNeutral
																		  alpha: 1.0]];

	NSColor *rgb = [tint colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];

	if ( rgb == nil )
		return tint;

	CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0, alpha = 1.0;

	[rgb getHue: &hue saturation: &saturation brightness: &brightness alpha: &alpha];

	if ( brightness <= TMVRemainderMaxBrightness )
		return tint;

	return [NSColor colorWithHue: hue
					  saturation: saturation
					  brightness: TMVRemainderMaxBrightness
						   alpha: alpha];
}

//The dominant kind decides the tint, so a remainder reads as "mostly this" and
//keeps the sidebar legend's promise that a colour means a kind. Lightened,
//because it is a group rather than a file and must not be mistaken for one.
- (void) treeMapView: (TreeMapView*) view
	willDisplayRemainderItems: (NSArray*) items
				 withRenderer: (TMVItem*) renderer
{
	NSColor *kindColor = [self dominantKindColorForItems: items];

	//Both derived from the kind colour and from nothing else, so they are the
	//same in either appearance - which is what the rest of the map does, kind
	//colours being data. Blending toward DIXTheme's surface and ink instead, as
	//this did first, went wrong twice over: -blendedColorWithFraction: resolves
	//its operands there and then, so the pair was frozen at whichever appearance
	//built the cell; and ink *inverts* to near-white in dark, so the border meant
	//to be a step darker came out a step lighter. A dense scan was laced with
	//white lines, and thin remainders were nothing but border.
	//
	//Resolving a colour is safe *here*, unlike there: a kind colour is data and
	//is the same in both appearances, so there is nothing to freeze.
	[renderer setCushionColor: RemainderFillColor( kindColor )];

	//the hatch and the border, one step darker than the fill
	[renderer setOutlineColor: [kindColor blendedColorWithFraction: 0.30
														   ofColor: [NSColor blackColor]]];
}

- (NSColor*) dominantKindColorForItems: (NSArray*) items
{
	NSString *kind = [self dominantKindForItems: items];

	if ( kind == nil )
		return [DIXTheme neutralFill];

	return [[[self document] fileTypeColors] colorForKind: kind];
}

//By size, not by count: the cell's area is bytes, so the kind that names it
//should be the one those bytes mostly are.
- (NSString*) dominantKindForItems: (NSArray*) items
{
	NSMutableDictionary<NSString*, NSNumber*> *sizeByKind = [NSMutableDictionary dictionary];

	for ( FSItem *item in items )
	{
		NSString *kind = [item kindName];

		if ( [kind length] == 0 )
			continue;

		const unsigned long long running =
			[[sizeByKind objectForKey: kind] unsignedLongLongValue] + [item sizeValue];

		[sizeByKind setObject: @(running) forKey: kind];
	}

	__block NSString *dominant = nil;
	__block unsigned long long best = 0;

	[sizeByKind enumerateKeysAndObjectsUsingBlock: ^( NSString *kind, NSNumber *size, BOOL *stop )
	{
		if ( [size unsignedLongLongValue] > best )
		{
			best = [size unsignedLongLongValue];
			dominant = kind;
		}
	}];

	return dominant;
}

- (NSString*) treeMapView: (TreeMapView*) view labelForRemainderItems: (NSArray*) items
{
	NSNumberFormatter *counts = [[NSNumberFormatter alloc] init];
	[counts setNumberStyle: NSNumberFormatterDecimalStyle];

	return [NSString stringWithFormat:
		NSLocalizedString( @"%@ smaller items", @"treemap, a merged remainder cell" ),
		[counts stringFromNumber: @([items count])]];
}

- (NSString*) treeMapView: (TreeMapView*) view detailLabelForRemainderItems: (NSArray*) items
{
	unsigned long long total = 0;
	for ( FSItem *item in items )
		total += [item sizeValue];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
	NSString *size = [sizeFormatter stringForObjectValue: @(total)];

	NSString *kind = [self dominantKindForItems: items];

	if ( kind == nil )
		return size;

	return [NSString stringWithFormat:
		NSLocalizedString( @"%@ · mostly %@", @"treemap, a merged remainder cell's detail" ),
		size, kind];
}

//The share of the whole scan, as the design writes it: one decimal place.
//NSNumberFormatterPercentStyle rounds to whole percent by default, which turned
//13.96% into "14%" and every small file into "0%" - a figure that says nothing
//about the thing it is describing.
static NSString* ShareOfScanString( unsigned long long part, unsigned long long whole )
{
	if ( whole == 0 )
		return nil;

	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];

	[formatter setNumberStyle: NSNumberFormatterPercentStyle];
	[formatter setMaximumFractionDigits: 1];

	return [formatter stringFromNumber: @( (double) part / whole )];
}

//The same three figures an ordinary cell reports - size, share of the scan,
//what it is - for a thing that has no name of its own.
- (void) reportRemainder: (TMVItem*) cell inStatusBar: (DIXStatusBarView*) statusBar
{
	if ( statusBar == nil )
		return;

	NSArray *items = [cell mergedItems];

	unsigned long long total = 0;
	for ( FSItem *item in items )
		total += [item sizeValue];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	NSMutableString *detail =
		[NSMutableString stringWithString: [sizeFormatter stringForObjectValue: @(total)]];

	//share of the whole scan, not of the folder it sits in - the same question
	//the readout answers for every other cell
	const unsigned long long scanSize =
		[[[[self document] rootItem] size] unsignedLongLongValue];

	NSString *share = ShareOfScanString( total, scanSize );

	if ( share != nil )
		[detail appendFormat: @" · %@", share];

	NSString *kind = [self dominantKindForItems: items];

	if ( kind != nil )
	{
		[detail appendFormat: NSLocalizedString( @" · mostly %@",
												 @"status bar, what a merged cell is mostly made of" ),
			kind];
	}

	[statusBar setItemName: [self treeMapView: _treeMapView labelForRemainderItems: items]
					detail: detail
				 kindColor: [self dominantKindColorForItems: items]];
}

#pragma mark --------cell labels-----------------

- (NSString*) treeMapView: (TreeMapView*) view labelForItem: (id) item
{
    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

	return [fsItem displayName];
}

- (NSString*) treeMapView: (TreeMapView*) view detailLabelForItem: (id) item
{
    FSItem *fsItem = ( item == nil ? [self rootItem] : item );

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	return [sizeFormatter stringForObjectValue: [fsItem size]];
}

//Colours and toggles the widget cannot know about on its own. Called at set-up
//and again whenever the label preference changes.
- (void) applyTreeMapAppearance
{
	//the design's gutters are the colour of the surface the map is inset in
	[_treeMapView setGutterColor: [DIXTheme surface]];
	[_treeMapView setSelectionColor: [DIXTheme accent]];
	[_treeMapView setDrawsCellLabels:
		[[NSUserDefaults standardUserDefaults] boolForKey: LabelLargeCells]];
	const BOOL classic = [[NSUserDefaults standardUserDefaults] boolForKey: ClassicCushions];

	[_treeMapView setUsesClassicCushions: classic];

	//10pt of surface around the map, as the design draws it. Not in classic
	//mode, which reproduces the original: the cells filled the view there, and
	//an inset would be as much a change to it as the gutters it already skips.
	[_treeMapView setContentInset: classic ? 0.0 : 10.0];

	//The palette goes with the shading, not with the appearance: see
	//FileTypeColors. Changing it drops every kind's assigned colour, so the map
	//has to be re-asked for them.
	if ( [[[self document] fileTypeColors] usesClassicPalette] != classic )
	{
		[[[self document] fileTypeColors] setUsesClassicPalette: classic];
		[_treeMapView reloadData];
	}
}

- (void) treeMapView: (TreeMapView*) view willShowMenuForEvent: (NSEvent*) event
{
    if ( [event type] == NSEventTypeRightMouseDown )
    {
        //right mouse click -> context menu
        //select the item hit by the click,
        //so the user gets feedback for which item the menu is shown 
        NSPoint point = [event locationInWindow];

        TMVCellId cell = [_treeMapView cellIdByPoint: point inViewCoords: NO];
        NSAssert1( cell != nil, @"No item at %@", NSStringFromPoint(point) );
		
		FSItem *fsItem = [_treeMapView itemByCellId: cell];

		if ( ![fsItem isSpecialItem] )
		{
			FileSystemDoc *document = [self document];
			[document setSelectedItem: fsItem];
		}
		
		[self onDocumentSelectionChanged];
    }
}

#pragma mark --------TreeMapView notifications-----------------

//The hover readout goes to the window's status bar, which replaced the two
//loose labels this controller used to write (the outlets remain connected but
//the labels are hidden). The bar adds the one figure the labels never had:
//the item's share of the scan, which is the number the treemap is drawing.
- (void)treeMapViewItemTouched: (NSNotification*) notification
{
    FSItem *fsItem = [[notification userInfo] objectForKey: TMVTouchedItem];
	TMVItem *cell = [[notification userInfo] objectForKey: TMVTouchedCell];

	NSWindowController *windowController = [[_treeMapView window] windowController];
	DIXStatusBarView *statusBar = [windowController isKindOfClass: [MainWindowController class]]
									? [(MainWindowController*) windowController statusBarView] : nil;

	//A remainder stands for many items and so has no single one of its own. It
	//is also the cell most worth describing, being the only thing that says
	//those files are there at all - so it must not fall into the nil branch,
	//which is what made pointing at one clear the readout instead of filling it.
	if ( fsItem == nil && [cell isRemainder] )
	{
		[self reportRemainder: cell inStatusBar: statusBar];
	}
    else if ( fsItem == nil )
    {
		[statusBar clearItem];
    }
    else
    {
		FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
		NSString *size = [sizeFormatter stringForObjectValue: [fsItem size]];
		NSString *detail = size;
		NSColor *kindColor = nil;

		if ( ![fsItem isSpecialItem] )
		{
			//share of the whole scan, not of the zoomed-in folder: the question
			//the readout answers is what this item costs the disk
			FileSystemDoc *doc = [self document];
			unsigned long long scanSize = [[[doc rootItem] size] unsignedLongLongValue];

			//"1.24 GB · 1.3% of this scan · Movies" - size, then share, then
			//where it is. The kind used to lead, which is the one thing the chip
			//beside the name already says in colour; what the readout could not
			//tell you was where in the tree you were pointing.
			NSString *share =
				ShareOfScanString( [[fsItem size] unsignedLongLongValue], scanSize );

			NSMutableString *line = [NSMutableString stringWithString: size];

			if ( share != nil )
				[line appendFormat: @" · %@", share];

			//the folder holding it, which is not the map's root - at the root
			//there is nothing useful left to say
			FSItem *parent = [fsItem parent];

			if ( parent != nil && parent != [self rootItem] )
				[line appendFormat: @" · %@", [parent displayName]];

			detail = line;

			//the synthetic cells keep a nil colour: free and other space are
			//not file kinds, and a chip would claim they are
			kindColor = [[doc fileTypeColors] colorForItem: fsItem];
		}

		[statusBar setItemName: [fsItem displayName] detail: detail kindColor: kindColor];
    }
}

- (void) treeMapViewSelectionDidChange: (NSNotification*) notification
{
    TreeMapView *view = (TreeMapView*) _treeMapView;

    //-selectedItem, not -enclosingItemByCellId:, would answer nil for a
    //remainder, and clicking one would clear the selection instead of moving
    //it. A remainder cannot be the document's selection - it stands for many
    //items and is none of them - so the click lands on the folder they were
    //merged out of, which the outline and the inspector can show.
    FSItem *item = [view enclosingItemByCellId: [view selectedCellId]];

    FileSystemDoc *doc = [self document];

    //if we are notified about the selection change after we've set the selection by ourself
    //(e.g. in 'onDocumentSelectionChanged') we don't want to post any notification
    if ( [doc selectedItem] != item
		 && ![item isSpecialItem] )
    {
        [doc setSelectedItem: item];
    }
}

//What the map had to aggregate this layout, put where a figure that contradicts
//the summary strip has to go. The cells cannot sum to the scan total once
//anything is merged, and the rule is that the difference is stated rather than
//left for someone to notice.
- (void) treeMapViewLayoutChanged: (NSNotification*) notification
{


	NSWindowController *windowController = [[[self document] windowControllers] firstObject];

	DIXStatusBarView *statusBar = [windowController isKindOfClass: [MainWindowController class]]
									? [(MainWindowController*) windowController statusBarView] : nil;

	if ( statusBar == nil )
		return;

	TreeMapView *view = (TreeMapView*) _treeMapView;
	const NSUInteger count = [view mergedItemCount];

	if ( count == 0 )
	{
		[statusBar setIdleSummary: nil detail: nil];
		return;
	}

	const unsigned long long merged = [view mergedItemWeight];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	//"items" and "separately", both deliberate. A merged entry is not always a
	//file - a folder with nothing worth subdividing is packed in whole - and a
	//folded folder is not "too small to draw", it is too small to draw as a
	//structure. Always plural: a remainder replaces at least two children.
	NSString *summary = [NSString stringWithFormat:
		NSLocalizedString( @"%@ items are too small to draw separately",
						   @"status bar, what the treemap had to merge" ),
		[NSNumberFormatter localizedStringFromNumber: @( count )
										 numberStyle: NSNumberFormatterDecimalStyle]];

	NSMutableString *detail =
		[NSMutableString stringWithString: [sizeFormatter stringForObjectValue: @(merged)]];

	const unsigned long long scanSize = [[[[self document] rootItem] size] unsignedLongLongValue];

	NSString *share = ShareOfScanString( merged, scanSize );

	if ( share != nil )
	{
		[detail appendFormat: NSLocalizedString( @" · %@ of this scan",
												 @"status bar, the merged share of the whole scan" ),
			share];
	}

	[statusBar setIdleSummary: summary detail: detail];
}

- (void) treeMapView: (TreeMapView*) view doubleClickedCellId: (TMVCellId) cellId
{
	FileSystemDoc *doc = [self document];
	FSItem *target = [view enclosingItemByCellId: cellId];

	//The widget addresses the root as nil, the way NSOutlineView does, so its
	//root renderer holds no item and a remainder sitting directly under it
	//resolves to nil rather than to the root. Every data source method above
	//already maps nil to the root; this was the one place that did not, and it
	//is why *those* merged cells - and only those - were dead double-clicks.
	if ( target == nil )
		target = [self rootItem];

	//A remainder has no item of its own and resolves to the folder that holds
	//it. Zooming there is what gives its merged items rects big enough to draw
	//- but only while that folder is not already what the map is showing.
	//
	//When it is, this was a dead double-click, and that is what "some merged
	//cells cannot zoom into" was: -zoomIntoItem: declines to re-zoom whatever is
	//on top of the stack, so nothing happened; and with an empty stack nothing
	//declined it either, so it pushed the displayed root onto itself and gave
	//the breadcrumb the same folder twice.
	//
	//At that point the pile is already drawn as large as this level allows, so
	//the only thing "zoom in" can still mean is to go into the largest folder
	//the pile itself contains. Where it lands is not a guess the user has to
	//make: the breadcrumb names it.
	TMVItem *cell = (TMVItem*) cellId;

	//A pile that is already what the map shows has nowhere further to zoom by
	//item: its contents are children of the displayed root, and zooming there
	//changes nothing. What does work is to lay the pile's own items out as the
	//map's whole content - they were merged for want of room beside their larger
	//siblings, and without those siblings there is room. This is the only thing
	//"zoom in" can mean for a pile holding no folder at all, which is most of
	//them: 1,583 data files have no item to descend into.
	if ( [cell isRemainder] && target == [doc zoomedItem] )
	{
		[doc setFocusedPile: [cell mergedItems]];
		return;
	}

	//Zooming into a file would leave an empty map, and the two synthetic cells
	//have no children to show.
	if ( target == nil || [target isSpecialItem] || ![target isFolder] )
		return;

	[doc zoomIntoItem: target];
}

#pragma mark --------document notifications-----------------

- (void) itemsChanged: (NSNotification*) notification
{
	//create new "free space" and "other space" items
	//(don't use [self rootItem] as we want the root, not the zoomed item)
	FSItem *rootItem =  [[self document] rootItem];
	
	_otherSpaceItem = [[FSItem alloc] initAsOtherSpaceItemForParent: rootItem];
	_freeSpaceItem = [[FSItem alloc] initAsFreeSpaceItemForParent: rootItem];
	
    [self reloadData];
}

//No zoom animation: it interpolates between two rects of one tree, and this
//replaces what the tree's root *is*. A plain reload is honest about that.
- (void) focusedPileChanged: (NSNotification*) notification
{
	[self reloadData];
}

- (void) zoomedItemChanged: (NSNotification*) notification
{
	//just do a reload if animated zooming is turned off
	if ( ![[NSUserDefaults standardUserDefaults] boolForKey: AnimatedZooming] )
	{
		[self reloadData];
	}
	else
	{
		FSItem *oldZoomedItem = [[notification userInfo] objectForKey: OldItem];
		FSItem *newZoomedItem = [[notification userInfo] objectForKey: NewItem];
		NSAssert( newZoomedItem == [self rootItem], @"invalid new zoomed item" );
		
		//did we zoom in or out?
		BOOL didZoomIn = [newZoomedItem isDescendantOf: oldZoomedItem];
		
		if ( didZoomIn )
		{
			NSArray *itemPath = [newZoomedItem fsItemPathFromAncestor: oldZoomedItem];
			[_treeMapView reloadAndPerformZoomIntoItem: itemPath];
		}
		else
		{
			NSArray *itemPath = [oldZoomedItem fsItemPathFromAncestor: newZoomedItem];
			[_treeMapView reloadAndPerformZoomOutofItem: itemPath];
		}
	}
}

- (void) viewOptionChanged: (NSNotification*) notification
{
	NSString *theOption = [[notification userInfo] objectForKey:ChangedViewOption];
	
	//The filter is a colour, not a layout, so the shaded bitmap is what goes
	//stale - not the tree. Reloading would relayout for nothing and lose the
	//selection on the way.
	if ( [theOption isEqualToString: DIXKindFilterOption] )
	{
		[_treeMapView invalidateCanvasCache];
		[_treeMapView reloadData];
		[self onDocumentSelectionChanged];
		return;
	}

	if ( [theOption isEqualToString: ShowPackageContents]
		 || [theOption isEqualToString: ShowPhysicalFileSize]
		 || [theOption isEqualToString: IgnoreCreatorCode]
		 || [theOption isEqualToString: ShowOtherSpace]
		 || [theOption isEqualToString: ShowFreeSpace] )
	{
		[self reloadData];
		
		//restore selection
		[self onDocumentSelectionChanged];
	}
}

#pragma mark --------window notifications-----------------

- (void) windowWillClose: (NSNotification*) notification
{
	[[self document] removeObserver: self forKeyPath: DocKeySelectedItem];
	
    [[NSNotificationCenter defaultCenter] removeObserver: self];
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver: self forKeyPath: [@"values." stringByAppendingString: ShareKindColors]];
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver: self forKeyPath: [@"values." stringByAppendingString: LabelLargeCells]];
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver: self forKeyPath: [@"values." stringByAppendingString: ClassicCushions]];
}

@end

@implementation TreeMapViewController(Private)

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if ( context == (__bridge void*) ShareKindColors )
	{
		[_treeMapView invalidateCanvasCache];
		[_treeMapView setNeedsDisplay: YES];
	}
	else if ( context == (__bridge void*) LabelLargeCells
			  || context == (__bridge void*) ClassicCushions )
	{
		//Labels are an overlay, so the shaded bitmap underneath is still good;
		//the shading model is baked into it, and -setUsesClassicCushions:
		//invalidates the cache itself when the value actually changes.
		[self applyTreeMapAppearance];
		[_treeMapView setNeedsDisplay: YES];
	}
	else if ( object == [self document] )
	{
		if ( [keyPath isEqualToString: DocKeySelectedItem] )
			[self onDocumentSelectionChanged];
	}
}

- (void) onDocumentSelectionChanged
{
	TreeMapView *view = (TreeMapView*) _treeMapView;
	FSItem *item = [[self document] selectedItem];

	//-enclosingItemByCellId:, not -selectedItem. A remainder has no item of its
	//own, so -selectedItem answers nil, this guard never fired, and clicking one
	//moved the selection straight off it and onto the parent folder's cell -
	//outlining a whole folder when a small hatched block had been clicked. The
	//remainder already stands for that item; it counts as selected.
	if ( item == (FSItem*) [view enclosingItemByCellId: [view selectedCellId]] )
		return;

	if ( item == nil )
		[view selectItemByCellId: nil];
	else
		[view selectItemByPathToItem: [item fsItemPathFromAncestor: [self rootItem]]];
}

- (void) reloadData;
{
	[_treeMapView reloadData];
	[self onDocumentSelectionChanged];
}

@end
