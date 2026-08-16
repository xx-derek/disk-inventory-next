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

//Builds one preferences page: a two-column grid of right-aligned section labels
//against a column of checkboxes, with optional explanatory text under a
//checkbox. Pages used to be a nib per page per language — eight bundles for two
//pages — which is why the two of them had drifted into different shapes.
//Describing a page in code means the alignment is a property of the layout
//rather than of whoever last opened Interface Builder.
//
//Titles are localized through the "Preferences" table, so the strings passed in
//are the English text, matching the convention everywhere else in the project.

@interface PrefsPageLayout : NSObject
{
	NSGridView *_grid;
	NSMutableArray<NSButton*> *_checkboxes;
	NSMutableArray<NSView*> *_controls;
	NSMutableArray<NSTextField*> *_helpFields;
	NSButton *_firstCheckbox;
	NSButton *_lastCheckbox;
	NSString *_pendingSectionLabel;
}

+ (instancetype) layout;

//Starts a group. The label sits against the first row added after this call;
//pass nil for a group that needs no label.
- (void) beginSectionWithLabel: (NSString*) label;

//A checkbox bound to a user-defaults key, with optional explanatory text
//beneath it in the same column.
- (void) addCheckboxTitled: (NSString*) title
			   defaultsKey: (NSString*) defaultsKey
					  help: (NSString*) help;

//A pop-up of numbers bound to a user-defaults key, with a caption after it, so
//a page can carry a small bounded choice as well as on/off. The values become
//the menu items' tags, which is what the binding matches against, so the stored
//preference is the number itself rather than a menu position.
- (void) addPopUpWithValues: (NSArray<NSNumber*>*) values
				defaultsKey: (NSString*) defaultsKey
			  trailingTitle: (NSString*) trailingTitle
					   help: (NSString*) help;

//the finished page view
- (NSView*) view;

//first and last control, for the page's keyboard loop; either may be nil
- (NSView*) firstControl;
- (NSView*) lastControl;

@end
