//
//  DIXFileInfoView.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 04.12.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "DIXFileInfoView.h"
#import "DIXTheme.h"
#import "DIXControls.h"
#import "AppsForItem.h"
#import "NSURL-Extensions.h"

#import <sys/stat.h>
#import <ctype.h>

static const CGFloat kEdgeInset    = 6.0;
static const CGFloat kColumnGap    = 8.0;
static const CGFloat kRowGap       = 6.0;

//The inspector's own metrics, straight from the design's markup for this block:
//"padding: 12px 16px", "gap: 10px", and rows of "padding: 3px 0" - which is the
//6pt between two rows' text that kRowGap already gives.
static const CGFloat kInspectorEdgeInsetX = 16.0;
static const CGFloat kInspectorEdgeInsetY = 12.0;
static const CGFloat kInspectorColumnGap  = 10.0;

//================ DIXInfoGrid ======================================================

//The grid itself, so that two things AppKit does not do for free can live in one
//place: a separator between rows, and values that wrap.
//
//A wrapping NSTextField only reports a correct height once it knows how wide it
//will be, which is what preferredMaxLayoutWidth is for. That width must be
//derived from the *title* column, never from the value field's own frame: the
//grid sizes its columns from their content, so a value field whose width
//depends on where it landed shrinks itself on every pass. Doing it that way
//collapsed the value column to five points and made the grid 1428 points tall.

@interface DIXInfoGrid : NSGridView
{
	NSMutableArray<NSTextField*> *_titleFields;
	NSMutableArray<NSTextField*> *_valueFields;
	CGFloat _titleColumnWidth;
	CGFloat _fixedTitleColumnWidth;   //0 to measure the titles instead
	BOOL _drawsRowSeparators;
	CGFloat _edgeInsetX;
	CGFloat _edgeInsetY;
}
@property (nonatomic) CGFloat fixedTitleColumnWidth;

//A ruled row per attribute is the old Info panel's look, not the design's: the
//design rules the block once, underneath, and lets the key column do the
//separating inside it. Six lines through seven rows read as a spreadsheet
//where the design reads as a caption list.
@property (nonatomic) BOOL drawsRowSeparators;
@property (nonatomic) CGFloat edgeInsetX;
@property (nonatomic) CGFloat edgeInsetY;
- (void) removeAllRows;
- (void) addRowWithTitleField: (NSTextField*) titleField valueField: (NSTextField*) valueField;
- (void) finishRows;
@end

@implementation DIXInfoGrid

- (instancetype) initWithFrame: (NSRect) frame
{
	self = [super initWithFrame: frame];

	if ( self != nil )
	{
		_drawsRowSeparators = YES;
		_edgeInsetX = kEdgeInset;
		_edgeInsetY = kEdgeInset;
	}

	return self;
}

- (BOOL) isFlipped
{
	//so rows fill from the top of the scroll view rather than the bottom
	return YES;
}

- (void) addRowWithTitleField: (NSTextField*) titleField valueField: (NSTextField*) valueField
{
	if ( _valueFields == nil )
	{
		_titleFields = [[NSMutableArray alloc] init];
		_valueFields = [[NSMutableArray alloc] init];
	}

	[self addRowWithViews: @[ titleField, valueField ]];

	[_titleFields addObject: titleField];
	[_valueFields addObject: valueField];
}

//Called once the rows are all in: the title column is pinned to the widest
//title so it stops competing with the value column for the spare width, and the
//value column takes whatever is left.
- (void) finishRows
{
	if ( [self numberOfRows] == 0 )
	{
		_titleColumnWidth = 0.0;
		return;
	}

	//The design pins this column rather than measuring it, so the values start
	//at the same x whatever the longest key happens to be - which is what makes
	//a column of them read as a column.
	if ( _fixedTitleColumnWidth > 0.0 )
	{
		_titleColumnWidth = _fixedTitleColumnWidth;
	}
	else
	{
		_titleColumnWidth = 0.0;
		for ( NSTextField *field in _titleFields )
			_titleColumnWidth = MAX( _titleColumnWidth, ceil( [field fittingSize].width ) );
	}

	NSGridColumn *titles = [self columnAtIndex: 0];
	[titles setWidth: _titleColumnWidth];
	[titles setXPlacement: _fixedTitleColumnWidth > 0.0
							? NSGridCellPlacementLeading : NSGridCellPlacementTrailing];
	[titles setLeadingPadding: _edgeInsetX];

	NSGridColumn *values = [self columnAtIndex: 1];
	[values setXPlacement: NSGridCellPlacementFill];
	[values setTrailingPadding: _edgeInsetX];

	[[self rowAtIndex: 0] setTopPadding: _edgeInsetY];
	[[self rowAtIndex: [self numberOfRows] - 1] setBottomPadding: _edgeInsetY];
}

//-removeRowAtIndex: drops the row but leaves its content views as subviews, so
//they have to be taken out by hand or every refresh piles another set of labels
//on top of the last.
- (void) removeAllRows
{
	while ( [self numberOfRows] > 0 )
		[self removeRowAtIndex: 0];

	for ( NSView *field in _titleFields )
		[field removeFromSuperview];
	for ( NSView *field in _valueFields )
		[field removeFromSuperview];

	[_titleFields removeAllObjects];
	[_valueFields removeAllObjects];
	_titleColumnWidth = 0.0;
}

- (void) layout
{
	//Width of the value column, from the grid's own width and the fixed title
	//column - nothing here reads a value field's frame, so there is no feedback.
	//
	//It must be the *same* inset -finishRows applies, not the constant it used to
	//be: too wide and a field reports the height of fewer lines than it will draw,
	//and the overflow lands on top of the next row. The inspector's 16pt inset
	//against a hardcoded 6 was 20 points of that, which cost a third line.
	const CGFloat available = NSWidth( [self bounds] )
							  - _edgeInsetX * 2.0
							  - _titleColumnWidth
							  - [self columnSpacing];

	if ( available > 0.0 )
		for ( NSTextField *field in _valueFields )
			if ( fabs( [field preferredMaxLayoutWidth] - available ) > 0.5 )
				[field setPreferredMaxLayoutWidth: available];

	[super layout];
}

- (void) drawRect: (NSRect) dirtyRect
{
	[super drawRect: dirtyRect];

	if ( !_drawsRowSeparators || [_valueFields count] < 2 )
		return;

	[[NSColor separatorColor] set];

	const NSRect bounds = [self bounds];

	//between rows only — no rule under the last one, and none above the first
	for ( NSUInteger i = 0; i + 1 < [_valueFields count]; i++ )
	{
		const NSRect field = [[_valueFields objectAtIndex: i] frame];
		const CGFloat y = round( NSMaxY( field ) + kRowGap / 2.0 );

		NSRectFill( NSMakeRect( NSMinX( bounds ), y, NSWidth( bounds ), 1.0 ) );
	}
}

@end

//================ DIXFileInfoView ======================================================

@interface DIXFileInfoView(Private)
- (void) buildViewHierarchy;
- (void) rebuildRows;
- (void) addRowWithTitle: (NSString*) title value: (NSString*) value;
+ (NSString*) permissionStringForURL: (NSURL*) URL;
+ (NSString*) permissionOctalStringForModeBits: (mode_t) modeBits;
@end

@implementation DIXFileInfoView

//The nib holds an NSCustomView placeholder, which instantiates us through
//-initWithFrame:. -initWithCoder: is here so a directly archived instance would
//work too, rather than silently coming up with no subviews.

- (id) initWithFrame: (NSRect) frame
{
	self = [super initWithFrame: frame];

	if ( self != nil )
		[self buildViewHierarchy];

	return self;
}

- (id) initWithCoder: (NSCoder*) coder
{
	self = [super initWithCoder: coder];

	if ( self != nil )
		[self buildViewHierarchy];

	return self;
}

- (void) setUsesInspectorLayout: (BOOL) inspector
{
	if ( _usesInspectorLayout == inspector )
		return;

	_usesInspectorLayout = inspector;

	//74pt, the design's key column
	DIXInfoGrid *grid = (DIXInfoGrid*) _grid;

	[grid setFixedTitleColumnWidth: inspector ? 74.0 : 0.0];
	[grid setDrawsRowSeparators: !inspector];
	[grid setEdgeInsetX: inspector ? kInspectorEdgeInsetX : kEdgeInset];
	[grid setEdgeInsetY: inspector ? kInspectorEdgeInsetY : kEdgeInset];
	[grid setColumnSpacing: inspector ? kInspectorColumnGap : kColumnGap];

	[self rebuildRows];
}

- (CGFloat) fittingHeight
{
	//Laid out first: the grid sizes its value column from -layout, and a grid
	//that has never been laid out still carries the frame it was created with -
	//the same trap the settings pages hit.
	[self layoutSubtreeIfNeeded];

	if ( [_grid numberOfRows] == 0 )
		return 0.0;

	return ceil( [_grid fittingSize].height );
}

- (NSURL*) URL
{
	return _URL;
}

- (void) setURL: (NSURL*) url
{
	_URL = url;

	[self rebuildRows];
}

@end

//================ DIXFileInfoView(Private) ======================================================

@implementation DIXFileInfoView(Private)

- (void) buildViewHierarchy
{
	[self setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

	_grid = [[DIXInfoGrid alloc] initWithFrame: [self bounds]];
	[_grid setColumnSpacing: kColumnGap];
	[_grid setRowSpacing: kRowGap];
	//a wrapped value keeps its first line level with its title
	[_grid setRowAlignment: NSGridRowAlignmentFirstBaseline];

	_scrollView = [[NSScrollView alloc] initWithFrame: [self bounds]];
	[_scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
	[_scrollView setHasVerticalScroller: YES];
	[_scrollView setHasHorizontalScroller: NO];
	[DIXControls useOverlayScrollersIn: _scrollView];
	[_scrollView setBorderType: NSNoBorder];
	[_scrollView setDrawsBackground: NO];
	[_scrollView setDocumentView: _grid];

	[self addSubview: _scrollView];

	//The grid is pinned to the clip view's width rather than left to size
	//itself, so there is never a horizontal scroller and long values wrap
	//instead. Height is deliberately unconstrained: the grid's own content
	//decides it, and that is what the scroll view scrolls.
	//
	//The width it fills to is a *preference*, not a requirement, and that
	//matters more than it looks. Every view from the panel's content view down
	//to here is pinned leading and trailing to its superview, so a required
	//equality at this last link put the whole chain - content view,
	//DIXFileInfoView, scroll view, clip view, grid - on one required width, and
	//an empty NSGridView asks for almost none. Emptying the grid therefore
	//*required* the panel to collapse, and AppKit obliged: a panel the user had
	//widened snapped to about 90 points the moment the selection was cleared,
	//and nothing brought it back. Zooming the treemap does exactly that, since
	//-zoomIntoItem: has to clear the selection - the item zoomed to becomes the
	//treemap's root.
	//
	//Preferring to fill lets the grid be narrower than the clip view when its
	//contents cannot fill it, which is the one case that was breaking the
	//panel. The trailing edge is still a hard limit, so a long value has to
	//wrap and cannot bring back the horizontal scroller.
	//
	//This is necessary and not sufficient: on its own it stops the collapse
	//being *required* without stopping it happening, because the engine then
	//settles the panel on its content's fitting width instead. InfoPanelController
	//holds the width; both halves were measured separately, and either one alone
	//leaves the panel collapsing to 90.
	[_grid setTranslatesAutoresizingMaskIntoConstraints: NO];

	NSLayoutConstraint *fillsWidth =
		[[_grid trailingAnchor] constraintEqualToAnchor: [[_scrollView contentView] trailingAnchor]];
	[fillsWidth setPriority: NSLayoutPriorityDefaultHigh];

	[NSLayoutConstraint activateConstraints: @[
		[[_grid leadingAnchor] constraintEqualToAnchor: [[_scrollView contentView] leadingAnchor]],
		[[_grid trailingAnchor] constraintLessThanOrEqualToAnchor: [[_scrollView contentView] trailingAnchor]],
		fillsWidth,
		[[_grid topAnchor] constraintEqualToAnchor: [[_scrollView contentView] topAnchor]],
	]];
}

- (void) addRowWithTitle: (NSString*) title value: (NSString*) value
{
	if ( value == nil )
		value = @"";

	NSTextField *titleField = [NSTextField labelWithString: title];

	if ( _usesInspectorLayout )
	{
		[titleField setFont: [NSFont systemFontOfSize: 12.0]];
		[titleField setTextColor: [DIXTheme muted]];
		[titleField setAlignment: NSTextAlignmentLeft];
	}
	else
	{
		[titleField setFont: [NSFont boldSystemFontOfSize: [NSFont smallSystemFontSize]]];
		[titleField setTextColor: [NSColor secondaryLabelColor]];
		[titleField setAlignment: NSTextAlignmentRight];
	}

	NSTextField *valueField = [NSTextField labelWithString: value];
	[valueField setFont: [NSFont systemFontOfSize:
		_usesInspectorLayout ? 12.0 : [NSFont smallSystemFontSize]]];

	if ( _usesInspectorLayout )
		[valueField setTextColor: [DIXTheme ink]];
	//a path or a resolved link is worth being able to copy out of the panel,
	//which the hand-drawn glyphs this replaces could never be
	[valueField setSelectable: YES];
	[valueField setContentHuggingPriority: NSLayoutPriorityDefaultLow
						   forOrientation: NSLayoutConstraintOrientationHorizontal];
	[valueField setContentCompressionResistancePriority: NSLayoutPriorityDefaultLow
										 forOrientation: NSLayoutConstraintOrientationHorizontal];
	[valueField setUsesSingleLineMode: NO];
	[valueField setLineBreakMode: NSLineBreakByWordWrapping];
	[valueField setMaximumNumberOfLines: 0];
	[[valueField cell] setWraps: YES];

	//the title column must not be squeezed to make room for a long value;
	//hugging stays below required so it cannot fight the grid's own sizing
	[titleField setContentCompressionResistancePriority: NSLayoutPriorityRequired
										 forOrientation: NSLayoutConstraintOrientationHorizontal];
	[titleField setContentHuggingPriority: NSLayoutPriorityDefaultHigh
						   forOrientation: NSLayoutConstraintOrientationHorizontal];

	[(DIXInfoGrid*)_grid addRowWithTitleField: titleField valueField: valueField];
}

- (void) rebuildRows
{
	[(DIXInfoGrid*)_grid removeAllRows];

	if ( _URL == nil || ![_URL stillExists] )
	{
		[self setNeedsDisplay: YES];
		return;
	}

	//NSLocalizedString keys are the English strings themselves and all twelve
	//exist in de/en/es/fr — changing a literal here means changing it in every
	//Localizable.strings too.

	//the display name is already shown next to the icon at the top of the
	//panel, so the raw name is the useful one here - and in the inspector it is
	//shown right above these rows, where repeating it is noise
	if ( !_usesInspectorLayout )
		[self addRowWithTitle: NSLocalizedString(@"Name:",@"") value: [_URL name]];

	[self addRowWithTitle: _usesInspectorLayout ? NSLocalizedString(@"Kind",@"inspector row")
												: NSLocalizedString(@"Kind:",@"")
					value: [_URL getCachedStringValue: NSURLLocalizedTypeDescriptionKey]];

	if ( [_URL isVolume] && ![_URL isLocalVolume] )
	{
		NSURL *networkURL = nil;
		[_URL getResourceValue: &networkURL forKey: NSURLVolumeURLForRemountingKey error: nil];

		if ( networkURL != nil )
			[self addRowWithTitle: NSLocalizedString(@"URL:",@"") value: [networkURL absoluteString]];
	}

	{
		NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateStyle: NSDateFormatterMediumStyle];
		[dateFormatter setTimeStyle: NSDateFormatterMediumStyle];
		[dateFormatter setLocale: [NSLocale currentLocale]];

		[self addRowWithTitle: _usesInspectorLayout ? NSLocalizedString(@"Modified",@"inspector row")
													: NSLocalizedString(@"Modified:",@"")
						value: [dateFormatter stringFromDate: [_URL cachedModificationDate]]];
		[self addRowWithTitle: _usesInspectorLayout ? NSLocalizedString(@"Created",@"inspector row")
													: NSLocalizedString(@"Created:",@"")
						value: [dateFormatter stringFromDate: [_URL cachedCreationDate]]];
	}

	//"Where" rather than "Path": the file's own name is in the header, so the
	//half of the path that says something new is the folder holding it. Written
	//the way the Finder writes it, with the home folder as a tilde.
	if ( _usesInspectorLayout )
	{
		NSString *folder = [[_URL URLByDeletingLastPathComponent] path];

		if ( [folder length] > 0 )
			[self addRowWithTitle: NSLocalizedString(@"Where",@"inspector row")
							value: [folder stringByAbbreviatingWithTildeInPath]];
	}

	NSDictionary<NSFileAttributeKey, id> *attribs =
		[[NSFileManager defaultManager] attributesOfItemAtPath: [_URL path] error: nil];

	if ( attribs != nil )
	{
		if ( _usesInspectorLayout )
		{
			//"derek · staff" - one row, since a group without an owner beside it
			//is not a thing anyone reads separately
			NSString *owner = [attribs fileOwnerAccountName];
			NSString *group = [attribs fileGroupOwnerAccountName];

			[self addRowWithTitle: NSLocalizedString(@"Owner",@"inspector row")
							value: ( [group length] > 0 && [owner length] > 0 )
									 ? [NSString stringWithFormat: @"%@ · %@", owner, group]
									 : ( owner ?: group )];
		}
		else
		{
			[self addRowWithTitle: NSLocalizedString(@"Owner:",@"") value: [attribs fileOwnerAccountName]];
			[self addRowWithTitle: NSLocalizedString(@"Group:",@"") value: [attribs fileGroupOwnerAccountName]];
		}
	}

	[self addRowWithTitle: _usesInspectorLayout ? NSLocalizedString(@"Permission",@"inspector row")
												: NSLocalizedString(@"Permission:",@"")
					value: [DIXFileInfoView permissionStringForURL: _URL]];

	{
		NSBundle *bundle = [NSBundle bundleWithURL: _URL];

		if ( bundle != nil )
		{
			//most specific first: a localized long string beats a bare version number
			NSArray<NSDictionary*> *dicts = @[ [bundle localizedInfoDictionary] ?: @{},
											   [bundle infoDictionary] ?: @{} ];
			NSArray<NSString*> *keys = @[ @"CFBundleGetInfoString", @"CFBundleShortVersionString" ];
			NSString *version = nil;

			for ( NSString *key in keys )
				for ( NSDictionary *dict in dicts )
					if ( version == nil || [version length] == 0 )
						version = [dict objectForKey: key];

			if ( [version length] > 0 )
				[self addRowWithTitle: NSLocalizedString(@"Version:",@"") value: version];
		}
	}

	//the inspector says "Where" above instead; the full path repeats the name
	if ( !_usesInspectorLayout )
		[self addRowWithTitle: NSLocalizedString(@"Path:",@"") value: [_URL path]];

	NSURL *resolvedURL = nil;

	if ( [_URL cachedIsAliasOrSymbolicLink] )
	{
		NSString *resolvedPath = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath: [_URL path]
																						  error: nil];

		if ( resolvedPath != nil )
		{
			resolvedURL = [NSURL fileURLWithPath: resolvedPath];

			[self addRowWithTitle: NSLocalizedString(@"Resolved:",@"") value: resolvedPath];
		}
	}

	{
		NSURL *url = (resolvedURL != nil ? resolvedURL : _URL);
		NSURL *appURL = [[AppsForItem appsForItemURL: url] defaultAppURL];

		//for an application, the default opener is the application itself; that
		//is not worth a row
		if ( appURL != nil && ![appURL isEqualToURL: _URL] )
			[self addRowWithTitle: _usesInspectorLayout
									? NSLocalizedString(@"Opens with",@"inspector row")
									: NSLocalizedString(@"Application:",@"")
							value: [appURL displayName]];
	}

	[(DIXInfoGrid*)_grid finishRows];

	[self setNeedsDisplay: YES];
}

// --------------- permissions ---------------------------------------------
// adopted from CocoaTechFile (NTFileDesc-NTUtilities.m)

+ (NSString*) permissionStringForURL: (NSURL*) URL
{
	// [NSFileManager attributesOfItemAtPath:error:] provides the permission bits
	// ([NSFileAttributes filePosixPermissions]), but not the complete mode bits,
	// which is what the file-type tests below need. lstat gives both, and
	// replaces the Carbon FSGetCatalogInfo this used to call. lstat rather than
	// stat so that a symlink reports as one, which is what the S_ISLNK branch
	// below has always been written for.

	struct stat fileInfo;
	if ( lstat( [URL fileSystemRepresentation], &fileInfo ) != 0 )
		return @"";

	const mode_t modeBits = fileInfo.st_mode;
	const mode_t permBits = (modeBits & ACCESSPERMS);

	char perm[11];

	if      ( S_ISDIR(modeBits) )  perm[0] = 'd';
	else if ( S_ISCHR(modeBits) )  perm[0] = 'c';
	else if ( S_ISBLK(modeBits) )  perm[0] = 'b';
	else if ( S_ISLNK(modeBits) )  perm[0] = 'l';
	else if ( S_ISSOCK(modeBits) ) perm[0] = 's';
	else if ( S_ISWHT(modeBits) )  perm[0] = 'w';
	else if ( S_ISREG(modeBits) )  perm[0] = '-';
	else                           perm[0] = ' ';  // what is it?

	//setuid/setgid show in the owner and group execute positions, the sticky
	//bit in the others position, exactly as ls(1) prints them
	const struct { mode_t read, write, execute; } who[] = {
		{ S_IRUSR, S_IWUSR, S_IXUSR },
		{ S_IRGRP, S_IWGRP, S_IXGRP },
		{ S_IROTH, S_IWOTH, S_IXOTH },
	};
	const mode_t special[] = { S_ISUID, S_ISGID, S_ISVTX };

	for ( int i = 0; i < 3; i++ )
	{
		char *out = &perm[1 + i * 3];

		out[0] = (permBits & who[i].read)  ? 'r' : '-';
		out[1] = (permBits & who[i].write) ? 'w' : '-';

		const BOOL executable = (permBits & who[i].execute) != 0;
		const BOOL marked     = (modeBits & special[i]) != 0;
		const char markedChar = (i == 2) ? 't' : 's';   // sticky prints t, set-id prints s

		if ( marked )
			out[2] = executable ? markedChar : toupper( markedChar );
		else
			out[2] = executable ? 'x' : '-';
	}

	perm[10] = '\0';

	return [NSString stringWithFormat: @"%s (%@)",
			perm, [self permissionOctalStringForModeBits: modeBits]];
}

+ (NSString*) permissionOctalStringForModeBits: (mode_t) modeBits
{
	const mode_t permBits = (modeBits & ACCESSPERMS);

	return [NSString stringWithFormat: @"%d%d%d",
			(permBits & S_IRWXU) >> 6,
			(permBits & S_IRWXG) >> 3,
			(permBits & S_IRWXO)];
}

@end
