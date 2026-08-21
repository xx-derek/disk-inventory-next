//
//  TreeMapPrefPage.m
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

#import "TreeMapPrefPage.h"
#import "PrefsPageLayout.h"
#import "Preferences.h"

@implementation TreeMapPrefPage

- (NSView*) buildControlBox
{
	PrefsPageLayout *layout = [PrefsPageLayout layoutWithWidth: [[self class] contentWidth]];

	[layout beginSectionWithLabel: @"Zooming"];

	[layout addToggleTitled: @"Animated zooming"
					   help: @"Turn off if the animation is slow on your machine."
				defaultsKey: AnimatedZooming];

	[layout beginSectionWithLabel: @"Cells"];

	[layout addToggleTitled: @"Show free space"
					   help: @"Draw free space as a cell so you can compare it with the folder."
				defaultsKey: ShowFreeSpace];

	[layout addToggleTitled: @"Show other space"
					   help: @"Space used by files outside the scanned folder, on the same drive."
				defaultsKey: ShowOtherSpace];

	[layout addToggleTitled: @"Label large cells"
					   help: @"Write the name and size into cells big enough to hold them."
				defaultsKey: LabelLargeCells];

	//Not in the design, and kept anyway: it is the switch between the shading
	//this application has always drawn and the one the redesign asks for, and
	//removing it would take the original away rather than offer the new one.
	[layout addToggleTitled: @"Classic cushion shading"
					   help: @"Draw cells as nested pillows, the way Disk Inventory X always has. Turned off, each cell is flat with a bevelled edge."
				defaultsKey: ClassicCushions];

	[layout addFootnote: @"Free space and other space are drawn neutral on purpose — they are not file kinds."];

	[layout beginSectionWithLabel: @"Colors"];

	[layout addToggleTitled: @"Same colors in every window"
					   help: @"A file kind keeps its color across scans and windows."
				defaultsKey: ShareKindColors];

	[self addRestoreDefaultsSectionTo: layout
								 help: @"Returns this tab to its factory settings. Open windows keep their current view options."];

	[self setLayout: layout];

	return [layout view];
}

@end
