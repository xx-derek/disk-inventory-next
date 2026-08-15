//
//  ToolbarWindowController.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 01.12.04.
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

//A window controller that builds its toolbar from a property list in the bundle
//rather than from code. The file is named after -toolbarConfigurationName with a
//".toolbar" extension and holds:
//
//    allowedItemIdentifiers  - every item the customization sheet offers
//    defaultItemIdentifiers  - the arrangement a fresh toolbar starts with
//    itemInfoByIdentifier    - one dictionary per item, with the keys
//                              "label", "paletteLabel", "toolTip", "imageName",
//                              "imageNameOffState", "imageNameMixedState",
//                              "action" and "target"
//
//"action" is a selector name. "target" is a key path evaluated against the
//controller, so an item can be aimed at something other than the window;
//leaving it out targets the controller, and "firstResponder" sends the action
//down the responder chain instead.
//
//Labels and tooltips are taken from the menu item with the same action wherever
//possible, so the wording only has to be written and localized once.
//
//(Previously OAToolbarWindowControllerEx, on top of OmniAppKit's
//OAToolbarWindowController; both are folded together here.)

@class ToolbarItem;

//Stands in for a menu item so a toolbar item can be validated by the same
//-validateMenuItem: code, forwarding anything it does not handle to the real
//toolbar item.
@interface NSToolbarItemValidationAdapter : NSObject
{
	NSToolbarItem* _toolbarItem;
}

- (void) setToolbarItem: (NSToolbarItem*) toolbarItem;

@end

@interface ToolbarWindowController : NSWindowController <NSToolbarDelegate>

//nil, the default, means the window has no toolbar
- (NSString*) toolbarConfigurationName;

//the whole property list backing the toolbar
- (NSDictionary*) toolbarConfigurationInfo;

//the description of one item, localized and completed from the main menu
- (NSDictionary*) toolbarInfoForItem: (NSString*) identifier;

//image for an item in a particular state, so a toggle can show what it will do
- (NSImage*) toolbar: (NSToolbar*) theToolbar
 imageForToolbarItem: (NSToolbarItem*) item
			forState: (NSControlStateValue) state;

// properties to resolve the "target" value for toolbar items
@property (readonly) NSDocumentController *documentController;
@property (readonly) NSApplication *application;

@end

//A toolbar item normally asks its own target whether it should be enabled,
//which leaves no say to anyone else when the target is the first responder.
//This one gives its delegate the last word instead.
@interface ToolbarItem : NSToolbarItem
{
	__weak id _delegate;
}

//sent -validateToolbarItem: whenever the item revalidates; weak, because the
//delegate is the window controller that owns this item's toolbar
@property (weak) id delegate;

@end
