//
//  FileTypeColors.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on Sun Oct 05 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "FileTypeColors.h"
#import <TreeMapView/TMVCushionRenderer.h>

@implementation FileTypeColors

+ (FileTypeColors*) instance
{
    static FileTypeColors * _instance = nil;

    if ( _instance == nil )
        _instance = [[[self class] alloc] init];

    return _instance;
}

- (id) init
{
    self = [super init];
	
    _colors = [[NSMutableDictionary alloc] init];

#define COLOR(r,g,b) [NSColor colorWithCalibratedRed: r green: g blue: b alpha: 1.0]

    //Twelve hues, one every 30 degrees round the colour circle.
    //
    //What makes a colour look washed out here is not how light it is but how
    //close its three components are: shading multiplies all three by the same
    //number, so it changes value and leaves saturation alone. A first attempt at
    //"lighter" raised every component to around 0.8, which left barely a third
    //between the highest and lowest — light, and grey. These keep a high peak
    //(0.95 or so) and let the other components fall to around 0.4, which is what
    //makes the hue actually read.
    //
    //Their means land between 0.55 and 0.75, comfortably under
    //TMVMaxColorBrightness, so +normalizeColor: leaves them alone. A saturated
    //colour has a lower mean than a pale one at the same peak, which is why
    //raising the cap and raising saturation do not fight each other.
    _predefinedColors = [[NSMutableArray alloc] initWithObjects:
        COLOR(0.38, 0.68, 0.96),    //azure
        COLOR(0.96, 0.44, 0.42),    //red
        COLOR(0.42, 0.82, 0.48),    //green
        COLOR(0.32, 0.80, 0.88),    //cyan
        COLOR(0.68, 0.48, 0.94),    //violet
        COLOR(0.96, 0.85, 0.35),    //yellow
        COLOR(0.98, 0.63, 0.32),    //orange
        COLOR(0.97, 0.50, 0.72),    //pink
        COLOR(0.70, 0.88, 0.38),    //lime
        COLOR(0.36, 0.85, 0.68),    //spring green
        COLOR(0.50, 0.55, 0.95),    //blue
        COLOR(0.88, 0.48, 0.90),    //magenta
        nil];

#undef COLOR

    unsigned i;
    for ( i = 0; i < [_predefinedColors count]; i++ )
    {
        NSColor *color = [_predefinedColors objectAtIndex: i];
        [_predefinedColors replaceObjectAtIndex: i withObject: [TMVCushionRenderer normalizeColor: color]];
    }
    
    return self;
}

- (void) reset
{
	[_colors removeAllObjects];
}


- (NSColor *) colorForItem: (FSItem*) item
{
    return [self colorForKind: [item kindName]];
}

- (NSColor *) colorForKind: (NSString*) kind
{
    NSColor *color = [_colors objectForKey: kind];

    if ( color == nil )
    {
        if ( [_predefinedColors count] > [_colors count] )
        {
            color = [_predefinedColors objectAtIndex: [_colors count]];

            [_colors setObject: color forKey: kind];
        }
        else
        {
            //Past the palette, kinds get greys. This used to start at
            //count * 0.05 with the 0.6 offset commented out, so the thirteenth
            //kind came out pure black and the next few nearly so. The ramp now
            //runs light to mid and wraps, which keeps them apart from each other
            //without any of them turning into a hole in the map.
            const NSUInteger step = [_colors count] - [_predefinedColors count];
            const CGFloat rgbComponent = 0.86 - ( step % 6 ) * 0.07;

            color = [NSColor colorWithCalibratedRed: rgbComponent green: rgbComponent blue: rgbComponent alpha: 1.0];

            color = [TMVCushionRenderer normalizeColor: color];

            [_colors setObject: color forKey: kind];
        }
    }

    return color;
}

@end
