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

//Every role below is an asset-catalog colour with an Any/Dark pair, taken from
//the handoff's dark-mode table. That table supersedes the earlier decision to
//map these onto semantic NSColors, and the reason is measurable: macOS 26
//resolves -windowBackgroundColor, -controlBackgroundColor and
//-textBackgroundColor to the same value (#ffffff light, #1e1e1e dark), while
//the design leans on five distinct surfaces. Semantics cannot say what the
//design says.
//
//The cost, recorded so it is a choice rather than an oversight: the sidebar no
//longer separates itself with a material and no longer tints with the desktop.
//Where a real material is wanted - a genuine NSVisualEffectView sidebar - it
//can still be used over these, but the flat tones are now the specification.
//
//The semantic colours remain as fallbacks inside NamedColor(), so a colorset
//that failed to compile degrades to something sensible rather than to nil.

#pragma mark --------surfaces-----------------

+ (NSColor*) ground
{
	return NamedColor( @"DIXGround", [NSColor windowBackgroundColor] );
}

+ (NSColor*) surface
{
	return NamedColor( @"DIXSurface", [NSColor controlBackgroundColor] );
}

+ (NSColor*) chrome
{
	return NamedColor( @"DIXChrome", [NSColor windowBackgroundColor] );
}

+ (NSColor*) toolbar
{
	return NamedColor( @"DIXToolbar", [NSColor windowBackgroundColor] );
}

+ (NSColor*) sidebar
{
	return NamedColor( @"DIXSidebar", [NSColor windowBackgroundColor] );
}

+ (NSColor*) well
{
	return NamedColor( @"DIXWell", [NSColor textBackgroundColor] );
}

+ (NSColor*) controlFill
{
	return NamedColor( @"DIXControlFill", [NSColor controlColor] );
}

+ (NSColor*) selectedRowFill
{
	//The neutral grey the design draws, not the emphasized blue: these rows are
	//a legend and a source list, where selection is a state rather than a focus.
	return NamedColor( @"DIXSelectedRow", [NSColor unemphasizedSelectedContentBackgroundColor] );
}

#pragma mark --------text-----------------

+ (NSColor*) ink
{
	return NamedColor( @"DIXInk", [NSColor labelColor] );
}

+ (NSColor*) bodyText
{
	//Its own value again. Under the semantic mapping this collapsed onto
	//labelColor, because AppKit expresses the difference with weight and size
	//rather than with two blacks; the design does give it a value of its own.
	return NamedColor( @"DIXBodyText", [NSColor labelColor] );
}

+ (NSColor*) secondaryText
{
	return NamedColor( @"DIXSecondaryText", [NSColor secondaryLabelColor] );
}

+ (NSColor*) tertiaryText
{
	return NamedColor( @"DIXTertiaryText", [NSColor tertiaryLabelColor] );
}

#pragma mark --------lines-----------------

+ (NSColor*) hairline
{
	//Pane borders: between the sidebar and the map, above the status bar.
	return NamedColor( @"DIXPaneBorder", [NSColor separatorColor] );
}

+ (NSColor*) rowSeparator
{
	//1pt, between rows within a section - lighter than a pane border.
	return NamedColor( @"DIXRowSeparator", [NSColor separatorColor] );
}

+ (NSColor*) rule
{
	//The 2pt rules between major sections. Same value as ink in both
	//appearances - the design's table lists them as one - but a distinct role,
	//because a rule that stopped following the text colour would be a bug and
	//not a redesign. Note it *inverts* in dark, to #f0eeec, and keeps its
	//weight: never soften a rule to a hairline because dark contrast reads high.
	return NamedColor( @"DIXInk", [NSColor labelColor] );
}

+ (NSColor*) controlBorder
{
	return NamedColor( @"DIXControlBorder", [NSColor separatorColor] );
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

+ (NSColor*) onAccent
{
	return NamedColor( @"DIXOnAccent", [NSColor whiteColor] );
}

+ (NSColor*) positive
{
	return NamedColor( @"DIXPositive", [NSColor systemGreenColor] );
}

+ (NSColor*) neutralFill
{
	//The "elsewhere" tile. This was literal and commented as deliberately not
	//following the appearance - the design's table overrides that and gives it
	//#555250 in dark. The reasoning behind the old comment still holds for the
	//*kind* colours, which really are data and really do not change; this tile
	//is not one of them.
	return NamedColor( @"DIXNeutralFill", [NSColor systemGrayColor] );
}

+ (NSColor*) freeSpaceFill
{
	return NamedColor( @"DIXFreeSpace", [NSColor windowBackgroundColor] );
}

+ (NSColor*) freeSpaceDash
{
	return NamedColor( @"DIXFreeSpaceDash", [NSColor separatorColor] );
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
