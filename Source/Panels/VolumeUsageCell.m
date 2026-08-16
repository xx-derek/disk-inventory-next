//
//  VolumeUsageCell.m
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

#import "VolumeUsageCell.h"

//space before and after the bar, relative to the left and right side of the cell
static const CGFloat kBarInset = 16.0;

static const CGFloat kBarHeight = 10.0;

static double ClampFraction( double value )
{
    if ( !( value > 0.0 ) ) //also catches NaN, which a zero-capacity volume produces
        return 0.0;

    return value > 1.0 ? 1.0 : value;
}

@implementation VolumeUsageCell

@synthesize usedFraction = _usedFraction;
@synthesize sharedUsedFraction = _sharedUsedFraction;
@synthesize hasSizeInfo = _hasSizeInfo;

//NSCell's -copyWithZone: copies the instance's bytes, which is enough here
//because every ivar above is a scalar. Adding an object ivar means writing
//-copyWithZone: as well, or the table view's copies will over-release it.

- (void) setUsedFraction: (double) fraction
{
    _usedFraction = ClampFraction( fraction );
}

- (void) setSharedUsedFraction: (double) fraction
{
    _sharedUsedFraction = ClampFraction( fraction );
}

- (void) drawWithFrame: (NSRect) cellFrame inView: (NSView*) controlView
{
    if ( !_hasSizeInfo )
        return; //no size information available for this volume

    NSRect track = NSInsetRect( cellFrame, kBarInset, 0 );
    if ( NSWidth( track ) <= 0 || NSHeight( track ) < kBarHeight )
        return;

    //the full width, every row: the bar is a scale, not a measurement
    const CGFloat barWidth = NSWidth( track );

    //centre the bar vertically in the row
    track.origin.y += ( NSHeight( track ) - kBarHeight ) / 2;
    track.size.height = kBarHeight;

    const CGFloat radius = kBarHeight / 2;
    NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect: track xRadius: radius yRadius: radius];

    //On a selected row the table has already filled the background with the
    //accent colour, so an accent-coloured bar would be invisible against it.
    const BOOL onSelection = [self isHighlighted];

    NSColor *trackColor = onSelection
        ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent: 0.25]
        : [NSColor quaternaryLabelColor];
    NSColor *usedColor = onSelection
        ? [NSColor alternateSelectedControlTextColor]
        : [NSColor controlAccentColor];
    NSColor *sharedColor = onSelection
        ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent: 0.55]
        : [[NSColor labelColor] colorWithAlphaComponent: 0.35];
    NSColor *borderColor = onSelection
        ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent: 0.4]
        : [NSColor tertiaryLabelColor];

    [trackColor set];
    [trackPath fill];

    //the two segments together must never exceed the track
    const double ownFraction = _usedFraction;
    const double sharedFraction = MIN( _sharedUsedFraction, 1.0 - ownFraction );

    if ( ownFraction > 0.0 || sharedFraction > 0.0 )
    {
        //clip to the track so the fills take the rounded ends with them rather
        //than squaring off the left edge or spilling past the right one
        [NSGraphicsContext saveGraphicsState];
        [trackPath addClip];

        //drawn behind this volume's own segment, so the accent colour always
        //starts at the left edge and the eye reads the row's own share first
        if ( sharedFraction > 0.0 )
        {
            NSRect shared = track;
            shared.origin.x += barWidth * ownFraction;
            shared.size.width = barWidth * sharedFraction;

            [sharedColor set];
            NSRectFill( shared );
        }

        if ( ownFraction > 0.0 )
        {
            NSRect used = track;
            used.size.width = barWidth * ownFraction;

            [usedColor set];
            NSRectFill( used );
        }

        [NSGraphicsContext restoreGraphicsState];
    }

    [borderColor set];
    [trackPath stroke];
}

@end
