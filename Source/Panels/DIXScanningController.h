//
//  DIXScanningController.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 03.12.04 as LoadingPanelController.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"

//The screen a scan runs behind: what has been found, how fast, where the walk
//is, and the three biggest files so far. It replaces the modal LoadingPanel
//nib, and it is a window of the design's own rather than a progress bar in a
//box - the same 560pt width as the volume picker it follows, so picking a
//volume and watching it counted read as one thing.
//
//It is still a modal session, and for the same reason as before: the main
//thread has nothing else to do while the walk runs on its queue, and a modal
//session is what keeps Cancel answering while it waits. See
//-[FileSystemDoc _runScanBlockOffMainThread:estimatingFrom:].
@interface DIXScanningController : NSObject

//Starts the modal session immediately. "title" is the name of what is being
//scanned, which the window carries in its title bar.
- (instancetype) initWithTitle: (NSString*) title;

//Placed over "frame" instead of centred, so that when the volume picker is what
//started this, the screen appears where the picker was and reads as the same
//window carrying on.
- (void) takeFrameFrom: (NSWindow*) window;

- (void) close;
- (void) closeNoModalEnd;

//Both are set on the main thread by their buttons and read from the scan's
//wait loop, which is also the main thread - but the flags are guarded anyway,
//since a caller is free to ask from the queue.
- (BOOL) cancelPressed;
- (BOOL) partialResultsPressed;

- (void) enableCancelButton: (BOOL) enable;

//A refresh has no use for partial results - it would replace a subtree that is
//complete with one that is not - so it hides the button rather than offering
//something it cannot honour. YES by default.
- (void) setAllowsPartialResults: (BOOL) allows;

//Everything the screen draws, in one call, from the document's own reading.
//Main thread only.
- (void) setProgress: (DIXScanProgress) progress;

//Where the walk is now, shown truncated at the head. Main thread only.
- (void) setCurrentPath: (NSString*) path;

//The three biggest files so far, as FSItemBiggestFilesSoFar() returns them.
- (void) setBiggestFiles: (NSArray<NSDictionary*>*) biggest;

//Runs the screen's own event handling for up to "seconds", so a caller waiting
//on work happening on another thread can keep it alive without spinning.
//Returns NO once the modal session has ended.
- (BOOL) runModalSessionForInterval: (NSTimeInterval) seconds;

- (IBAction) cancel: (id) sender;
- (IBAction) showPartialResults: (id) sender;

@end
