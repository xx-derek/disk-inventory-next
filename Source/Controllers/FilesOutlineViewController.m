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

#import "FilesOutlineViewController.h"
#import "DIXTheme.h"
#import "DIXTableHeaderView.h"
#import "FSItem.h"
#import "FSItem-Utilities.h"
#import "MainWindowController.h"
#import "Preferences.h"

@interface FilesOutlineViewController(Private)

- (void) onDocumentSelectionChanged;
- (void) searchResultsChanged: (NSNotification*) notification;
- (NSArray<FSItem*>*) searchResults;
- (NSColor*) chipColorForItem: (FSItem*) item;
- (NSString*) dominantKindForFolder: (FSItem*) folder;
- (void) accumulateKindSizesUnder: (FSItem*) item into: (NSMutableDictionary<NSString*,NSNumber*>*) parentTotals;
- (void) viewOptionChangedInvalidatesChips;
- (void) reloadPackages: (FSItem*) parent;
- (void) reloadData;
- (void) setOutlineViewFont;
- (void) applyDesignAppearance;
- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context;

@end

@implementation FilesOutlineViewController

- (void) awakeFromNib
{
	FileSystemDoc *doc = [self document];
	
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
    [center addObserver: self
			   selector: @selector(zoomedItemChanged:)
				   name: ZoomedItemChangedNotification
				 object: doc];
	
    [center addObserver: self
			   selector: @selector(viewOptionChanged:)
				   name: ViewOptionChangedNotification
				 object: doc];
	
    [center addObserver: self
			   selector: @selector(itemsChanged:)
				   name: FSItemsChangedNotification
				 object: doc];
	
    [center addObserver: self
			   selector: @selector(searchResultsChanged:)
				   name: SearchResultsChangedNotification
				 object: doc];

    [center addObserver: self
			   selector: @selector(windowWillClose:)
				   name: NSWindowWillCloseNotification
				 object: [_outlineView window]];
	
	//set ImageAndTextCell as the data cell for the first (outline) column
    [[_outlineView outlineTableColumn] setDataCell: [ImageAndTextCell cell]];
	
	//set FileSizeFormatter for the size column
	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];
	[[[_outlineView tableColumnWithIdentifier: @"size"] dataCell] setFormatter: sizeFormatter];
        
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver: self
															  forKeyPath: [@"values." stringByAppendingString: UseSmallFontInFilesView]
																 options: 0
																 context: (__bridge void*) UseSmallFontInFilesView];
	
	[doc addObserver: self forKeyPath: DocKeySelectedItem options: 0 context: nil];
	
	//set small font for all for all columns if needed
	[self setOutlineViewFont];

	[self applyDesignAppearance];
     
    [self reloadData];
}


- (FileSystemDoc*) document
{
    if ( _document == nil && _outlineView != nil )
        _document = [MainWindowController documentForView: _outlineView];

    return _document;
}

- (FSItem*) rootItem
{
    return [[self document] zoomedItem];
}

#pragma mark --------NSOutlineView datasource-----------------

//While a search is running the list stops being a tree and becomes the results,
//flat. A hit is shown where it was found, not where it sits: nesting the matches
//back under their folders would hide most of them behind closed triangles, which
//is the opposite of what someone typing into a search field is asking for.
//
//Nil rather than an empty array is what says "not searching" - an empty array
//means the search found nothing, and the list has to show that rather than
//falling back to the tree.
- (NSArray<FSItem*>*) searchResults
{
	return [[self document] searchResults];
}

- (id) outlineView: (NSOutlineView *) outlineView child: (NSInteger) index ofItem: (id) item
{
	NSArray<FSItem*> *results = [self searchResults];

	if ( results != nil )
		return ( item == nil && index < (NSInteger) [results count] )
				? [results objectAtIndex: index] : nil;

	FSItem *fsItem = (item == nil) ? [self rootItem] : item;

    return [fsItem childAtIndex: index];
}

- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable: (id) item
{
	if ( [self searchResults] != nil )
		return NO;

    return [[self document] itemIsNode: item];
}

- (NSInteger) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem: (id) item
{
	NSArray<FSItem*> *results = [self searchResults];

	if ( results != nil )
		return ( item == nil ) ? (NSInteger) [results count] : 0;

	FSItem *fsItem = (item == nil) ? [self rootItem] : item;

    return [fsItem childCount];
}

- (id) outlineView: (NSOutlineView *) outlineView
objectValueForTableColumn: (NSTableColumn *) tableColumn
            byItem: (id) item
{
    NSString *columnTag = [tableColumn identifier];
    FSItem *fsItem = item;

	//Computed rather than a property of the item: it is a share of the *scan*,
	//so it changes with the root and belongs to the view, not to the file.
	if ( [columnTag isEqualToString: @"dixShare"] )
	{
		const unsigned long long scanSize =
			[[[[self document] rootItem] size] unsignedLongLongValue];

		if ( scanSize == 0 )
			return @"";

		NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];

		[formatter setNumberStyle: NSNumberFormatterPercentStyle];

		//One decimal always, not at most one. This is a column, and dropping the
		//trailing zero puts "18%" beside "24.3%" so the figures stop lining up -
		//which is the whole reason they are set in tabular figures.
		[formatter setMinimumFractionDigits: 1];
		[formatter setMaximumFractionDigits: 1];

		return [formatter stringFromNumber: @( (double) [fsItem sizeValue] / scanSize )];
	}

	return [fsItem valueForKey: columnTag];
}

- (BOOL) outlineView: (NSOutlineView *) outlineView
          writeItems: (NSArray*) items
        toPasteboard: (NSPasteboard*) pboard
{
	//currently, we only support single selection
	NSAssert( [items count] == 1, @"only first item will be written to the pasteboard" );
	FSItem *item = [items objectAtIndex: 0];
	
	if ( ![item isSpecialItem] && [item exists] )
	{
		[item writeToPasteboard: pboard];
		
		return YES;
	}
	else
		return NO;
}

#pragma mark --------NSOutlineView delegate-----------------

//A 10x10 square of a kind's colour. Square, not rounded: the design keeps data
//elements square and reserves the 6pt radius for controls, and this is the same
//chip the sidebar legend uses.
//
//Cached by colour rather than built per row. A list redraws every visible row on
//every scroll, and there are twelve colours in the palette plus a grey ramp.
static NSImage* KindChipImage( NSColor *color )
{
	static NSMutableDictionary<NSColor*, NSImage*> *cache = nil;

	if ( cache == nil )
		cache = [NSMutableDictionary dictionary];

	if ( color == nil )
		return nil;

	NSImage *chip = [cache objectForKey: color];

	if ( chip != nil )
		return chip;

	//Drawn centred in a 16pt box rather than as a 10pt image. ImageAndTextCell is
	//Apple sample code and draws whatever it is given at a hardcoded 16x16, so an
	//image of the chip's own size would come back scaled half again too big; the
	//padding is what keeps the chip at the 10pt the sidebar legend uses.
	const CGFloat box  = 16.0;
	const CGFloat side = [DIXTheme kindChipSize];

	chip = [NSImage imageWithSize: NSMakeSize( box, box )
						  flipped: NO
				   drawingHandler: ^BOOL( NSRect rect )
	{
		[color set];
		NSRectFill( NSMakeRect( ( box - side ) / 2.0, ( box - side ) / 2.0, side, side ) );
		return YES;
	}];

	[cache setObject: chip forKey: color];

	return chip;
}

- (void) outlineView: (NSOutlineView *) outlineView
     willDisplayCell: (id) cell
      forTableColumn: (NSTableColumn *) tableColumn
                item: (id) item
{
    if ( [[tableColumn identifier] isEqualToString: @"displayName"] )
    {
		//The design puts a kind chip where the file icon was, and is emphatic
		//that the rule has no exceptions: a file shows its own kind's colour, a
		//folder the colour of the kind filling the most space inside it. The
		//sidebar legend binds those colours to named kinds, so a folder drawn in
		//a generic colour would make every chip in the list unreliable.
		[cell setImage: KindChipImage( [self chipColorForItem: item] )];
    }
}

//Nil for the two synthetic cells, which are not file kinds - the map draws them
//neutral for the same reason.
- (NSColor*) chipColorForItem: (FSItem*) item
{
	FileSystemDoc *doc = [self document];

	if ( [item isSpecialItem] )
		return nil;

	if ( ![doc itemIsNode: item] )
		return [[doc fileTypeColors] colorForItem: item];

	NSString *kind = [self dominantKindForFolder: item];

	return kind != nil ? [[doc fileTypeColors] colorForKind: kind] : nil;
}

//The kind occupying the most space inside a folder.
//
//Computed for the whole tree in one bottom-up pass rather than per row: a row is
//drawn on every scroll, and answering for one folder means walking everything
//under it - which for the root is the entire scan. The pass merges each folder's
//kind totals into its parent's and keeps only the winner, so what it holds at
//any moment is one root-to-leaf path's worth of totals rather than the tree's.
//
//Keyed weakly, so a tree dropped between refreshes takes its entries with it.
- (NSString*) dominantKindForFolder: (FSItem*) folder
{
	if ( _dominantKinds == nil )
	{
		_dominantKinds = [NSMapTable mapTableWithKeyOptions: NSPointerFunctionsWeakMemory
											   valueOptions: NSPointerFunctionsStrongMemory];

		FSItem *root = [[self document] rootItem];

		if ( root != nil )
			[self accumulateKindSizesUnder: root into: [NSMutableDictionary dictionary]];
	}

	return [_dominantKinds objectForKey: folder];
}

- (void) accumulateKindSizesUnder: (FSItem*) item
							 into: (NSMutableDictionary<NSString*, NSNumber*>*) parentTotals
{
	if ( [item isSpecialItem] )
		return;

	if ( ![[self document] itemIsNode: item] )
	{
		NSString *kind = [item kindName];

		if ( [kind length] > 0 )
		{
			const unsigned long long running =
				[[parentTotals objectForKey: kind] unsignedLongLongValue] + [item sizeValue];

			[parentTotals setObject: @(running) forKey: kind];
		}

		return;
	}

	NSMutableDictionary<NSString*, NSNumber*> *totals = [NSMutableDictionary dictionary];
	NSUInteger i = [item childCount];

	while ( i-- )
		[self accumulateKindSizesUnder: [item childAtIndex: i] into: totals];

	__block NSString *dominant = nil;
	__block unsigned long long best = 0;

	[totals enumerateKeysAndObjectsUsingBlock: ^( NSString *kind, NSNumber *size, BOOL *stop )
	{
		const unsigned long long value = [size unsignedLongLongValue];

		if ( value > best )
		{
			best = value;
			dominant = kind;
		}

		//merged upward here rather than in a second loop, since this one is
		//already walking every entry
		const unsigned long long running =
			[[parentTotals objectForKey: kind] unsignedLongLongValue] + value;

		[parentTotals setObject: @(running) forKey: kind];
	}];

	if ( dominant != nil )
		[_dominantKinds setObject: dominant forKey: item];
}

- (NSMenu*) outlineView: (NSOutlineView *) outlineView menuForTableColumn: (NSTableColumn*) column item: (id) item
{	
	return _contextMenu;
}

- (NSDragOperation) dragOperationMaskForLocalDestination:(BOOL)isLocal
{
	//this selector is normally sent to the view itself, but DIXOutlineView forwards this decision to
	//it's delagate (like it should be)
	
	//drag&drop within the application is not supported
	//
	//Copy only, not Link: offering Link makes the Finder create an alias rather
	//than a copy, which is almost never what is wanted from a file listing. The
	//other two drag sources in this app already commented Link out for the same
	//reason; the outline view was simply missed.
	return isLocal ? NSDragOperationNone : NSDragOperationCopy;
}

#pragma mark --------NSOutlineView notifications-----------------

- (void) outlineViewSelectionDidChange: (NSNotification*) notification
{
    FSItem *item = [_outlineView selectedItem];

    FileSystemDoc *doc = [self document];

    //if we are notified about the selection change after we've set the selection by ourself
    //(e.g. in 'onDocumentSelectionChanged') we don't want to post any notification
    if ( item != [doc selectedItem] )
        [doc setSelectedItem: item];
}

#pragma mark --------document notifications-----------------

- (void) zoomedItemChanged: (NSNotification*) notification
{
    [self reloadData];
}

- (void) viewOptionChangedInvalidatesChips
{
	//"show package contents" changes which items count as folders, and so which
	//kinds a folder is made of
	_dominantKinds = nil;
}

//A reload and nothing else. Collapsing first, which this did, asks the outline
//to operate on rows that the data source has already stopped describing - the
//document changed underneath it before the notification was sent - and it left
//the list blank on the way back to the tree. Expansion state is worth keeping
//across a search in any case: it is the state of the tree, and the tree is what
//comes back.
- (void) searchResultsChanged: (NSNotification*) notification
{
	[self reloadData];
}

- (void) viewOptionChanged: (NSNotification*) notification
{
	NSString *theOption = [[notification userInfo] objectForKey:ChangedViewOption];
	
	if ( [theOption isEqualToString: ShowPackageContents] )
	{
		//that option changes which items count as folders, and so which kinds a
		//folder is made of
		[self viewOptionChangedInvalidatesChips];

		//save current selection
		id selectedItem = [_outlineView selectedItem];
		[_outlineView deselectAll: self];
		
		[self reloadPackages: nil];
		
		//try to restore selection
		NSInteger row = [_outlineView rowForItem: selectedItem];
		if ( row >= 0 )
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection: NO];
		
		//the view doesn't redraw properly, so invalidate it
		[_outlineView setNeedsDisplay: YES];
	}
	else if ( [theOption isEqualToString: ShowPhysicalFileSize] )
		[self reloadData];
}

- (void) itemsChanged: (NSNotification*) notification
{
	//the chips are computed from sizes, so anything that moved items invalidates
	//every folder's answer, not only the ones that moved
	_dominantKinds = nil;

    [self reloadData];
}

#pragma mark --------window notifications-----------------

- (void) windowWillClose: (NSNotification*) notification
{
	[[self document] removeObserver: self forKeyPath: DocKeySelectedItem];
	
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver: self forKeyPath: [@"values." stringByAppendingString: UseSmallFontInFilesView]];
	
	[[NSNotificationCenter defaultCenter] removeObserver: self];
}

@end

@implementation FilesOutlineViewController(Private)

- (void)observeValueForKeyPath:(NSString*)keyPath
					  ofObject:(id)object
						change:(NSDictionary*)change
					   context:(void*)context
{
	if ( context == (__bridge void*) UseSmallFontInFilesView )
	{
		[self setOutlineViewFont];
	}
	else if ( object == [self document] )
	{
		if ( [keyPath isEqualToString: DocKeySelectedItem] )
			[self onDocumentSelectionChanged];
	}
}

- (void) onDocumentSelectionChanged
{
    FSItem *item = [[self document] selectedItem];

	if ( item == (FSItem*) [_outlineView selectedItem] )
		return;

    if ( item == nil )
        [_outlineView deselectAll: nil];
    else
    {
        NSInteger row = [_outlineView rowForItem: item];

        //While a search is showing, nothing is expandable and an item that is
        //not a result has no row to reveal. Walking its ancestors trying to
        //expand them cannot succeed and must not be attempted.
        if ( row < 0 && [self searchResults] != nil )
        {
            [_outlineView deselectAll: nil];
            return;
        }

        //if the item can't be found in the view, then the user hasn't expanded the parents yet
        if ( row < 0 )
        {
            //get path from the root item to the item to be selected
            NSArray *path = [item fsItemPath];
            
            //expand all nodes in the outlineview till the item
            NSUInteger i = 0;
            for ( i = 1; i < [path count]; i++ )
            {
                row = [_outlineView rowForItem: item];
                if ( row <= 0 )
                {
                    //the item is not exandable, so stop here
                    //(e.g. item is a pckage, but package contents aren't shown)
                    if ( ![[self document] itemIsNode: [path objectAtIndex: i]] )
                        break;
					
                    [_outlineView expandItem: [path objectAtIndex: i]];
                }
            }
            
            //now the item may be found in the outline view, if the expandation wasn't stopped
            row = [_outlineView rowForItem: [[self document] selectedItem]];
        }
        
        if ( row < 0 )
            [_outlineView deselectAll: nil];
        else
        {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection: NO];
            [_outlineView scrollRowToVisible: row];
        }
    }
}

//The design's rows are 26pt with the size in tabular figures and a share column
//beside it, under a 28pt header. The header is worth a note: the README says
//the design has no table headers, and the design file has one over this list -
//Name, Size, Share, 11pt in the tertiary colour over a 0.5pt rule. The HTML is
//the source of truth for values, as it was for the cell gaps and the label ink,
//so the header stays. This restyles the nib's
//outline in place rather than replacing it: the nib still owns the view, so
//building a replacement now would mean duplicating this controller's wiring -
//data source, delegate, drag, context menu, the poof effect's cell rect - and
//throwing the duplicate away at the end of this phase, where the outline is
//created in code anyway. The per-row kind chip needs view-based rows and lands
//there with it.
- (void) applyDesignAppearance
{
	[_outlineView setGridStyleMask: NSTableViewGridNone];

	//AppKit's header draws a bezel, a gradient and a separator per column; the
	//design's is a flat band with one rule. Both the view and the cells have to
	//be replaced - the cell paints its own background before its text.
	DIXTableHeaderView *header = [[DIXTableHeaderView alloc] initWithFrame:
		NSMakeRect( 0.0, 0.0, NSWidth( [_outlineView bounds] ),
					[DIXTableHeaderView preferredHeight] )];

	[_outlineView setHeaderView: header];

	for ( NSTableColumn *column in [_outlineView tableColumns] )
	{
		DIXTableHeaderCell *cell = [[DIXTableHeaderCell alloc] initTextCell:
			[[column headerCell] stringValue]];

		[cell setAlignment: [[column headerCell] alignment]];
		[column setHeaderCell: cell];
	}
	[_outlineView setIntercellSpacing: NSMakeSize( 6.0, 0.0 )];
	[_outlineView setBackgroundColor: [DIXTheme surface]];

	NSTableColumn *size = [_outlineView tableColumnWithIdentifier: @"size"];

	[size setWidth: 74.0];
	[size setMinWidth: 74.0];
	[size setMaxWidth: 74.0];
	[[size dataCell] setAlignment: NSTextAlignmentRight];
	[[size dataCell] setTextColor: [DIXTheme bodyText]];

	//"Name (fills) · Size (74pt) · Share (46pt)", which needs saying twice: the
	//two figures are pinned above, and the name is told it may shrink.
	//
	//Without this the name column kept the wide minimum the nib gave it, so a
	//narrow list could not shrink the table to fit - it scrolled sideways
	//instead, leaving a column of sizes with the names off to the left and the
	//header reading "N". First-column-only autoresizing is what makes the name
	//absorb the difference rather than the last column, which is pinned.
	NSTableColumn *name = [_outlineView outlineTableColumn];

	[name setMinWidth: 60.0];
	[name setMaxWidth: 10000.0];

	[_outlineView setColumnAutoresizingStyle: NSTableViewFirstColumnOnlyAutoresizingStyle];

	//The style only redistributes when the table's frame changes, and the name
	//column arrives carrying whatever width it was last squeezed to - which
	//NSTableView autosaves, so a bad one comes back every launch. -sizeToFit
	//spends the table's current width across the columns now, honouring the
	//minimums and maximums just set, which is what gives the name the remainder.
	[_outlineView setAutosaveTableColumns: NO];
	[_outlineView sizeToFit];

	[[[_outlineView outlineTableColumn] headerCell] setStringValue:
		NSLocalizedString( @"Name", @"file list column" )];
	[[size headerCell] setStringValue: NSLocalizedString( @"Size", @"file list column" )];
	[[size headerCell] setAlignment: NSTextAlignmentRight];

	//The row's percentage of the whole scan - the number the map is drawing, and
	//the one thing a list of sizes cannot tell you at a glance.
	if ( [_outlineView tableColumnWithIdentifier: @"dixShare"] == nil )
	{
		NSTableColumn *share = [[NSTableColumn alloc] initWithIdentifier: @"dixShare"];

		[share setWidth: 46.0];
		[share setMinWidth: 46.0];
		[share setMaxWidth: 46.0];
		[[share dataCell] setAlignment: NSTextAlignmentRight];
		[[share dataCell] setTextColor: [DIXTheme tertiaryText]];

		//its own header cell, since this column is created after the swap above
		DIXTableHeaderCell *shareHeader = [[DIXTableHeaderCell alloc] initTextCell:
			NSLocalizedString( @"Share", @"file list column" )];

		[shareHeader setAlignment: NSTextAlignmentRight];
		[share setHeaderCell: shareHeader];

		[_outlineView addTableColumn: share];
	}
}

- (void) setOutlineViewFont
{
	//The design's rows are 12pt, which is a point under +systemFontSize. Written
	//out rather than taken from the system, because the figure is the design's
	//and not the platform's, and the row height below is measured against it.
	CGFloat fontSize = 12.0;

	if ( [[NSUserDefaults standardUserDefaults] boolForKey: UseSmallFontInFilesView] )
		fontSize = [NSFont smallSystemFontSize];
	
	NSFont *font = [NSFont systemFontOfSize: fontSize];

	//NSTableView has no font of its own; it lives on each column's data cell
	for ( NSTableColumn *column in [_outlineView tableColumns] )
	{
		//figures line up in a column only if they are the same width, which the
		//proportional system font does not promise
		const BOOL isNumeric = ( [[column identifier] isEqualToString: @"size"]
								 || [[column identifier] isEqualToString: @"dixShare"] );

		[[column dataCell] setFont: isNumeric ? [DIXTheme tabularFontOfSize: fontSize] : font];
	}

	[_outlineView setNeedsDisplay: YES];

	//The header is the design's 11pt in the secondary tone, whatever the row font
	//does - it labels the columns rather than being part of the list. The
	//quieter tertiary step belongs to the share figures, which had it the other
	//way round.
	for ( NSTableColumn *column in [_outlineView tableColumns] )
	{
		[[column headerCell] setFont: [NSFont systemFontOfSize: 11.0]];
		[[column headerCell] setTextColor: [DIXTheme secondaryText]];
	}

	//26pt rows, or the font's own height if the small-font preference has pushed
	//it past that - a clipped name is worse than a row out of step with the design
	[_outlineView setRowHeight: MAX( 26.0, fontSize + 4.0 )];
}

- (void) reloadData
{
    [_outlineView reloadData];
	[self onDocumentSelectionChanged];
}

- (void) reloadPackages: (FSItem*) parent
{
	FileSystemDoc *doc = [self document];
	
    if ( parent == nil )
	{
        parent = [self rootItem];
	}

    unsigned i;
    for ( i = 0; i < [parent childCount]; i++ )
    {
        FSItem *child = [parent childAtIndex: i];

        //if the item is shown in the outline view, reload all package items
        if ( [child isFolder] && [_outlineView rowForItem: child] >= 0 )
        {
			//collapse item if it is no longer expandable
			if ( ![doc itemIsNode: child] && [_outlineView isItemExpanded: child] )
				[_outlineView collapseItem: child collapseChildren: TRUE];
			
            if ( [child isPackage] )
                [_outlineView reloadItem: child];

			//recurse through childs
			if ( [[self document] itemIsNode: child] )
				[self reloadPackages: child];
        }
    }
}

@end
