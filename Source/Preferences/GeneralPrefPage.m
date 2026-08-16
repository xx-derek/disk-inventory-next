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

//the choices offered in the pop-up, from the bounds the preference declares
static NSArray<NSNumber*>* ScanConcurrencyValues( void )
{
	NSMutableArray *values = [NSMutableArray array];

	for ( NSInteger i = ScanConcurrencyMinimum; i <= ScanConcurrencyMaximum; i++ )
		[values addObject: [NSNumber numberWithInteger: i]];

	return values;
}

@implementation GeneralPrefPage

//The strings are the English text: they are the keys into Preferences.strings,
//which is where the German, Spanish and French wording lives now that the page
//is no longer a nib per language.
- (NSView*) buildControlBox
{
	PrefsPageLayout *layout = [PrefsPageLayout layout];

	[layout beginSectionWithLabel: @"View settings for new windows:"];

	[layout addCheckboxTitled: @"Show Package Contents"
				  defaultsKey: ShowPackageContents
						 help: nil];

	[layout addCheckboxTitled: @"Ignore Creator Code"
				  defaultsKey: IgnoreCreatorCode
						 help: @"If set, e.g. PDF files opened by the Finder with Acrobat or Preview are be regarded to have the same kind."];

	[layout addCheckboxTitled: @"Show Physical File Size"
				  defaultsKey: ShowPhysicalFileSize
						 help: @"The physical size is the space that a file occupies on a drive. Many applications show the logical size, which is the size of a file's content."];

	[layout addCheckboxTitled: @"Split window horizontally"
				  defaultsKey: SplitWindowHorizontally
						 help: nil];

	[layout beginSectionWithLabel: @"Use small font in:"];

	[layout addCheckboxTitled: @"Files View"
				  defaultsKey: UseSmallFontInFilesView
						 help: nil];

	[layout addCheckboxTitled: @"Kind Statistic Drawer"
				  defaultsKey: UseSmallFontInKindStatistic
						 help: nil];

	[layout addCheckboxTitled: @"Selection List"
				  defaultsKey: UseSmallFontInSelectionList
						 help: nil];

	//Concurrency is a setting rather than a constant because it is the one part
	//of the scan whose best value depends on the drive: a fast internal SSD
	//likes several requests outstanding, a network share or a spinning disk can
	//be made slower by them. One walks everything in order, as the scan did
	//before this was settable.
	[layout beginSectionWithLabel: @"Scanning:"];

	[layout addPopUpWithValues: ScanConcurrencyValues()
				   defaultsKey: ScanConcurrency
				 trailingTitle: @"folders at a time"
						  help: @"How many folders inside the one being scanned are read at the same time. Higher is usually faster on an internal drive; choose 1 to scan everything in order, which can be better over a network."];

	//This one had no label column in the nib and so broke the alignment of
	//everything above it; it gets a section of its own now.
	[layout beginSectionWithLabel: @"File kind colors:"];

	[layout addCheckboxTitled: @"Use the same color for each file kind in all windows"
				  defaultsKey: ShareKindColors
						 help: nil];

	[self setLayout: layout];

	return [layout view];
}

@end
