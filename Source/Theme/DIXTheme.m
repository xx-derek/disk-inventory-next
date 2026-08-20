//
//  DIXTheme.m
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

#import "DIXTheme.h"

//The design's tracking is expressed in em. Kerning is in points, so it has to
//be multiplied out per size rather than set once.
static const CGFloat kDisplayTrackingEm      = -0.02;
static const CGFloat kSectionLabelTrackingEm =  0.10;

static const CGFloat kSectionLabelSize = 11.0;

//Named colours are looked up once. -colorNamed: hands back a dynamic colour
//that resolves per appearance when it is drawn, so caching the object is safe
//- what must not be cached is a *resolved* colour, which is why nothing here
//calls -colorUsingColorSpace: or -blendedColorWithFraction:ofColor:.
static NSColor* NamedColor( NSString *name, NSColor *fallback )
{
	NSColor *color = [NSColor colorNamed: name];

	if ( color == nil )
	{
		//an asset that failed to compile into Assets.car would otherwise be an
		//invisible control rather than something anyone could diagnose
		NSLog( @"no colour named '%@' in the asset catalog", name );
		return fallback;
	}

	return color;
}

@implementation DIXTheme

#pragma mark --------surfaces-----------------

+ (NSColor*) ground
{
	return [NSColor windowBackgroundColor];
}

+ (NSColor*) surface
{
	return [NSColor controlBackgroundColor];
}

+ (NSColor*) chrome
{
	//A dynamic colour rather than a resolved one: the provider runs again for
	//each appearance, so this keeps flipping. Resolving once and caching the
	//result - which is what -blendedColorWithFraction:ofColor: would force -
	//would freeze it at whatever appearance happened to be current first.
	static NSColor *color = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{
		color = [NSColor colorWithName: @"DIXChrome"
					   dynamicProvider: ^NSColor* ( NSAppearance *appearance )
		{
			NSAppearanceName matched =
				[appearance bestMatchFromAppearancesWithNames: @[ NSAppearanceNameAqua,
																  NSAppearanceNameDarkAqua ]];

			//light chrome sits below the white content; dark chrome sits above
			//the near-black content, which is the direction macOS itself moves
			if ( [matched isEqualToString: NSAppearanceNameDarkAqua] )
				return [NSColor colorWithSRGBRed: 0x2A / 255.0
										   green: 0x2A / 255.0
											blue: 0x2A / 255.0
										   alpha: 1.0];

			return [NSColor colorWithSRGBRed: 0xF4 / 255.0
									   green: 0xF3 / 255.0
										blue: 0xF2 / 255.0
									   alpha: 1.0];
		}];
	});

	return color;
}

+ (NSColor*) sidebar
{
	//Same value as -ground, and deliberately so: the design's ground and
	//sidebar differ by about one percent, and on macOS that separation comes
	//from the sidebar material rather than from a flat fill.
	return [NSColor windowBackgroundColor];
}

+ (NSColor*) selectedRowFill
{
	//The neutral grey the design draws, not the emphasized blue: these rows are
	//a legend and a source list, where selection is a state rather than a focus.
	return [NSColor unemphasizedSelectedContentBackgroundColor];
}

#pragma mark --------text-----------------

+ (NSColor*) ink
{
	return [NSColor labelColor];
}

+ (NSColor*) bodyText
{
	//The design separates body copy (#56524f) from ink (#201e1d). AppKit makes
	//that distinction with size and weight rather than with two blacks, and a
	//third label colour between label and secondary would read as a bug in dark
	//mode. Both map to labelColor on purpose.
	return [NSColor labelColor];
}

+ (NSColor*) secondaryText
{
	return [NSColor secondaryLabelColor];
}

+ (NSColor*) tertiaryText
{
	return [NSColor tertiaryLabelColor];
}

#pragma mark --------lines-----------------

+ (NSColor*) hairline
{
	return [NSColor separatorColor];
}

+ (NSColor*) rule
{
	return [NSColor labelColor];
}

+ (NSColor*) controlBorder
{
	return [NSColor separatorColor];
}

#pragma mark --------accent-----------------

+ (NSColor*) accent
{
	return NamedColor( @"DIXAccent", [NSColor systemRedColor] );
}

+ (NSColor*) accentPressed
{
	return NamedColor( @"DIXAccentPressed", [NSColor systemRedColor] );
}

+ (NSColor*) accentTint
{
	return NamedColor( @"DIXAccentTint", [NSColor controlBackgroundColor] );
}

+ (NSColor*) positive
{
	return NamedColor( @"DIXPositive", [NSColor systemGreenColor] );
}

+ (NSColor*) neutralFill
{
	//Literal rather than semantic, unlike everything else here. This is the
	//"other space" tile, which sits inside the treemap against a fixed twelve
	//hue palette - it belongs to that palette's world, not to the window
	//chrome, and following the appearance would make it disappear into a dark
	//background while the coloured cells beside it stayed put.
	return [NSColor colorWithSRGBRed: 0xB9 / 255.0
							   green: 0xB5 / 255.0
								blue: 0xB2 / 255.0
							   alpha: 1.0];
}

#pragma mark --------type-----------------

+ (NSFont*) displayFontOfSize: (CGFloat) size
{
	return [NSFont systemFontOfSize: size weight: NSFontWeightBold];
}

+ (NSFont*) sectionLabelFont
{
	return [NSFont systemFontOfSize: kSectionLabelSize weight: NSFontWeightBold];
}

+ (NSFont*) tabularFontOfSize: (CGFloat) size
{
	return [NSFont monospacedDigitSystemFontOfSize: size weight: NSFontWeightRegular];
}

+ (NSFont*) monoFontOfSize: (CGFloat) size
{
	return [NSFont monospacedSystemFontOfSize: size weight: NSFontWeightRegular];
}

+ (NSDictionary<NSAttributedStringKey, id>*) displayAttributesOfSize: (CGFloat) size
															   color: (NSColor*) color
{
	return @{
		NSFontAttributeName:            [self displayFontOfSize: size],
		NSForegroundColorAttributeName: ( color != nil ? color : [self ink] ),
		NSKernAttributeName:            @( kDisplayTrackingEm * size ),
	};
}

+ (NSDictionary<NSAttributedStringKey, id>*) sectionLabelAttributes
{
	return @{
		NSFontAttributeName:            [self sectionLabelFont],
		NSForegroundColorAttributeName: [self secondaryText],
		NSKernAttributeName:            @( kSectionLabelTrackingEm * kSectionLabelSize ),
	};
}

#pragma mark --------metrics-----------------

+ (CGFloat) cornerRadius                    { return 6.0; }
+ (CGFloat) ruleThickness                   { return 2.0; }
+ (CGFloat) hairlineThickness               { return 1.0; }
+ (CGFloat) kindChipSize                    { return 10.0; }

+ (CGFloat) sidebarWidth                    { return 244.0; }
+ (CGFloat) inspectorWidth                  { return 300.0; }
+ (CGFloat) fileListWidth                   { return 320.0; }

+ (CGFloat) bothModeMinimumContentWidth     { return 1000.0; }

@end
