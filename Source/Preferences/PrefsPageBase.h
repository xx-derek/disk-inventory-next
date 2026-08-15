//
//  PrefsPageBase.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 29.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import <Cocoa/Cocoa.h>

@class PrefsPageRecord, PrefsPageLayout;

//Runs one page of the preferences window. A subclass is the File's Owner of its
//own nib and connects the three outlets below; the controls themselves are
//bound to NSUserDefaultsController, so a page usually needs no code at all
//beyond existing.
//
//(Previously a subclass of OmniAppKit's OAPreferenceClient, which is folded in
//here.)

@interface PrefsPageBase : NSObject
{
	IBOutlet NSView *controlBox;

	//The page nibs connect these two on File's Owner as well. They have to be
	//declared or the connections fail during nib loading — silently, since
	//AppKit logs the unknown key rather than raising, which would cost the page
	//its keyboard focus and its tab order.
	IBOutlet NSView *initialFirstResponder;
	IBOutlet NSView *lastKeyView;

	PrefsPageRecord *_pageRecord;
	NSArray *_nibTopLevelObjects;
	PrefsPageLayout *_layout;
}

- (id) initWithPageRecord: (PrefsPageRecord*) pageRecord;

- (PrefsPageRecord*) pageRecord;
- (NSString*) title;

//Override to build the page in code; the default returns nil, which falls back
//to loading the page record's nib. Both paths still exist because a page that
//needs something a grid of checkboxes cannot express is better off in a nib.
- (NSView*) buildControlBox;

//Called by a subclass from -buildControlBox, so the base can take the keyboard
//loop from the layout it built.
- (void) setLayout: (PrefsPageLayout*) layout;

//the page's view, built or loaded on first use
- (NSView*) controlBox;

//the control that should take focus when the page is shown, and the last one in
//its tab order; either may be nil
- (NSView*) initialFirstResponder;
- (NSView*) lastKeyView;

//Resets every defaults key this page presents. Removal is bracketed with
//will/didChangeValueForKey:, because -removeObjectForKey: is not itself
//key-value observing compliant and bound controls would otherwise not notice.
- (void) restoreDefaultsNoPrompt;

//YES if any key this page presents differs from its registered default
- (BOOL) haveAnyDefaultsChanged;

//sent after the defaults behind the page were changed from outside it
- (void) valuesHaveChanged;

@end
