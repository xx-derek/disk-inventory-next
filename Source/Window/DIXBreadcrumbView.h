//
//  DIXBreadcrumbView.h
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

//The zoom stack, made visible and clickable, in the place a window title would
//normally sit: "Macintosh HD › Users › derek › Movies".
//
//The stack itself is not new - the document has always kept one, and
//MyDocumentController exposes it as a menu nobody finds. What is new is that it
//is on screen, so where you are and how to get back are the same control.
//
//The last segment is where you are and is not a button. Every earlier one zooms
//back out to that item when clicked.

@interface DIXBreadcrumbView : NSView

//Segments from root to current. Each entry's title is shown; its represented
//object comes back as the sender's -representedObject when clicked, so the
//caller gets its FSItem back without this view knowing what one is.
- (void) setSegmentTitles: (NSArray<NSString*>*) titles
	   representedObjects: (NSArray*) objects;

//Sent when an ancestor segment is clicked. The sender is an NSMenuItem-like
//stand-in carrying -representedObject, so an existing zoomOutTo:-style action
//can be reused unchanged.
- (void) setTarget: (id) target action: (SEL) action;

//width the toolbar item should ask for
- (CGFloat) fittingWidth;

@end
