//
//  DIXBreadcrumbView.m
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

#import "DIXBreadcrumbView.h"
#import "DIXTheme.h"

static const CGFloat kSegmentFontSize   = 13.0;
static const CGFloat kSeparatorFontSize = 12.0;
static const CGFloat kSegmentGap        =  5.0;
static const CGFloat kSegmentInset      =  3.0;

//U+203A, the single right-pointing angle quotation mark. Narrower and lighter
//than ">" and it is what the platform uses between path components.
static NSString * const kSeparator = @"›";

#pragma mark --------one segment-----------------

//NSButton has no -representedObject, and the action this drives - the window
//controller's -zoomOutTo: - reads one off its sender, because it was written
//for the zoom-stack menu. Carrying the object here means that action is reused
//exactly as it stands rather than gaining a second entry point.
@interface DIXBreadcrumbSegment : NSButton
@property (nonatomic, strong) id representedObject;
@end

@implementation DIXBreadcrumbSegment
@end

#pragma mark --------the breadcrumb-----------------

@interface DIXBreadcrumbView()
{
	NSMutableArray<DIXBreadcrumbSegment*> *_segments;
	NSMutableArray<NSTextField*> *_separators;

	__weak id _target;
	SEL _action;
}
@end

@implementation DIXBreadcrumbView

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_segments = [NSMutableArray array];
		_separators = [NSMutableArray array];
	}

	return self;
}

- (void) setTarget: (id) target action: (SEL) action
{
	_target = target;
	_action = action;

	for ( DIXBreadcrumbSegment *segment in _segments )
	{
		[segment setTarget: target];
		[segment setAction: action];
	}
}

#pragma mark --------contents-----------------

- (void) setSegmentTitles: (NSArray<NSString*>*) titles representedObjects: (NSArray*) objects
{
	//Rebuilt rather than reused. The zoom stack changes rarely - once per zoom -
	//and pooling half a dozen buttons would trade a clear rebuild for a stale
	//title the one time the counts happen to match.
	for ( NSView *view in [self subviews] )
		[view removeFromSuperview];

	[_segments removeAllObjects];
	[_separators removeAllObjects];

	const NSUInteger count = [titles count];

	for ( NSUInteger i = 0; i < count; i++ )
	{
		const BOOL isLast = ( i == count - 1 );

		DIXBreadcrumbSegment *segment = [[DIXBreadcrumbSegment alloc] initWithFrame: NSZeroRect];

		[segment setTranslatesAutoresizingMaskIntoConstraints: YES];
		[segment setButtonType: NSButtonTypeMomentaryChange];
		[segment setBordered: NO];
		[segment setBezelStyle: NSBezelStyleInline];

		//Where you are is a statement, not a control: the last segment is ink
		//and semibold, is not clickable, and does not take a cursor.
		NSDictionary *attributes = @{
			NSFontAttributeName: [NSFont systemFontOfSize: kSegmentFontSize
													weight: isLast ? NSFontWeightSemibold
																   : NSFontWeightRegular],
			NSForegroundColorAttributeName: isLast ? [DIXTheme ink] : [DIXTheme secondaryText],
		};

		[segment setAttributedTitle:
			[[NSAttributedString alloc] initWithString: [titles objectAtIndex: i]
											attributes: attributes]];

		[segment setEnabled: !isLast];

		if ( !isLast )
		{
			[segment setRepresentedObject: ( i < [objects count] )
											? [objects objectAtIndex: i] : nil];
			[segment setTarget: _target];
			[segment setAction: _action];
		}

		[_segments addObject: segment];
		[self addSubview: segment];

		if ( !isLast )
		{
			NSTextField *separator = [NSTextField labelWithString: kSeparator];

			[separator setTranslatesAutoresizingMaskIntoConstraints: YES];
			[separator setFont: [NSFont systemFontOfSize: kSeparatorFontSize]];
			[separator setTextColor: [DIXTheme tertiaryText]];

			[_separators addObject: separator];
			[self addSubview: separator];
		}
	}

	[self layoutSegments];
}

#pragma mark --------layout-----------------

- (void) setFrameSize: (NSSize) newSize
{
	[super setFrameSize: newSize];
	[self layoutSegments];
}

- (void) layoutSegments
{
	const NSRect bounds = [self bounds];
	const CGFloat midY = NSMidY( bounds );

	CGFloat x = 0.0;

	for ( NSUInteger i = 0; i < [_segments count]; i++ )
	{
		DIXBreadcrumbSegment *segment = [_segments objectAtIndex: i];

		[segment sizeToFit];

		const NSSize size = [segment frame].size;
		[segment setFrame: NSMakeRect( x, midY - size.height / 2.0, size.width, size.height )];

		x += size.width;

		if ( i < [_separators count] )
		{
			NSTextField *separator = [_separators objectAtIndex: i];

			[separator sizeToFit];

			const NSSize separatorSize = [separator frame].size;

			[separator setFrame: NSMakeRect( x + kSegmentGap - kSegmentInset,
											 midY - separatorSize.height / 2.0,
											 separatorSize.width, separatorSize.height )];

			x += kSegmentGap * 2.0 + separatorSize.width - kSegmentInset * 2.0;
		}
	}
}

- (CGFloat) fittingWidth
{
	[self layoutSegments];

	CGFloat width = 0.0;

	for ( NSView *view in [self subviews] )
		width = MAX( width, NSMaxX( [view frame] ) );

	return width;
}

//No -drawRect: at all, deliberately. A view without a backing layer that fills
//its dirty rect paints over its siblings - see the note in DIXStatusBarView -
//and a breadcrumb has nothing to draw behind its labels anyway.

@end
