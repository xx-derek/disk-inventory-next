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
//On a dark ground the same shading glares: a cell that reaches its full base
//colour at the centre is a bright patch on near-black, and the design's dark
//board draws the cushions with a deeper shadow instead. The README puts it as
//CSS opacities - white inset ~45% down to ~30%, shadow ~26% up to ~42% - which
//do not map one to one onto this renderer, because here the lit peak is always
//exactly the base colour and there is no separate highlight to lower. Deepening
//the shadow is the whole move, so the dark pair simply lowers the floor.
//
//The sum stays 1.0 in both, which is what guarantees no pixel can exceed its
//base colour. This is the one place in the application that reads the
//appearance while drawing: these are numbers, not colours, so they cannot come
//from the asset catalog.
static const double Ia = 0.68;
static const double Is = 0.32;

//A mild deepening, not the dramatic one the CSS figures suggest. The design's
//dark board draws cells that are still bright and saturated; read literally,
//"raise the shadow to 42%" would take them well below that, because here the
//lit peak is the base colour itself and lowering the floor is the only lever.
//
//Not settled by measurement: the board's cells are mostly narrow strips, where
//a dome reads as a faint vertical gradient, while a large square shows the same
//dome plainly. Comparing the two is comparing geometries. Worth re-checking
//against a real scan in dark once the sidebar lands and a screenshot is
//comparable.
//Classic mode is the original application's rendering, not the new one with old
//shading: the pair below is what Disk Inventory X drew with, before the floor
//was raised to keep saturated colours out of the mud. It goes with the original
//palette, and only with it - 0.10 under the current pastels would wash out, and
//0.68 under the original primaries is what made them look flat.
static const double IaClassic = 0.10;
static const double IsClassic = 0.90;

//The original never had a dark mode to be designed against. A floor of 0.10 puts
//the rim of every cell at a tenth of its colour - near black - which reads as
//modelling on a white window and as a hole on a dark one: the map sinks into the
//background instead of sitting on it. The floor is raised for dark, which is the
//opposite of what the modern pair does (0.68 down to 0.62, deepening the shadow
//so a full-strength cell does not glare). Same ground, opposite problems,
//because the two palettes sit at opposite ends of the range.
//
//0.30 measured: over /System/Library/Frameworks in dark, mean luma is 0.371 at
//the original 0.10, 0.487 here, 0.545 at 0.42. Deliberately not pushed to the
//modern rim's 0.708 - the deep shading *is* the classic look, and flattening it
//to match would leave the setting offering nothing.
//
//It cannot be taken the rest of the way from here in any case, and the reason is
//the palette rather than the floor: the original's first colour is pure blue,
//whose luma is 0.072 at full strength - darker than the #1c1b1a the map sits on.
//A blue cell is dimmer than its own background however high the floor goes. That
//was never a defect on the white window this was drawn for.
static const double IaClassicDark = 0.30;
static const double IsClassicDark = 0.70;

static const double IaDark = 0.62;
static const double IsDark = 0.38;

//Set from the view before it shades a bitmap; see TreeMapView -drawInCache,
//which also invalidates the cache when the appearance changes.
static BOOL g_usesDarkShading = NO;

//Two shading models, selectable because they answer different questions.
//
//The classic cushion - a parabola per nesting level, accumulated - is what the
//algorithm's paper describes and what this application has always looked like.
//It encodes *depth*: a folder reads as one raised region with its contents
//modelled on top, which is how a treemap showed structure before anyone could
//afford a border on every cell.
//
//The rim is the design's: a bevel of fixed width around each cell, flat inside,
//with no accumulation. It encodes *extent* - where this cell begins and ends -
//and nothing else. It reads better on a dense map, because a parabola scaled to
//its cell spreads across a large rectangle as a soft radial gradient, which is
//what made big groups glow.
//
//Both are needed rather than one being simply better: the map now draws a
//separator between every pair of cells, which does the rim's job too, so on a
//shallow tree the rim can look flat and characterless - and on a deep one the
//classic look is the noise it was accused of being.
static BOOL g_usesRimShading = YES;

//How far in the bevel reaches, in points, and how strongly it darkens and
//lightens at the very edge.
//
//The rim is composited, not shaded. Running it through the cushion's light model
//was the obvious thing and it does not work: the light points almost straight
//down (Lz = 0.976), so tilting the surface barely changes the angle to it. A
//45-degree bevel came out spanning 0.879 to 0.923 of the base colour - a four
//percent range, which is why the cells looked flat and the design's grey edge
//was missing. Steepening it does not help either; past a point the slope swamps
//Lz and *both* sides go dark.
//
//So these are the design's own figures, straight from its two inset shadows:
//a white one from the top left and a black one from the bottom right, blurred.
//The dark board weights them .30 and .42, the light board .45 and .26 - the
//shadow is the heavier of the two on dark, and the highlight on light.
static const double TMVRimWidth = 18.0;

static const double TMVRimHighlight     = 0.45;
static const double TMVRimShadow        = 0.26;
static const double TMVRimHighlightDark = 0.30;
static const double TMVRimShadowDark    = 0.42;

//Never more than this fraction of a cell's short side, so a small cell gets a
//scaled-down bevel rather than two overlapping ones.
static const double TMVMaxRimFraction = 0.34;

//Layout is in backing pixels; the rim is specified in points, so it has to be
//multiplied up or it would be half as wide on a Retina display.
static double g_backingScale = 1.0;

//Ceiling on a base colour's mean component, applied by +normalizeColor:.
//Nothing can clip - the brightest a pixel gets is Ia + Is = 1 times the base
//colour - so this only decides how light a cell is allowed to be. It was 0.6,
//which dimmed any pale colour back to a muddy mid-tone.
static const double TMVMaxColorBrightness = 0.85;

//The original palette leads with pure blue, whose luma is 0.072 at full
//strength - darker than the #1c1b1a the map sits on, so a blue cell is dimmer
//than its own background. Pure red (0.213) and pure magenta are not much better.
//None of that mattered on the white window the palette was drawn for, and
//upstream never had a dark mode for it to matter in.
//
//So in dark, and only in dark, a classic colour too dark to read is lifted
//toward white until its luma reaches this floor. Toward white rather than
//brighter, because these are already at full brightness - pure blue is
//saturation 1, brightness 1; its luma is low because blue simply is dark, and
//the only way up is to let the other components in. Luma is linear in the
//components and white is 1.0, so the blend lands exactly on the floor.
//
//It leaves everything already above the floor alone, so the pastel half of the
//palette and the yellows and cyans are untouched: this is not a re-tint of the
//classic look, it is the three colours that were unusable being made usable.
static const double TMVClassicDarkLumaFloor = 0.35;

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

	if ( !g_usesRimShading && g_usesDarkShading )
	{
		const double luma = 0.2126 * baseRed + 0.7152 * baseGreen + 0.0722 * baseBlue;

		if ( luma < TMVClassicDarkLumaFloor && luma < 1.0 )
		{
			const double towardWhite = ( TMVClassicDarkLumaFloor - luma ) / ( 1.0 - luma );

			baseRed   += ( 1.0 - baseRed   ) * towardWhite;
			baseGreen += ( 1.0 - baseGreen ) * towardWhite;
			baseBlue  += ( 1.0 - baseBlue  ) * towardWhite;
		}
	}

	unsigned char *bitmapData = [bitmap bitmapData];
	if ( bitmapData == NULL )
		return;

	const NSInteger bytesPerRow   = [bitmap bytesPerRow];
	const NSInteger bytesPerPixel = [bitmap bitsPerPixel] / 8;

	double ambient, diffuse;

	if ( !g_usesRimShading )
	{
		ambient = g_usesDarkShading ? IaClassicDark : IaClassic;
		diffuse = g_usesDarkShading ? IsClassicDark : IsClassic;
	}
	else
	{
		ambient = g_usesDarkShading ? IaDark : Ia;
		diffuse = g_usesDarkShading ? IsDark : Is;
	}

	if ( g_usesRimShading )
	{
		[self renderRimInBitmap: bitmap
						 xStart: xStart yStart: yStart xEnd: xEnd yEnd: yEnd
						  color: (double[]){ baseRed, baseGreen, baseBlue }
						ambient: ambient diffuse: diffuse];
		return;
	}

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

			double brightness = diffuse * cosa;
			brightness = ( brightness < 0.0 ) ? ambient : ( brightness + ambient );

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

//The bevel. The slope is a half-cosine ramp from the edge inwards, so the
//surface leaves the edge flat, tilts hardest half way in and is flat again at
//the top - a blurred chamfer rather than a crease, which is what the design's
//blurred inset shadows draw.
//
//The x profile is the same for every row and the y profile the same for every
//column, so both are computed once. The interior - every pixel more than a rim
//in from all four edges - has a flat surface and therefore one constant colour,
//which is most of a large cell and costs nothing.
- (void) renderRimInBitmap: (NSBitmapImageRep*) bitmap
					xStart: (NSInteger) xStart yStart: (NSInteger) yStart
					  xEnd: (NSInteger) xEnd   yEnd: (NSInteger) yEnd
					 color: (const double*) base
				   ambient: (double) ambient diffuse: (double) diffuse
{
	unsigned char *bitmapData = [bitmap bitmapData];
	const NSInteger bytesPerRow   = [bitmap bytesPerRow];
	const NSInteger bytesPerPixel = [bitmap bitsPerPixel] / 8;

	const double shortSide = MIN( NSWidth(_rect), NSHeight(_rect) );
	double rim = TMVRimWidth * g_backingScale;

	if ( rim > shortSide * TMVMaxRimFraction )
		rim = shortSide * TMVMaxRimFraction;

	const NSInteger width = xEnd - xStart, height = yEnd - yStart;

	if ( width <= 0 || height <= 0 )
		return;

	//Four falloffs, one per edge, each 1 at the edge and 0 a rim in. Squared, so
	//most of the weight sits close to the edge the way a blur does rather than
	//ramping evenly across the band.
	double *lightX = calloc( (size_t) width,  sizeof(double) );
	double *darkX  = calloc( (size_t) width,  sizeof(double) );
	double *lightY = calloc( (size_t) height, sizeof(double) );
	double *darkY  = calloc( (size_t) height, sizeof(double) );

	if ( lightX == NULL || darkX == NULL || lightY == NULL || darkY == NULL )
	{
		free( lightX ); free( darkX ); free( lightY ); free( darkY );
		return;
	}

	if ( rim > 0.0 )
	{
		for ( NSInteger i = 0; i < width; i++ )
		{
			const double x = xStart + i + 0.5;
			const double fromLow = x - NSMinX(_rect), fromHigh = NSMaxX(_rect) - x;

			if ( fromLow < rim )  { const double t = 1.0 - fromLow  / rim; lightX[i] = t * t; }
			if ( fromHigh < rim ) { const double t = 1.0 - fromHigh / rim; darkX[i]  = t * t; }
		}

		for ( NSInteger j = 0; j < height; j++ )
		{
			const double y = yStart + j + 0.5;
			const double fromLow = y - NSMinY(_rect), fromHigh = NSMaxY(_rect) - y;

			if ( fromLow < rim )  { const double t = 1.0 - fromLow  / rim; lightY[j] = t * t; }
			if ( fromHigh < rim ) { const double t = 1.0 - fromHigh / rim; darkY[j]  = t * t; }
		}
	}

	const double highlight = g_usesDarkShading ? TMVRimHighlightDark : TMVRimHighlight;
	const double shadow    = g_usesDarkShading ? TMVRimShadowDark    : TMVRimShadow;

	for ( NSInteger iy = yStart; iy < yEnd; iy++ )
	{
		const double lightRow = lightY[iy - yStart], darkRow = darkY[iy - yStart];

		unsigned char *pixel = bitmapData + iy * bytesPerRow + xStart * bytesPerPixel;

		for ( NSInteger ix = xStart; ix < xEnd; ix++, pixel += bytesPerPixel )
		{
			//the strongest of the two edges each shadow comes from, not their
			//sum, so a corner does not go to twice the weight
			const double lightWeight = MAX( lightRow, lightX[ix - xStart] ) * highlight;
			const double darkWeight  = MAX( darkRow,  darkX [ix - xStart] ) * shadow;

			double red = base[0], green = base[1], blue = base[2];

			//white in from the top left, black in from the bottom right
			red   += ( 1.0 - red   ) * lightWeight;
			green += ( 1.0 - green ) * lightWeight;
			blue  += ( 1.0 - blue  ) * lightWeight;

			red   *= ( 1.0 - darkWeight );
			green *= ( 1.0 - darkWeight );
			blue  *= ( 1.0 - darkWeight );

			pixel[0] = (unsigned char) ( red   * 255.0 + 0.5 );
			pixel[1] = (unsigned char) ( green * 255.0 + 0.5 );
			pixel[2] = (unsigned char) ( blue  * 255.0 + 0.5 );
		}
	}

	free( lightX ); free( darkX ); free( lightY ); free( darkY );
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

+ (BOOL) usesDarkShading
{
	return g_usesDarkShading;
}

+ (void) setUsesDarkShading: (BOOL) dark
{
	g_usesDarkShading = dark;
}

+ (BOOL) usesRimShading
{
	return g_usesRimShading;
}

+ (void) setUsesRimShading: (BOOL) rim
{
	g_usesRimShading = rim;
}

+ (void) setBackingScale: (double) scale
{
	g_backingScale = ( scale > 0.0 ) ? scale : 1.0;
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
