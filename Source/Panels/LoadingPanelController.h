//
//  LoadingPanelController.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 03.12.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import <Cocoa/Cocoa.h>


@interface LoadingPanelController : NSObject
{
	//holds the top-level objects of the nib this controller loads
	NSArray *_nibTopLevelObjects;
	NSModalSession _loadingPanelModalSession;
	BOOL _cancelPressed;
	NSString *_message;
    IBOutlet NSTextField* _loadingTextField;
    IBOutlet NSPanel* _loadingPanel;
    IBOutlet NSProgressIndicator* _loadingProgressIndicator;
    IBOutlet NSButton* _loadingCancelButton;
}

- (id) init; //will start modal session immediately
- (id) initAsSheetForWindow: (NSWindow*) window; //will start modal session immediately

- (void) close;
- (void) closeNoModalEnd;

- (void) enableCancelButton: (BOOL) enable; //button is enabled by default

//Safe to call from the scan queue: the flag is set on the main thread by the
//Cancel button and read from whichever thread is doing the loading.
- (BOOL) cancelPressed;

- (void) startAnimation;
- (void) stopAnimation;

//Shown the next time the panel gets a chance to draw. Main thread only.
- (void) setMessageText: (NSString*) msg;

//Runs the panel's own event handling for up to "seconds", so a caller waiting
//on work happening on another thread can keep the panel alive without spinning.
//Returns NO once the modal session has ended.
//
//This replaces -runEventLoop, which the scan used to call from inside the
//directory walk every 0.2 seconds. The walk no longer runs on the main thread,
//so there is nothing to interleave with: the main thread now does only this.
- (BOOL) runModalSessionForInterval: (NSTimeInterval) seconds;

- (IBAction) cancel:(id)sender;

@end
