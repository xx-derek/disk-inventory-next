//
//  DIXFileInfoView.h
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

#import <Cocoa/Cocoa.h>

//The scrolling title/value list in the Info panel: name, kind, dates, owner,
//permissions, path and so on for one file.
//
//This used to be three vendored CocoaTech classes (NTInfoView gathering the
//rows, NTTitledInfoView laying them out by hand, NTTitledInfoPair carrying one
//pair). The layout is now an NSGridView, so the measuring, positioning and
//glyph drawing are AppKit's problem.
//
//The class name is load-bearing: all four InfoPanel.nib bundles name
//DIXFileInfoView, as an NSCustomView placeholder. That placeholder instantiates
//it with -initWithFrame:, not -initWithCoder:, which is why both have to work.

@interface DIXFileInfoView : NSView
{
	NSURL *_URL;
	NSGridView *_grid;
	NSScrollView *_scrollView;
}

@property (nonatomic, strong) NSURL *URL;

@end
