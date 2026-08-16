//
//  InfoPanelController.m
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

#import "InfoPanelController.h"
#import "DIXFileInfoView.h"
//-isEqualToURL: used to arrive through NTInfoView.h; the replacement header
//does not drag it in, so name the dependency here
#import "NSURL-Extensions.h"

//The nib opens the panel 228 points wide. That leaves about 133 points for the
//value column once the title column, the gap and the edge insets are taken out,
//which is narrow enough that a path or a permission string wraps to three or
//four lines and the panel reads as a column of fragments. The three other
//localizations have longer titles than English and fare worse.
//
//Set here rather than in the four nibs: it is one number, and editing it in the
//nibs means the ibtool round trip in every language for no gain.
static const CGFloat kInfoPanelDefaultContentWidth = 360.0;

//Below this the two-column grid stops being a grid. The nib says 150.
static const CGFloat kInfoPanelMinimumContentWidth = 240.0;

static NSString * const kInfoPanelFrameAutosaveName = @"DIXInfoPanel";

@implementation InfoPanelController

+ (InfoPanelController*) sharedController
{
	static InfoPanelController *controller = nil;
	
	if ( controller == nil )
		controller = [[InfoPanelController alloc] init];
	
	return controller;
}

- (id) init
{
	self = [super init];
		
	//load Nib with info panel
	//Under the old +loadNibNamed:owner: the nib's top-level objects were
	//retained (and leaked) for us. The replacement hands them back
	//autoreleased, so they have to be held or the panel is deallocated on
	//the way out of this method.
    NSArray *topLevelObjects = nil;
    const BOOL loadedNib = [[NSBundle mainBundle] loadNibNamed: @"InfoPanel" owner: self topLevelObjects: &topLevelObjects];
    _nibTopLevelObjects = topLevelObjects;
    if ( !loadedNib )
	{
		self = nil;
	}
	else
	{
		//A scan runs the progress panel in an application-modal session, and a
		//modal session cuts every other window off from the event queue — so
		//while a scan was in progress this panel could not be resized, scrolled
		//or closed, and a long scan of a slow volume froze it for minutes.
		//
		//The scan itself has run on a background queue since 2026-08-15; the
		//modal session is only there to hold the progress panel up and keep the
		//main thread pumping. Nothing about it needs this panel inert, and the
		//panel is read-only: it displays the selected item and owns no command
		//that could disturb a running scan.
		//
		//Note the filtering happens where the event is dequeued, inside
		//-runModalSession:, not in -[NSApplication sendEvent:] — an event handed
		//straight to -sendEvent: reaches the window either way, so this cannot be
		//verified without going through the queue.
		[_infoPanel setWorksWhenModal: YES];

		[_infoPanel setContentMinSize: NSMakeSize( kInfoPanelMinimumContentWidth,
												   [_infoPanel contentMinSize].height )];

		//A panel the user has resized should stay that size across launches, which
		//this one never did - it had no autosave name at all, so every launch
		//brought back the nib's width. -setFrameUsingName: answers NO when there
		//is nothing remembered, and that is the only time the wider default
		//should be imposed: otherwise it would overwrite whatever size the user
		//had settled on. The name is registered afterwards, because
		//-setFrameAutosaveName: saves the current frame as it is set.
		const BOOL restoredSavedFrame = [_infoPanel setFrameUsingName: kInfoPanelFrameAutosaveName];

		if ( !restoredSavedFrame )
		{
			const CGFloat contentWidth = NSWidth( [[_infoPanel contentView] frame] );

			if ( contentWidth < kInfoPanelDefaultContentWidth )
			{
				NSRect frame = [_infoPanel frame];
				frame.size.width += kInfoPanelDefaultContentWidth - contentWidth;

				//AppKit constrains this to the screen when the panel is ordered
				//front, so growing rightwards cannot push it out of reach
				[_infoPanel setFrame: frame display: NO];
			}
		}

		[_infoPanel setFrameAutosaveName: kInfoPanelFrameAutosaveName];

		//Widen the panel, then zoom in on the treemap, and the panel used to
		//snap to a stub about 90 points wide and stay there: zooming out did
		//not bring it back, and neither did selecting something else. The panel
		//was not doing it - AppKit was, in
		//-[NSWindow _changeWindowFrameFromConstraintsIfNecessary], which sizes a
		//window to what its content's constraints solve to. A backtrace from a
		//swizzled -setFrame:display: is what named it; nothing in this file or
		//in DIXFileInfoView appears in that stack.
		//
		//Half the cause is in DIXFileInfoView, where the grid used to be pinned
		//to the clip view's width by a *required* equality - see the comment
		//there. This is the other half: with that equality relaxed nothing
		//required the panel to collapse any more, but nothing held its width
		//either, so the engine still settled it on the content's fitting width.
		//
		//So the panel's own width is stated as a constraint, and the priority
		//is the whole point of it. AppKit holds a window's size at
		//NSLayoutPriorityWindowSizeStayPut, which is 500, and a constraint of
		//500 - or of 501 - still lost, both measured. DefaultHigh holds, and
		//being below Required it can still be given up if something ever
		//genuinely requires otherwise, so it cannot make the layout
		//unsatisfiable. -_panelDidResize: keeps the constant in step.
		//
		//Width only: the height of this chain is not tied to the grid, whose
		//top alone is pinned - that is what leaves the scroll view something to
		//scroll.
		NSView *contentView = [_infoPanel contentView];

		_contentWidthConstraint = [[contentView widthAnchor]
									constraintEqualToConstant: NSWidth( [contentView frame] )];
		[_contentWidthConstraint setPriority: NSLayoutPriorityDefaultHigh];
		[_contentWidthConstraint setActive: YES];

		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(_panelDidResize:)
													 name: NSWindowDidResizeNotification
												   object: _infoPanel];

		/*
		NSRect frameRect = [_infoView frame];
		
		[_infoView removeFromSuperviewWithoutNeedingDisplay];
		
		_infoView = [[DIXFileInfoView alloc] initWithFrame: frameRect longFormat: YES];
		
		[_infoView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
		
		[[_infoPanel contentView] addSubview: _infoView];
		 */
	}
	
	return self;
}


//The width the panel is held at is the width it has, so a resize is adopted
//rather than fought. Measured: -setFrame: on the panel is honoured whatever
//this constraint currently says, and this then puts the constant back in step,
//so the next content change holds the new width rather than the old one.
//
//A real drag of the resize corner is the one part no probe can synthesise -
//faking -inLiveResize does not reproduce a live resize - so that still wants a
//person. What can be said is that the constraint is below Required and so
//cannot make the resize impossible.
- (void) _panelDidResize: (NSNotification*) notification
{
	[_contentWidthConstraint setConstant: NSWidth( [[_infoPanel contentView] frame] )];
}

- (BOOL) panelIsVisible
{
	return [[self panel] isVisible];
}

- (void) showPanel
{
	[[self panel] orderFront: nil];
}

- (void) hidePanel
{
	[[self panel] orderOut: nil];
}

- (NSWindow*) panel
{
	return _infoPanel;
}

- (void) showPanelWithFSItem: (FSItem*) fsItem
{
	[self showPanel];
	
	if ( fsItem == nil || [fsItem fileURL] == nil)
	{
		[_displayNameTextField setStringValue: @""];
		[_iconImageView setImage: nil];

		[_infoView setURL: nil];
	}
	else if ( [_infoView URL] == nil
             || ![[fsItem fileURL] isEqualToURL: [_infoView URL]] )
	{
		[_displayNameTextField setStringValue: [fsItem displayName]];
		[_iconImageView setImage: [fsItem iconWithSize: 32]];
        
        [_infoView setURL: [fsItem fileURL]];
	}
}

@end
