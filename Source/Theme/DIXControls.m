//
//  DIXControls.m
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

#import "DIXControls.h"
#import "DIXTheme.h"

#pragma mark --------kind chip-----------------

@implementation DIXKindChip

+ (instancetype) chipWithColor: (NSColor*) color
{
	DIXKindChip *chip = [[self alloc] initWithFrame: NSZeroRect];

	[chip setColor: color];

	return chip;
}

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_chipSize = [DIXTheme kindChipSize];
		[self setTranslatesAutoresizingMaskIntoConstraints: NO];
	}

	return self;
}

- (NSSize) intrinsicContentSize
{
	return NSMakeSize( _chipSize, _chipSize );
}

- (void) setChipSize: (CGFloat) chipSize
{
	if ( _chipSize == chipSize )
		return;

	_chipSize = chipSize;
	[self invalidateIntrinsicContentSize];
	[self setNeedsDisplay: YES];
}

- (void) setColor: (NSColor*) color
{
	_color = color;
	[self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) dirtyRect
{
	if ( _color == nil )
		return;

	//Centred rather than filling the frame, so a chip in a stack view that has
	//been given extra room stays the size the design asks for.
	const NSRect bounds = [self bounds];
	const NSRect chip = NSMakeRect( NSMidX(bounds) - _chipSize / 2.0,
									NSMidY(bounds) - _chipSize / 2.0,
									_chipSize, _chipSize );

	[_color set];
	NSRectFill( chip );	//square: no radius, this is a data element
}

@end

#pragma mark --------share bar-----------------

@implementation DIXShareBar

+ (instancetype) barWithFraction: (double) fraction fillColor: (NSColor*) fillColor
{
	DIXShareBar *bar = [[self alloc] initWithFrame: NSZeroRect];

	[bar setFraction: fraction];
	[bar setFillColor: fillColor];

	return bar;
}

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_trackColor = [DIXTheme barTrack];
		[self setTranslatesAutoresizingMaskIntoConstraints: NO];
	}

	return self;
}

- (void) setFraction: (double) fraction
{
	//Clamped rather than asserted: the fraction is a ratio of file sizes, and a
	//tree being refreshed under the view can legitimately produce a stale
	//numerator for one frame.
	if ( fraction < 0.0 )
		fraction = 0.0;
	else if ( fraction > 1.0 )
		fraction = 1.0;

	if ( _fraction == fraction )
		return;

	_fraction = fraction;
	[self setNeedsDisplay: YES];
}

- (void) setFillColor: (NSColor*) fillColor
{
	_fillColor = fillColor;
	[self setNeedsDisplay: YES];
}

- (void) setTrackColor: (NSColor*) trackColor
{
	_trackColor = trackColor;
	[self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) dirtyRect
{
	const NSRect bounds = [self bounds];

	[_trackColor set];
	NSRectFill( bounds );

	if ( _fraction <= 0.0 || _fillColor == nil )
		return;

	NSRect fill = bounds;
	fill.size.width = NSWidth( bounds ) * _fraction;

	//A share that rounds to less than a point still happened, and a bar that
	//draws nothing reads as zero rather than as "very small".
	if ( NSWidth( fill ) < 1.0 )
		fill.size.width = 1.0;

	[_fillColor set];
	NSRectFill( fill );
}

@end

#pragma mark --------the accent button-----------------

//NSButton draws its title in the system's label colour, which is unreadable on
//a saturated fill, so the title is set as an attributed string. That has to be
//redone whenever the button is enabled or disabled: an attributed title is not
//dimmed by AppKit the way a plain one is, so a disabled button would otherwise
//stay at full contrast and look live.
//
//The colour is +onAccent, not white. The dark accent (#ff5a3c) is light enough
//that a white label on it fails, so there it is near-black instead - which is
//also why the title has to be rebuilt when the appearance changes, since an
//attributed string holds a resolved colour rather than a dynamic one.
@interface DIXAccentButton : NSButton
@end

@implementation DIXAccentButton

- (void) dix_applyTitleColor
{
	NSColor *onAccent = [DIXTheme onAccent];

	NSColor *color = [self isEnabled] ? onAccent
									  : [onAccent colorWithAlphaComponent: 0.5];

	NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
	[centred setAlignment: NSTextAlignmentCenter];

	NSDictionary *attributes = @{
		NSForegroundColorAttributeName: color,
		NSFontAttributeName:            [self font] != nil ? [self font]
														   : [NSFont systemFontOfSize: [NSFont systemFontSize]],
		NSParagraphStyleAttributeName:  centred,
	};

	[self setAttributedTitle: [[NSAttributedString alloc] initWithString: [self title]
															 attributes: attributes]];
}

- (void) setEnabled: (BOOL) enabled
{
	[super setEnabled: enabled];
	[self dix_applyTitleColor];
}

- (void) setTitle: (NSString*) title
{
	[super setTitle: title];
	[self dix_applyTitleColor];
}

//An attributed title carries a colour that was resolved when it was built, so
//unlike everything else drawn from the catalog it does not follow the
//appearance on its own.
- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self dix_applyTitleColor];
}

@end

#pragma mark --------rules, labels and buttons-----------------

@implementation DIXControls

+ (NSBox*) sectionRule
{
	NSBox *rule = [[NSBox alloc] initWithFrame: NSZeroRect];

	//A separator-type NSBox draws a hairline and ignores fillColor, so the 2pt
	//rule is a custom box with no border and an ink fill instead.
	[rule setBoxType: NSBoxCustom];
	[rule setBorderWidth: 0.0];
	[rule setFillColor: [DIXTheme rule]];

	//Deliberately no height constraint. The windows that use this lay out with
	//frames, and a constraint on the returned box would be the only thing in
	//that hierarchy asking the layout engine for an opinion. Callers give it a
	//frame [DIXTheme ruleThickness] points tall.
	[rule setTranslatesAutoresizingMaskIntoConstraints: YES];

	return rule;
}

+ (NSBox*) rowSeparator
{
	NSBox *separator = [[NSBox alloc] initWithFrame: NSZeroRect];

	[separator setBoxType: NSBoxCustom];
	[separator setBorderWidth: 0.0];
	[separator setFillColor: [DIXTheme rowSeparator]];
	[separator setTranslatesAutoresizingMaskIntoConstraints: NO];

	[[[separator heightAnchor] constraintEqualToConstant: [DIXTheme hairlineThickness]] setActive: YES];

	return separator;
}

+ (NSTextField*) sectionLabelWithTitle: (NSString*) title
{
	//Uppercased here rather than in the .strings, so translators see and edit
	//the natural-case string. -localizedUppercaseString, not -uppercaseString:
	//the Turkish dotless i is exactly the kind of thing that goes unnoticed.
	NSString *shouted = [title localizedUppercaseString];

	NSTextField *label = [NSTextField labelWithAttributedString:
		[[NSAttributedString alloc] initWithString: shouted
										attributes: [DIXTheme sectionLabelAttributes]]];

	[label setTranslatesAutoresizingMaskIntoConstraints: NO];

	return label;
}

+ (NSButton*) primaryButtonWithTitle: (NSString*) title
							  target: (id) target
							  action: (SEL) action
{
	DIXAccentButton *button = [[DIXAccentButton alloc] initWithFrame: NSZeroRect];

	[button setButtonType: NSButtonTypeMomentaryPushIn];
	[button setBezelStyle: NSBezelStyleRounded];
	[button setTarget: target];
	[button setAction: action];

	//tints the bezel while leaving AppKit to draw the button's shape, so it
	//keeps the platform's 6pt geometry, focus ring and pressed state
	[button setBezelColor: [DIXTheme accent]];

	[button setTitle: title];	//sets the attributed title through the override
	[button setTranslatesAutoresizingMaskIntoConstraints: NO];

	return button;
}

+ (NSButton*) secondaryButtonWithTitle: (NSString*) title
								target: (id) target
								action: (SEL) action
{
	NSButton *button = [NSButton buttonWithTitle: title target: target action: action];

	[button setBezelStyle: NSBezelStyleRounded];
	[button setTranslatesAutoresizingMaskIntoConstraints: NO];

	return button;
}

@end
