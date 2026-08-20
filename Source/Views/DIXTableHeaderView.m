//
//  DIXTableHeaderView.m
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

#import "DIXTableHeaderView.h"
#import "DIXTheme.h"

static const CGFloat kHeaderHeight = 28.0;
static const CGFloat kTextInset    = 10.0;

@implementation DIXTableHeaderView

+ (CGFloat) preferredHeight
{
	return kHeaderHeight;
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Deliberately not calling super, which is what draws the bezel and the
	//per-column separators. Clamped to bounds like the rest of the chrome.
	[[DIXTheme chrome] set];
	NSRectFill( NSIntersectionRect( dirtyRect, [self bounds] ) );

	//Along the bottom, between the header and the first row - which is where the
	//design draws it, and which in *this* view means the far y. NSTableHeaderView
	//is flipped, so a rule at the origin is a rule along the top: it left the
	//band's own top edge underlined and the boundary that matters undrawn.
	NSRect rule = [self bounds];
	rule.size.height = [DIXTheme hairlineThickness];
	rule.origin.y = NSMaxY( [self bounds] ) - rule.size.height;

	//the lighter content weight: this divides one pane, where -hairline
	//is the edge *between* panes - between the header and the rows, inside the list
	[[DIXTheme contentHairline] set];
	NSRectFill( NSIntersectionRect( rule, dirtyRect ) );

	for ( NSUInteger i = 0; i < [[[self tableView] tableColumns] count]; i++ )
	{
		const NSRect columnRect = [self headerRectOfColumn: (NSInteger) i];

		if ( NSIntersectsRect( columnRect, dirtyRect ) )
		{
			NSTableColumn *column = [[[self tableView] tableColumns] objectAtIndex: i];

			[[column headerCell] drawWithFrame: columnRect inView: self];
		}
	}
}

//No drag-to-reorder and no click-to-sort: the columns were never sortable and
//the design gives the header no affordance suggesting otherwise.
- (void) mouseDown: (NSEvent*) event
{
}

@end

@implementation DIXTableHeaderCell

- (void) drawWithFrame: (NSRect) cellFrame inView: (NSView*) controlView
{
	[self drawInteriorWithFrame: cellFrame inView: controlView];
}

- (void) drawInteriorWithFrame: (NSRect) cellFrame inView: (NSView*) controlView
{
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];

	[paragraph setAlignment: [self alignment]];
	[paragraph setLineBreakMode: NSLineBreakByTruncatingTail];

	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize: 11.0],
		NSForegroundColorAttributeName: [DIXTheme secondaryText],
		NSParagraphStyleAttributeName: paragraph,
	};

	const NSSize extent = [[self stringValue] sizeWithAttributes: attributes];

	//vertically centred in the band, inset from whichever edge it is aligned to
	NSRect textRect = NSInsetRect( cellFrame, kTextInset, 0.0 );
	textRect.origin.y = NSMidY( cellFrame ) - extent.height / 2.0;
	textRect.size.height = extent.height;

	[[self stringValue] drawInRect: textRect withAttributes: attributes];
}

@end
