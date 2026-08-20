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

#pragma mark --------the button shape-----------------

//The design's control border is 0.5px, which is one device pixel on a Retina
//display and is what makes it read as an edge rather than as a frame. The
//section rules are 1 and 2pt and are a different thing; see DIXTheme.
static const CGFloat kControlBorderWidth = 0.5;

//The design's buttons are 12pt, filled ones semibold. 13 is the platform's
//size, not this design's.
static const CGFloat kButtonFontSize = 12.0;

//"padding: 0 10px" in the design, against the two points a borderless button
//measures itself at - which put Rescan's label against its own border.
static const CGFloat kButtonPadding = 10.0;

//One button, drawn rather than asked for.
//
//NSBezelStyleRounded looked like the way to keep the platform's geometry and
//is not. Measured against the design: it draws 24pt tall whatever frame it is
//given, so the inspector's 28 and the strip's 26 both came out 24; it fills
//itself #efefef where the design has a flat white; and it draws no border
//where the design has a hairline. (Its -bezelColor was fine - the accent it
//put on screen was the accent asked for. A screenshot reads a saturated colour
//about #ef472d for #ec3013, which is the display's gamut and not a bug.)
//
//So the bezel is ours: a flat fill, the theme's 6pt radius, an optional
//hairline, and the height the caller asked for. The title is attributed, which
//is what lets it be readable on a saturated fill - and which has to be rebuilt
//on enable and on appearance changes, since an attributed string holds a
//resolved colour and is not dimmed by AppKit the way a plain title is.

@implementation DIXFlatButton

- (instancetype) initWithFrame: (NSRect) frameRect
{
	self = [super initWithFrame: frameRect];

	if ( self != nil )
	{
		_titleWeight = NSFontWeightRegular;

		[self setBordered: NO];
		[self setButtonType: NSButtonTypeMomentaryChange];
		[self setFont: [NSFont systemFontOfSize: kButtonFontSize]];

		//Without this the symbol is placed against the leading edge and only the
		//title is centred in what is left, so Rescan's glyph sat on its own
		//border with the padding all at the other end. Hugging makes the pair one
		//centred group, which is the design's flex row. (It does nothing for a
		//rounded bezel, which is why it is here and not on the old button.)
		[self setImageHugsTitle: YES];
	}

	return self;
}

- (void) drawRect: (NSRect) dirtyRect
{
	//Resolved before the alpha is applied. -colorWithAlphaComponent: on a
	//catalog colour pins it to an appearance of its own choosing, which drew
	//the disabled border in the dark theme's tone against a light window.
	NSColor *fill = ( [self isHighlighted] && _pressedFillColor != nil )
					? _pressedFillColor : _fillColor;

	fill = [fill colorUsingColorSpace: [NSColorSpace sRGBColorSpace]] ?: fill;

	NSColor *border = [_borderColor colorUsingColorSpace: [NSColorSpace sRGBColorSpace]]
					  ?: _borderColor;

	if ( ![self isEnabled] )
	{
		fill = [fill colorWithAlphaComponent: 0.4];
		border = [border colorWithAlphaComponent: 0.5];
	}

	//half the line width in, so a stroke lands on the pixel rather than across it
	NSRect box = _borderColor != nil
				 ? NSInsetRect( [self bounds], kControlBorderWidth / 2.0, kControlBorderWidth / 2.0 )
				 : [self bounds];

	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: box
														xRadius: [DIXTheme cornerRadius]
														yRadius: [DIXTheme cornerRadius]];
	if ( fill != nil )
	{
		[fill set];
		[path fill];
	}

	if ( _borderColor != nil )
	{
		[border set];
		[path setLineWidth: kControlBorderWidth];
		[path stroke];
	}

	//the title and the image, which a borderless button draws and nothing else
	[super drawRect: dirtyRect];
}

- (void) sizeToFit
{
	[super sizeToFit];

	NSRect frame = [self frame];

	frame.size.width += kButtonPadding * 2.0;

	[self setFrame: frame];
}

- (void) dix_applyTitleColor
{
	//Resolved inside this view's appearance, not whatever happens to be current.
	//An attributed string and -contentTintColor both keep the colour they were
	//given, and a button is built before it is in a window - so a catalog colour
	//asked for here came back in the *application's* appearance. With the system
	//in dark mode and this window forced to Aqua that meant near-white ink on a
	//white fill: a disabled button with no label on it at all.
	__block NSColor *base = nil;

	[[self effectiveAppearance] performAsCurrentDrawingAppearance: ^
	{
		NSColor *wanted = self->_titleColor != nil ? self->_titleColor : [DIXTheme ink];

		base = [wanted colorUsingColorSpace: [NSColorSpace sRGBColorSpace]] ?: wanted;
	}];

	//A borderless button tints a template image with the system's control text
	//colour, which on these fills came out several shades lighter than the
	//label beside it - the Rescan glyph read as disabled next to live text.
	//The symbol is part of the label, so it takes the label's colour.
	[self setContentTintColor: [self isEnabled] ? base
												: [base colorWithAlphaComponent: 0.5]];

	if ( [[self title] length] == 0 )
		return;

	NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
	[centred setAlignment: NSTextAlignmentCenter];

	NSDictionary *attributes = @{
		NSForegroundColorAttributeName: [self isEnabled] ? base
														 : [base colorWithAlphaComponent: 0.5],
		NSFontAttributeName:            [NSFont systemFontOfSize: kButtonFontSize
														  weight: _titleWeight],
		NSParagraphStyleAttributeName:  centred,
	};

	[self setAttributedTitle: [[NSAttributedString alloc] initWithString: [self title]
															 attributes: attributes]];
}

- (void) setTitleColor: (NSColor*) titleColor
{
	_titleColor = titleColor;
	[self dix_applyTitleColor];
}

- (void) setTitleWeight: (NSFontWeight) titleWeight
{
	_titleWeight = titleWeight;
	[self dix_applyTitleColor];
}

- (void) setEnabled: (BOOL) enabled
{
	[super setEnabled: enabled];
	[self dix_applyTitleColor];
	[self setNeedsDisplay: YES];
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
	[self setNeedsDisplay: YES];
}

//And a button built outside a window has no appearance worth resolving against
//until it is in one.
- (void) viewDidMoveToWindow
{
	[super viewDidMoveToWindow];

	if ( [self window] != nil )
		[self dix_applyTitleColor];
}

@end

#pragma mark --------the mode switch-----------------

//Straight from the design's markup for this control: a 7pt track with 2pt of
//padding, segments of "3px 12px" at 12pt, and the selected one a 5pt pill.
static const CGFloat kSwitchTrackRadius   = 7.0;
static const CGFloat kSwitchTrackPadding  = 2.0;
static const CGFloat kSwitchPillRadius    = 5.0;
static const CGFloat kSwitchSegmentInsetX = 12.0;
static const CGFloat kSwitchSegmentInsetY = 3.0;

@implementation DIXSegmentedControl
{
	NSArray<NSString*> *_labels;
	__weak id _target;
	SEL _action;
}

+ (instancetype) switchWithLabels: (NSArray<NSString*>*) labels
						   target: (id) target
						   action: (SEL) action
{
	DIXSegmentedControl *control = [[self alloc] initWithFrame: NSZeroRect];

	control->_labels = [labels copy];
	control->_target = target;
	control->_action = action;

	[control sizeToFit];

	return control;
}

- (NSFont*) dix_fontForSegment: (NSInteger) segment
{
	//the selected label is medium, the others regular - the design's 500 against
	//its default
	return [NSFont systemFontOfSize: kButtonFontSize
							 weight: segment == _selectedSegment ? NSFontWeightMedium
																 : NSFontWeightRegular];
}

- (NSDictionary*) dix_attributesForSegment: (NSInteger) segment
{
	__block NSColor *color = nil;

	[[self effectiveAppearance] performAsCurrentDrawingAppearance: ^
	{
		NSColor *wanted = segment == self->_selectedSegment ? [DIXTheme ink]
														    : [DIXTheme detailText];

		color = [wanted colorUsingColorSpace: [NSColorSpace sRGBColorSpace]] ?: wanted;
	}];

	return @{ NSFontAttributeName: [self dix_fontForSegment: segment],
			  NSForegroundColorAttributeName: color };
}

//Every segment is as wide as the widest label, so the pill does not change size
//as the selection moves - which it would, the labels being different lengths
//and the selected one a heavier weight.
- (CGFloat) dix_segmentWidth
{
	CGFloat widest = 0.0;

	for ( NSInteger i = 0; i < (NSInteger) [_labels count]; i++ )
	{
		//measured at the heavier weight, so the widest case is the one that fits
		NSDictionary *attributes = @{ NSFontAttributeName:
			[NSFont systemFontOfSize: kButtonFontSize weight: NSFontWeightMedium] };

		widest = MAX( widest, ceil( [[_labels objectAtIndex: i] sizeWithAttributes: attributes].width ) );
	}

	return widest + kSwitchSegmentInsetX * 2.0;
}

- (void) sizeToFit
{
	const CGFloat lineHeight = ceil( [[self dix_fontForSegment: -1] boundingRectForFont].size.height );

	NSRect frame = [self frame];

	frame.size.width  = [self dix_segmentWidth] * (CGFloat) [_labels count]
						+ kSwitchTrackPadding * 2.0;
	frame.size.height = lineHeight + kSwitchSegmentInsetY * 2.0 + kSwitchTrackPadding * 2.0;

	[self setFrame: frame];
}

- (NSRect) dix_rectForSegment: (NSInteger) segment
{
	const CGFloat width = [self dix_segmentWidth];

	return NSMakeRect( kSwitchTrackPadding + width * (CGFloat) segment,
					   kSwitchTrackPadding,
					   width,
					   NSHeight( [self bounds] ) - kSwitchTrackPadding * 2.0 );
}

- (void) setSelectedSegment: (NSInteger) selectedSegment
{
	if ( selectedSegment == _selectedSegment )
		return;

	_selectedSegment = selectedSegment;
	[self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) dirtyRect
{
	[[DIXTheme switchTrack] set];
	[[NSBezierPath bezierPathWithRoundedRect: [self bounds]
									 xRadius: kSwitchTrackRadius
									 yRadius: kSwitchTrackRadius] fill];

	if ( _selectedSegment >= 0 && _selectedSegment < (NSInteger) [_labels count] )
	{
		[[DIXTheme switchSelected] set];
		[[NSBezierPath bezierPathWithRoundedRect: [self dix_rectForSegment: _selectedSegment]
										 xRadius: kSwitchPillRadius
										 yRadius: kSwitchPillRadius] fill];
	}

	for ( NSInteger i = 0; i < (NSInteger) [_labels count]; i++ )
	{
		NSString *label = [_labels objectAtIndex: i];
		NSDictionary *attributes = [self dix_attributesForSegment: i];
		const NSSize extent = [label sizeWithAttributes: attributes];
		const NSRect segment = [self dix_rectForSegment: i];

		[label drawAtPoint: NSMakePoint( round( NSMidX( segment ) - extent.width  / 2.0 ),
										 round( NSMidY( segment ) - extent.height / 2.0 ) )
			withAttributes: attributes];
	}
}

- (BOOL) isFlipped
{
	return NO;
}

- (void) mouseDown: (NSEvent*) event
{
	const NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];

	for ( NSInteger i = 0; i < (NSInteger) [_labels count]; i++ )
	{
		if ( !NSPointInRect( point, [self dix_rectForSegment: i] ) )
			continue;

		[self setSelectedSegment: i];

		if ( _target != nil && _action != NULL )
			[NSApp sendAction: _action to: _target from: self];

		return;
	}
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay: YES];
}

@end

#pragma mark --------overlay scrollers-----------------

//AppKit takes the scroller style from a system-wide preference, and that
//preference's default - "Automatic" - means "legacy scrollers whenever a mouse
//is plugged in". Legacy scrollers are always drawn, and they are laid out
//beside the content rather than over it, so every list in the window loses 17pt
//of width to a channel that is doing nothing most of the time. The
//design has no such channel: its lists run to the edge of the pane and the knob
//appears over them while something is scrolling.
//
//"Always", though, is left alone. That one is set by hand in System Settings,
//by someone who wants a scroll bar they can see and aim at, and it is not this
//application's to overrule.
static NSScrollerStyle DIXWantedScrollerStyle( void )
{
	NSString *preference = [[NSUserDefaults standardUserDefaults]
		stringForKey: @"AppleShowScrollBars"];

	if ( [preference isEqualToString: @"Always"] )
		return [NSScroller preferredScrollerStyle];

	return NSScrollerStyleOverlay;
}

//Setting the style once is not enough to keep it. NSScrollView observes
//NSPreferredScrollerStyleDidChangeNotification itself and answers it by
//adopting the new preferred style, which undoes ours - plugging a mouse in
//would put the channel back. So the scroll views that asked are remembered and
//set again afterwards.
//
//Weakly remembered: this table outlives every window, and a document's lists go
//away with it.
@interface DIXScrollerStyleKeeper : NSObject
{
	NSHashTable<NSScrollView*> *_scrollViews;
}

+ (instancetype) sharedKeeper;

- (void) keepOverlayStyleIn: (NSScrollView*) scrollView;

@end

@implementation DIXScrollerStyleKeeper

+ (instancetype) sharedKeeper
{
	static DIXScrollerStyleKeeper *keeper = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ keeper = [[DIXScrollerStyleKeeper alloc] init]; } );

	return keeper;
}

- (instancetype) init
{
	self = [super init];

	if ( self != nil )
	{
		_scrollViews = [NSHashTable weakObjectsHashTable];

		[[NSNotificationCenter defaultCenter]
			addObserver: self
			   selector: @selector( preferredScrollerStyleChanged: )
				   name: NSPreferredScrollerStyleDidChangeNotification
				 object: nil];
	}

	return self;
}

- (void) keepOverlayStyleIn: (NSScrollView*) scrollView
{
	if ( scrollView == nil )
		return;

	[_scrollViews addObject: scrollView];
	[scrollView setScrollerStyle: DIXWantedScrollerStyle()];
}

- (void) preferredScrollerStyleChanged: (NSNotification*) notification
{
	//Deliberately not done here and now: the scroll views are on the same
	//notification and there is no order between observers, so setting the style
	//from inside it can be overwritten a moment later by AppKit's own handler.
	//The next turn of the run loop is after all of them.
	dispatch_async( dispatch_get_main_queue(), ^
	{
		const NSScrollerStyle style = DIXWantedScrollerStyle();

		for ( NSScrollView *scrollView in self->_scrollViews )
			[scrollView setScrollerStyle: style];
	} );
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
	DIXFlatButton *button = [[DIXFlatButton alloc] initWithFrame: NSZeroRect];

	[button setTarget: target];
	[button setAction: action];

	[button setFillColor: [DIXTheme accent]];
	[button setPressedFillColor: [DIXTheme accentPressed]];

	//+onAccent, not white: the dark accent (#ff5a3c) is light enough that a
	//white label on it fails, so there it is near-black instead
	[button setTitleColor: [DIXTheme onAccent]];
	[button setTitleWeight: NSFontWeightSemibold];

	[button setTitle: title];	//sets the attributed title through the override
	[button setTranslatesAutoresizingMaskIntoConstraints: NO];

	return button;
}

+ (NSButton*) secondaryButtonWithTitle: (NSString*) title
								target: (id) target
								action: (SEL) action
{
	DIXFlatButton *button = [[DIXFlatButton alloc] initWithFrame: NSZeroRect];

	[button setTarget: target];
	[button setAction: action];

	[button setFillColor: [DIXTheme controlFill]];
	[button setPressedFillColor: [DIXTheme selectedRowFill]];
	[button setBorderColor: [DIXTheme controlBorder]];
	[button setTitleColor: [DIXTheme ink]];

	[button setTitle: title];
	[button setTranslatesAutoresizingMaskIntoConstraints: NO];

	return button;
}

+ (void) setImageTitleGap: (CGFloat) gap onButton: (NSButton*) button
{
	NSString *title = [button title];

	if ( [title length] == 0 )
		return;

	NSFont *font = [button font] ?: [NSFont systemFontOfSize: [NSFont systemFontSize]];

	//A space is about a quarter of the point size; the kern makes up the rest,
	//so the figure asked for is the figure drawn whatever the font does.
	const CGFloat spaceWidth = [@" " sizeWithAttributes: @{ NSFontAttributeName: font }].width;

	NSMutableAttributedString *spaced = [[NSMutableAttributedString alloc]
		initWithString: [@" " stringByAppendingString: title]
			attributes: @{ NSFontAttributeName: font }];

	[spaced addAttribute: NSKernAttributeName
				   value: @( MAX( 0.0, gap - spaceWidth ) )
				   range: NSMakeRange( 0, 1 )];

	[button setAttributedTitle: spaced];
	[button setAccessibilityTitle: title];
}

+ (void) useOverlayScrollersIn: (NSScrollView*) scrollView
{
	//This defaults to NO, and the file list's scroll view comes out of
	//TreeMap.nib with nothing setting it. It matters in the legacy fallback
	//above: measured against a document view shorter than its clip view, a
	//scroll view that does not autohide still drew a scroller and still gave up
	//17 of its 200 points to it.
	[scrollView setAutohidesScrollers: YES];

	[[DIXScrollerStyleKeeper sharedKeeper] keepOverlayStyleIn: scrollView];
}

@end
