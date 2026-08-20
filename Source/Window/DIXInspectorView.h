//
//  DIXInspectorView.h
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

@class FSItem;
@class FileSystemDoc;
@class DIXFileInfoView;

//The pane down the right-hand side of the window: what is selected, how big it
//is, and what can be done with it.
//
//It replaces the floating Info window, which had to be opened from a menu, sat
//over the map, and described the selection from a separate window that could be
//left behind on another space. The attribute rows are the same DIXFileInfoView
//it used, reparented - the panel was only ever a frame around that view.

@interface DIXInspectorView : NSView

//Width the window should give the pane, per the design.
+ (CGFloat) preferredWidth;

//Shows one item, or nothing when it is nil.
- (void) setItem: (FSItem*) item;

//The document behind the siblings section, which needs the kind statistics and
//the reclaim basket. Separate from -setItem: because it changes once and the
//selection changes constantly.
- (void) setDocument: (FileSystemDoc*) document;
- (void) setReclaimTarget: (id) target action: (SEL) action;

//Wires the three header buttons to actions that already exist on the window
//controller: -showInFinder:, -openFile:, -moveToTrash:.
- (void) setTarget: (id) target
	  revealAction: (SEL) revealAction
		openAction: (SEL) openAction
	   trashAction: (SEL) trashAction;

//enabled state, driven by the same conditions -validateMenuItem: uses
- (void) setRevealEnabled: (BOOL) reveal
			  openEnabled: (BOOL) open
			 trashEnabled: (BOOL) trash;

@end
