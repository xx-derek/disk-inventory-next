//
//  MainWindow.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 19.03.06.
//  Copyright 2006 Tjark Derlien. All rights reserved.
//

#import "MainWindow.h"
#import "MainWindowController.h"


@implementation MainWindow

//NSWindow implements -toggleSidebar: itself. The standard sidebar toolbar item
//has a nil target, so the action walks the responder chain — and the walk stops
//at the window, which is *before* the window controller. Without this the
//button would be present, enabled, and do nothing at all.
//
//AppKit's own sidebar handling works because NSSplitViewController sits in the
//chain ahead of the window, via the content view controller. This window is
//nib-based and has no content view controller, so the forward is explicit.
- (IBAction) toggleSidebar: (id) sender
{
	MainWindowController *controller = (MainWindowController*) [self windowController];

	if ( [controller isKindOfClass: [MainWindowController class]] )
		[controller toggleSidebar: sender];
}

// the TreeMapView now uses NSTrackingArea to receive mouseMoved-Events even when it is not first responder,
// so we do not need to propagate this event anymore
/*
- (void) mouseMoved: (NSEvent *)theEvent
{
    [super mouseMoved: theEvent];
	
	//give the treemap view a chance to handle mouseMoved events even if it's not the first responder
	if ( [self firstResponder] != _treeMapView && NSPointInRect( [theEvent locationInWindow], [_treeMapView frame]))
		[_treeMapView mouseMoved: theEvent];
}
*/

+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    completionHandler(nil, nil);
}

@end
