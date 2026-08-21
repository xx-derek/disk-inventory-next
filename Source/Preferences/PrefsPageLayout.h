//
//  PrefsPageLayout.h
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

//One settings row that answers rather than asks: a title, a help line, and a
//coloured dot beside a word. Returned by -addStatusTitled:help: so the page can
//fill it in - Full Disk Access has to be looked up, and how much history is
//stored has to be counted.
@interface PrefsStatusRow : NSView

- (void) setStatusText: (NSString*) text good: (BOOL) good;
- (void) setHelpText: (NSString*) help;

@end

//One row carrying a folder: a monospaced chip on a line of its own and a
//Choose… button beside it. Returned so the page can put a path in it and read
//one back out.
@interface PrefsPathRow : NSView

- (void) setPath: (NSString*) path;

@end

//Builds one settings page as the design draws it: sections, each a small
//uppercase label over a 2pt ink rule, then rows separated by 1pt, then an
//optional footnote. A row is a 13pt title over an 11pt help line with one
//control right-aligned against it.
//
//Pages used to be a nib per page per language - eight bundles for two pages -
//which is why the two of them had drifted into different shapes. Describing a
//page in code means the alignment is a property of the layout rather than of
//whoever last opened Interface Builder.
//
//Titles are localized through the "Preferences" table, so the strings passed in
//are the English text, matching the convention everywhere else in the project.
@interface PrefsPageLayout : NSObject
{
	NSView *_view;
	CGFloat _width;
	CGFloat _y;                 //how far down the page the next row starts

	NSMutableArray<NSView*> *_controls;
	NSView *_firstControl;
	NSView *_lastControl;

	BOOL _sectionHasRows;       //whether a 1pt separator is owed above the next row
}

//"width" is the content width of the right-hand pane, which the panel decides.
+ (instancetype) layoutWithWidth: (CGFloat) width;

- (void) beginSectionWithLabel: (NSString*) label;

//An NSSwitch bound to a defaults key. "inverted" is for the keys that are
//stored as suppression flags - DontShowPrivacyWarningMessage reads as "warn me"
//in the window and as "don't" on disk.
- (void) addToggleTitled: (NSString*) title
					help: (NSString*) help
			 defaultsKey: (NSString*) defaultsKey;

- (void) addToggleTitled: (NSString*) title
					help: (NSString*) help
			 defaultsKey: (NSString*) defaultsKey
				inverted: (BOOL) inverted;

//A pop-up bound to a defaults key. The values become the menu items' tags, and
//the binding is NSSelectedTagBinding, so what is stored is the number chosen
//rather than where it sat in the menu.
- (void) addPopUpTitled: (NSString*) title
				   help: (NSString*) help
			defaultsKey: (NSString*) defaultsKey
				 titles: (NSArray<NSString*>*) titles
				 values: (NSArray<NSNumber*>*) values;

//A row whose control is a button. Destructive ones are the solid accent.
- (void) addButtonTitled: (NSString*) title
					help: (NSString*) help
			 buttonTitle: (NSString*) buttonTitle
			 destructive: (BOOL) destructive
				  target: (id) target
				  action: (SEL) action;

- (PrefsStatusRow*) addStatusTitled: (NSString*) title help: (NSString*) help;

- (PrefsPathRow*) addPathRowTitled: (NSString*) title
							  help: (NSString*) help
					   buttonTitle: (NSString*) buttonTitle
							target: (id) target
							action: (SEL) action;

//11pt, under the group, explaining the group rather than any one row.
- (void) addFootnote: (NSString*) text;

//the finished page view, sized to what was added
- (NSView*) view;

//first and last control, for the page's keyboard loop; either may be nil
- (NSView*) firstControl;
- (NSView*) lastControl;

@end
