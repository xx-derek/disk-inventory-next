//
//  DIXChangesController.h
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

@class FileSystemDoc;
@class FSItem;

//"Since 8 Aug": what this folder gained and lost since the last time it was
//scanned, biggest first. The whole of the answer the application is opened with,
//in one window - where the summary strip beside the map only has room for the
//one figure.
//
//A window of its own rather than a sheet, which is how the design draws it: it
//is read against the map behind it, and a sheet would be over the top of the
//thing it is describing.
@protocol DIXChangesDelegate <NSObject>

//"Show only these on the map" - narrow the map to what changed, or stop.
- (void) changesControllerSetShowsOnlyChanges: (BOOL) showsOnlyChanges;

//"Review 2.81 GB" - go to the biggest of them in the main window.
- (void) changesControllerReviewItem: (FSItem*) item;

@end

@interface DIXChangesController : NSWindowController

- (instancetype) initWithDocument: (FileSystemDoc*) document;

//__weak on the implementation side: the main window controller owns this.
@property (nonatomic, weak) id<DIXChangesDelegate> changesDelegate;

//Rebuilds from the document and brings the window forward. Cheap enough to do
//on every showing, which is what keeps the row list and the button titles in
//step with a filter that can be switched off from elsewhere.
- (void) showChanges;

@end
