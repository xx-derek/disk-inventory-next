//
//  GeneralPrefPage.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 27.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "GeneralPrefPage.h"

#import "PrefsPageLayout.h"
#import "Preferences.h"

@implementation GeneralPrefPage

//The strings are the English text: they are the keys into Preferences.strings,
//which is where the German, Spanish and French wording lives now that the page
//is no longer a nib per language.
- (NSView*) buildControlBox
{
	PrefsPageLayout *layout = [PrefsPageLayout layoutWithWidth: [[self class] contentWidth]];

	[layout beginSectionWithLabel: @"New windows"];

	[layout addToggleTitled: @"Show package contents"
					   help: @"Treat app bundles as folders and descend into them."
				defaultsKey: ShowPackageContents];

	[layout addToggleTitled: @"Show physical file size"
					   help: @"The space a file occupies on disk rather than the size of its content."
				defaultsKey: ShowPhysicalFileSize];

	[layout addToggleTitled: @"Ignore creator code"
					   help: @"PDFs opened with Preview and with Acrobat count as one kind."
				defaultsKey: IgnoreCreatorCode];

	[layout addFootnote: @"These become the starting view options of each new scan; a window can still change its own."];

	[layout beginSectionWithLabel: @"On launch"];

	//SplitWindowHorizontally and the three UseSmallFontIn… keys are deliberately
	//not here. The new layout has one split and one type scale, so there is
	//nothing for them to change; they are still read, so an existing user's
	//value is not thrown away, just no longer offered.
	[layout addPopUpTitled: @"Open with"
					  help: @"What the app shows when you start it with no document."
			   defaultsKey: OpenWith
					titles: @[ @"Last scanned volume", @"The volume picker", @"Nothing" ]
					values: @[ @(DIXOpenWithLastVolume), @(DIXOpenWithPicker), @(DIXOpenWithNothing) ]];

	//"Reopen the last scan" is in the design and is deliberately not here: it
	//offers to restore a saved result instead of rescanning, and nothing is
	//saved - a scan is a tree in memory that goes when the window closes.
	//"Last scanned volume" above therefore means scanning it again, which is
	//why the default is the picker rather than that.

	[self addRestoreDefaultsSectionTo: layout
								 help: @"Returns this tab to its factory settings. Hold ⌥ to reset every tab."];

	[self setLayout: layout];

	return [layout view];
}

@end
