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

    //Twelve light, low-saturation hues rather than the saturated primaries this
    //started with. Cushion shading darkens a cell towards its rim, so a base
    //colour that is already fully saturated has nowhere to go but towards black,
    //which is what made the treemap read as glowing blobs. These sit around a
    //mean component of 0.8, are spaced right around the hue circle so adjacent
    //kinds stay tellable apart, and are close enough in luminance that no single
    //kind shouts over the others.
    _predefinedColors = [[NSMutableArray alloc] initWithObjects:
        COLOR(0.62, 0.76, 0.95),    //blue
        COLOR(0.96, 0.68, 0.64),    //coral
        COLOR(0.68, 0.87, 0.70),    //green
        COLOR(0.64, 0.86, 0.89),    //teal
        COLOR(0.83, 0.72, 0.93),    //purple
        COLOR(0.95, 0.90, 0.72),    //yellow
        COLOR(0.98, 0.82, 0.70),    //orange
        COLOR(0.96, 0.73, 0.85),    //pink
        COLOR(0.82, 0.91, 0.73),    //lime
        COLOR(0.72, 0.82, 0.92),    //sky
        COLOR(0.78, 0.76, 0.94),    //lavender
        COLOR(0.88, 0.83, 0.80),    //warm grey
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
