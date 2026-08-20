//
//  TMVCushionRenderer.h
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

#import <Cocoa/Cocoa.h>

//Shades one treemap cell as a "cushion": a parabolic height field is accumulated
//per cell, one ridge per nesting level, and the surface is then lit by a fixed
//directional light. The technique is described in
//
//    Jarke J. van Wijk and Huub van de Wetering, "Cushion Treemaps: Visualization
//    of Hierarchical Information", Proc. IEEE Symposium on Information
//    Visualization (InfoVis '99), 1999.
//
//The height field is separable, so it is stored as four coefficients: the
//quadratic and linear terms of x (surface[0], surface[1]) and of y
//(surface[2], surface[3]).

enum { TMVSurfaceCoefficientCount = 4 };

@interface TMVCushionRenderer : NSObject
{
	NSRect _rect;
	NSColor *_color;
	double _surface[TMVSurfaceCoefficientCount];
}

- (id) initWithRect: (NSRect) rect;

@property (assign) NSRect rect;
@property (retain) NSColor *color;

- (const double*) surface;
- (void) setSurface: (const double*) surface;

//adds one parabolic ridge over the receiver's rect; called once per nesting
//level, with a height factor that shrinks as the hierarchy gets deeper
- (void) addRidgeByHeightFactor: (double) heightFactor;

//shades the receiver's rect into the bitmap; the rect is in bitmap pixel coords
- (void) renderCushionInBitmap: (NSBitmapImageRep*) bitmap;

//Scales a color so that its three components sum to a fixed brightness, keeping
//the hue. Cushion shading multiplies the base color by a brightness that can
//exceed 1, so base colors have to start out dim enough to leave headroom.
//Whether cushions are shaded for a dark ground. Set by the view before it
//builds its bitmap; global rather than per-renderer because a treemap holds
//tens of thousands of these and they all shade the same way.
+ (BOOL) usesDarkShading;

//Which of the two shading models to use, and the backing scale the rim's width
//is expressed against. See -renderCushionInBitmap: for what they select between.
+ (BOOL) usesRimShading;
+ (void) setUsesRimShading: (BOOL) rim;
+ (void) setBackingScale: (double) scale;
+ (void) setUsesDarkShading: (BOOL) dark;

+ (NSColor*) normalizeColor: (NSColor*) color;
+ (void) normalizeColorRed: (double*) red green: (double*) green blue: (double*) blue;

@end
