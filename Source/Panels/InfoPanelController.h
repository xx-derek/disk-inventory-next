//
//  InfoPanelController.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 16.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import <Cocoa/Cocoa.h>
#import "FSItem.h"

@class DIXFileInfoView;

@interface InfoPanelController : NSObject
{
	//holds the top-level objects of the nib this controller loads
	NSArray *_nibTopLevelObjects;
	IBOutlet DIXFileInfoView *_infoView;
	//an NSPanel in all four nibs, and typed as one here because -init needs
	//-setWorksWhenModal: — see the comment there
	IBOutlet NSPanel* _infoPanel;
	IBOutlet NSTextField* _displayNameTextField;
	IBOutlet NSImageView* _iconImageView;
	//holds the panel's width against its own contents — see -init
	NSLayoutConstraint* _contentWidthConstraint;
}

+ (InfoPanelController*) sharedController;

- (BOOL) panelIsVisible;
- (void) showPanel;
- (void) hidePanel;
- (void) showPanelWithFSItem: (FSItem*) fsItem;
- (NSWindow*) panel;

@end
