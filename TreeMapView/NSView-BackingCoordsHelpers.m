//
//  NSView-BackingCoordsHelpers.m
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

#import "NSView-BackingCoordsHelpers.h"

//How many backing pixels one point covers, always positive. Taken from AppKit so
//it follows the view onto a display of a different scale.
static void BackingScale( NSView *view, CGFloat *scaleX, CGFloat *scaleY )
{
	const NSSize unit = [view convertSizeToBacking: NSMakeSize( 1.0, 1.0 )];

	*scaleX = fabs( unit.width );
	*scaleY = fabs( unit.height );

	//a view with no window yet still has to give an answer
	if ( *scaleX <= 0.0 ) *scaleX = 1.0;
	if ( *scaleY <= 0.0 ) *scaleY = 1.0;
}

@implementation NSView(BackingCoordsHelpers)

//AppKit's own -convertPointToBacking: and friends are not usable here. They
//convert into a bottom-up space, so on a flipped view they come back with a
//negated y: a rect sitting at the top of the view lands at a negative
//coordinate. What a bitmap needs is the opposite — y measured downwards from
//the top-left corner, which is where its first row is. So the scaling is done
//here, and the y axis is oriented explicitly.

- (NSPoint) convertPointToBackingRespectingFlipped: (NSPoint) point
{
	CGFloat scaleX, scaleY;
	BackingScale( self, &scaleX, &scaleY );

	const NSRect bounds = [self bounds];

	//a flipped view already measures downwards from the top
	const CGFloat distanceFromTop = [self isFlipped]
									? ( point.y - NSMinY(bounds) )
									: ( NSMaxY(bounds) - point.y );

	return NSMakePoint( ( point.x - NSMinX(bounds) ) * scaleX, distanceFromTop * scaleY );
}

- (NSPoint) convertPointFromBackingRespectingFlipped: (NSPoint) point
{
	CGFloat scaleX, scaleY;
	BackingScale( self, &scaleX, &scaleY );

	const NSRect bounds = [self bounds];
	const CGFloat distanceFromTop = point.y / scaleY;

	const CGFloat y = [self isFlipped]
					  ? ( NSMinY(bounds) + distanceFromTop )
					  : ( NSMaxY(bounds) - distanceFromTop );

	return NSMakePoint( NSMinX(bounds) + point.x / scaleX, y );
}

- (NSSize) convertSizeToBackingRespectingFlipped: (NSSize) size
{
	CGFloat scaleX, scaleY;
	BackingScale( self, &scaleX, &scaleY );

	//a size has no position, so orientation does not enter into it
	return NSMakeSize( fabs( size.width ) * scaleX, fabs( size.height ) * scaleY );
}

- (NSSize) convertSizeFromBackingRespectingFlipped: (NSSize) size
{
	CGFloat scaleX, scaleY;
	BackingScale( self, &scaleX, &scaleY );

	return NSMakeSize( fabs( size.width ) / scaleX, fabs( size.height ) / scaleY );
}

//Both corners are converted and the rect rebuilt from them, because flipping
//turns the top edge into the bottom one; taking origin and size across
//unchanged would put the rect one height out of place.
- (NSRect) convertRectToBackingRespectingFlipped: (NSRect) rect
{
	const NSPoint a = [self convertPointToBackingRespectingFlipped: NSMakePoint( NSMinX(rect), NSMinY(rect) )];
	const NSPoint b = [self convertPointToBackingRespectingFlipped: NSMakePoint( NSMaxX(rect), NSMaxY(rect) )];

	return NSMakeRect( MIN( a.x, b.x ), MIN( a.y, b.y ), fabs( b.x - a.x ), fabs( b.y - a.y ) );
}

- (NSRect) convertRectFromBackingRespectingFlipped: (NSRect) rect
{
	const NSPoint a = [self convertPointFromBackingRespectingFlipped: NSMakePoint( NSMinX(rect), NSMinY(rect) )];
	const NSPoint b = [self convertPointFromBackingRespectingFlipped: NSMakePoint( NSMaxX(rect), NSMaxY(rect) )];

	return NSMakeRect( MIN( a.x, b.x ), MIN( a.y, b.y ), fabs( b.x - a.x ), fabs( b.y - a.y ) );
}

@end
