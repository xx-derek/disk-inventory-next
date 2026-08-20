//
//  DIXSummaryStripView.h
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

//The band above the map, answering the question the application is opened with
//before anything has to be clicked: how much is here, how many things is that,
//and how long ago was it counted.
//
//The delta block beside it - what has grown since the last scan - stays hidden
//until there is a previous scan to compare against, which is what the scan
//history provides. A "+0 GB" standing in for "nothing to compare" would be a
//statement, and a false one.

@interface DIXSummaryStripView : NSView

+ (CGFloat) preferredHeight;

//"94.6 GB" and "71,204 files · 9,812 folders · scanned 2 minutes ago"
- (void) setTotal: (NSString*) total subtitle: (NSString*) subtitle;

//"+2.81 GB" and "since 8 Aug". Passing nil for the delta hides the block and
//the rule beside it.
- (void) setDelta: (NSString*) delta
		  caption: (NSString*) caption
		 isGrowth: (BOOL) isGrowth;

//Wired by the window controller to the actions that already exist on it:
//-refreshAll:, -zoomIn:, -zoomOut:.
- (void) setTarget: (id) target
	  rescanAction: (SEL) rescanAction
	  zoomInAction: (SEL) zoomInAction
	 zoomOutAction: (SEL) zoomOutAction;

//enabled state for the two zoom buttons, which the menu validates separately
- (void) setZoomInEnabled: (BOOL) zoomIn zoomOutEnabled: (BOOL) zoomOut;

@end
