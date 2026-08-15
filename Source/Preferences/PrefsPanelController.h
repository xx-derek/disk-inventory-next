//
//  PrefsPanelController.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 28.11.04.
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

@class PrefsPageBase, PrefsPageRecord;

//The preferences window: a toolbar of pages over a content area that swaps to
//whichever page is selected. The pages come from Info.plist, under
//Registrations keyed by the name of this class, and their titles are localized
//through "Preferences.strings".
//
//(Previously a subclass of OmniAppKit's OAPreferenceController, which is folded
//in here.)

@interface PrefsPanelController : NSWindowController <NSToolbarDelegate>
{
	NSMutableDictionary *_pagesByIdentifier;
	PrefsPageRecord *_currentPageRecord;
	PrefsPageBase *_currentPage;
	BOOL _windowBuilt;
}

+ (PrefsPanelController*) sharedPreferenceController;

//every registered page, hidden ones included, in the order they are shown
+ (NSArray*) allPageRecords;

+ (PrefsPageRecord*) pageRecordWithIdentifier: (NSString*) identifier;

//"pageName" is the name of the PrefsPageBase subclass running the page;
//registering a page whose class is not in the binary is ignored
+ (void) registerPageName: (NSString*) pageName description: (NSDictionary*) description;

- (IBAction) showPreferencesPanel: (id) sender;

//asks first, then resets
- (IBAction) restoreDefaults: (id) sender;

- (PrefsPageBase*) currentPage;
- (void) setCurrentPageRecord: (PrefsPageRecord*) pageRecord;

@end
