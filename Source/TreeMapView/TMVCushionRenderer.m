//
//  TMVCushionRenderer.m
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

#import "TMVCushionRenderer.h"
#import <math.h>

//Direction of the light, pointing up and to the left. The view draws flipped
//(y grows downwards), so a negative y component puts the highlight at the top.
static const double Lx = -0.09759;
static const double Ly = -0.19518;
static const double Lz =  0.97590;

//Ambient and diffuse contributions. They sum to 1, so a fully lit pixel reaches
//exactly the cell's base color and nothing can clip.
//
//Ia is the floor: what a pixel gets where the cushion turns away from the light.
//At the 0.10 this started with, the rim of every cell fell to a tenth of its
//colour - practically black - and the contrast against the lit centre read as a
//glow rather than as a curved surface.
//
//0.68 is high because the palette is saturated. Shading multiplies all three
//components by the same number, so it never desaturates, only darkens - and a
//darkened saturated colour is a muddy one, orange going to brown. Keeping the
//floor high keeps the hues clean; the dome is still plainly visible because the
//remaining 0.32 of range is spread over a curve, not a gradient.
static const double Ia = 0.68;
static const double Is = 0.32;

//Ceiling on a base colour's mean component, applied by +normalizeColor:.
//Nothing can clip - the brightest a pixel gets is Ia + Is = 1 times the base
//colour - so this only decides how light a cell is allowed to be. It was 0.6,
//which dimmed any pale colour back to a muddy mid-tone.
static const double TMVMaxColorBrightness = 0.85;

static NSColor *g_defaultCushionColor = nil;

@implementation TMVCushionRenderer

+ (void) initialize
{
	if ( self == [TMVCushionRenderer class] )
		g_defaultCushionColor = [self normalizeColor: [NSColor colorWithCalibratedWhite: 0.75 alpha: 1.0]];
}

- (id) init
{
	return [self initWithRect: NSZeroRect];
}

- (id) initWithRect: (NSRect) rect
{
	self = [super init];
	if ( self == nil )
		return nil;

	_rect = rect;
	_color = g_defaultCushionColor;

	//a flat surface: no ridges added yet
	for ( int i = 0; i < TMVSurfaceCoefficientCount; i++ )
		_surface[i] = 0.0;

	return self;
}


- (NSRect) rect
{
	return _rect;
}

- (void) setRect: (NSRect) rect
{
	_rect = rect;
}

- (NSColor*) color
{
	return _color;
}

- (void) setColor: (NSColor*) color
{
	if ( color == nil )
		color = g_defaultCushionColor;

	_color = color;
}

- (const double*) surface
{
	return _surface;
}

- (void) setSurface: (const double*) surface
{
	if ( surface == NULL )
		return;

	for ( int i = 0; i < TMVSurfaceCoefficientCount; i++ )
		_surface[i] = surface[i];
}

#pragma mark --------cushion geometry-----------------

//Adds a parabola over one axis of the cell. The parabola is zero at both edges
//and reaches "heightFactor" in the middle, so ridges from successive nesting
//levels accumulate into the familiar nested-pillow look.
static inline void AddRidgeOnAxis( double x1, double x2, double heightFactor,
								   double *quadraticTerm, double *linearTerm )
{
	const double width = x2 - x1;

	//degenerate cells carry no ridge; guarding here keeps the division safe
	if ( width <= 0.0 )
		return;

	*linearTerm    += 4.0 * heightFactor * ( x2 + x1 ) / width;
	*quadraticTerm -= 4.0 * heightFactor / width;
}

- (void) addRidgeByHeightFactor: (double) heightFactor
{
	AddRidgeOnAxis( NSMinX(_rect), NSMaxX(_rect), heightFactor, &_surface[0], &_surface[1] );
	AddRidgeOnAxis( NSMinY(_rect), NSMaxY(_rect), heightFactor, &_surface[2], &_surface[3] );
}

#pragma mark --------rendering-----------------

- (void) renderCushionInBitmap: (NSBitmapImageRep*) bitmap
{
	NSParameterAssert( bitmap != nil );

	//the cell rect is in bitmap pixel coords; clip it to the bitmap
	const NSInteger pixelsWide = [bitmap pixelsWide];
	const NSInteger pixelsHigh = [bitmap pixelsHigh];

	NSInteger xStart = (NSInteger) floor( NSMinX(_rect) );
	NSInteger yStart = (NSInteger) floor( NSMinY(_rect) );
	NSInteger xEnd   = (NSInteger) ceil( NSMaxX(_rect) );
	NSInteger yEnd   = (NSInteger) ceil( NSMaxY(_rect) );

	if ( xStart < 0 ) xStart = 0;
	if ( yStart < 0 ) yStart = 0;
	if ( xEnd > pixelsWide ) xEnd = pixelsWide;
	if ( yEnd > pixelsHigh ) yEnd = pixelsHigh;

	if ( xStart >= xEnd || yStart >= yEnd )
		return;

	//base color, in a device-independent space we can read components from
	NSColor *rgbColor = [_color colorUsingColorSpace: [NSColorSpace genericRGBColorSpace]];
	if ( rgbColor == nil )
		rgbColor = [NSColor grayColor];

	CGFloat baseRed = 0, baseGreen = 0, baseBlue = 0, baseAlpha = 1;
	[rgbColor getRed: &baseRed green: &baseGreen blue: &baseBlue alpha: &baseAlpha];

	unsigned char *bitmapData = [bitmap bitmapData];
	if ( bitmapData == NULL )
		return;

	const NSInteger bytesPerRow   = [bitmap bytesPerRow];
	const NSInteger bytesPerPixel = [bitmap bitsPerPixel] / 8;

	//derivatives of the height field; the normal at a pixel is (nx, ny, 1)
	const double nxFactor = 2.0 * _surface[0];
	const double nxOffset = _surface[1];
	const double nyFactor = 2.0 * _surface[2];
	const double nyOffset = _surface[3];

	for ( NSInteger iy = yStart; iy < yEnd; iy++ )
	{
		//ny is constant along a row
		const double ny = -( nyFactor * ( iy + 0.5 ) + nyOffset );
		const double nyLy = ny * Ly;
		const double nySquaredPlusOne = ny * ny + 1.0;

		unsigned char *pixel = bitmapData + iy * bytesPerRow + xStart * bytesPerPixel;

		for ( NSInteger ix = xStart; ix < xEnd; ix++, pixel += bytesPerPixel )
		{
			const double nx = -( nxFactor * ( ix + 0.5 ) + nxOffset );

			//cosine of the angle between the surface normal and the light
			const double cosa = ( nx * Lx + nyLy + Lz ) / sqrt( nx * nx + nySquaredPlusOne );

			double brightness = Is * cosa;
			brightness = ( brightness < 0.0 ) ? Ia : ( brightness + Ia );

			double red   = baseRed   * brightness;
			double green = baseGreen * brightness;
			double blue  = baseBlue  * brightness;

			//a steep cushion can still overshoot; clip rather than wrap around
			if ( red   > 1.0 ) red   = 1.0;
			if ( green > 1.0 ) green = 1.0;
			if ( blue  > 1.0 ) blue  = 1.0;

			pixel[0] = (unsigned char) ( red   * 255.0 + 0.5 );
			pixel[1] = (unsigned char) ( green * 255.0 + 0.5 );
			pixel[2] = (unsigned char) ( blue  * 255.0 + 0.5 );
		}
	}
}

#pragma mark --------color normalization-----------------

+ (void) normalizeColorRed: (double*) red green: (double*) green blue: (double*) blue
{
	NSParameterAssert( red != NULL && green != NULL && blue != NULL );

	const double brightness = ( *red + *green + *blue ) / 3.0;

	//Only ever dim a color, never boost it. Boosting would drag every dark color
	//up to the same brightness, which would make deliberately dark cells (the
	//"other space" cell, say) indistinguishable from light ones.
	if ( brightness <= TMVMaxColorBrightness || brightness <= 0.0 )
		return;

	const double scale = TMVMaxColorBrightness / brightness;

	*red   *= scale;
	*green *= scale;
	*blue  *= scale;
}

+ (NSColor*) normalizeColor: (NSColor*) color
{
	NSColor *rgbColor = [color colorUsingColorSpace: [NSColorSpace genericRGBColorSpace]];
	if ( rgbColor == nil )
		return color;

	CGFloat red = 0, green = 0, blue = 0, alpha = 1;
	[rgbColor getRed: &red green: &green blue: &blue alpha: &alpha];

	double normalizedRed = red, normalizedGreen = green, normalizedBlue = blue;
	[self normalizeColorRed: &normalizedRed green: &normalizedGreen blue: &normalizedBlue];

	return [NSColor colorWithColorSpace: [NSColorSpace genericRGBColorSpace]
							 components: (CGFloat[]){ normalizedRed, normalizedGreen, normalizedBlue, alpha }
								  count: 4];
}

@end
