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
	PrefsPageLayout *layout = [PrefsPageLayout layout];

	//The nib left this one with an empty label column, which is what made the
	//two pages look like they belonged to different applications.
	[layout beginSectionWithLabel: @"Zooming:"];

	[layout addCheckboxTitled: @"Animated Zooming"
				  defaultsKey: AnimatedZooming
						 help: @"Turn this off if the animation is too slow on your machine or if you don't like it."];

	[layout beginSectionWithLabel: @"View settings for new windows:"];

	[layout addCheckboxTitled: @"Show Free Space"
				  defaultsKey: ShowFreeSpace
						 help: @"This shows free space like a file in the treemap. It helps to see the size relations between the opened folder and the free space on the drive."];

	[layout addCheckboxTitled: @"Show Other Space"
				  defaultsKey: ShowOtherSpace
						 help: @"This shows space used by not shown files and folders like a file in the treemap. It helps to see how the opened folder compares in size to the rest of the files on the same drive. This option is only available if not a whole drive is shown."];

	[layout addCheckboxTitled: @"Label Large Cells"
				  defaultsKey: LabelLargeCells
						 help: @"Write the name and size into cells big enough to hold them."];

	[layout addCheckboxTitled: @"Classic Cushion Shading"
				  defaultsKey: ClassicCushions
						 help: @"Draw cells as nested pillows, the way Disk Inventory X always has. Turned off, each cell is flat with a bevelled edge, which stays readable when the map is dense - a pillow stretched across a large cell reads as a glow rather than as a shape."];

	[self setLayout: layout];

	return [layout view];
}

@end
