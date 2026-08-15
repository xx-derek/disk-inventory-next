//
//  LoadingPanelController.m
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

#import "LoadingPanelController.h"


@implementation LoadingPanelController

- (id) init
{
	self = [super init];
	
    //load Nib with progress panel
	//Under the old +loadNibNamed:owner: the nib's top-level objects were
	//retained (and leaked) for us. The replacement hands them back
	//autoreleased, so they have to be held or the panel is deallocated on
	//the way out of this method.
	NSArray *topLevelObjects = nil;
	const BOOL loadedNib = [[NSBundle mainBundle] loadNibNamed: @"LoadingPanel" owner: self topLevelObjects: &topLevelObjects];
	_nibTopLevelObjects = topLevelObjects;
	//This panel's nib does not set "release when closed", so AppKit defaults it
	//to YES and releases the panel itself on -close. That used to be balanced
	//by +loadNibNamed:owner: leaking the nib's top-level objects. Now that
	//_nibTopLevelObjects owns them properly, AppKit's release is one too many
	//and the app crashes tearing the window down.
	[_loadingPanel setReleasedWhenClosed: NO];
	if ( !loadedNib )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	
	//Deliberately not started here. Once the bar has begun its indeterminate
	//animation inside a modal session, -setIndeterminate:NO does not reliably
	//stop it drawing: -isIndeterminate answers NO while the barber pole carries
	//on over the top of the value. -setProgressFraction: starts the animation
	//only when it knows there is no estimate to show.
	[_loadingProgressIndicator setUsesThreadedAnimation: NO];
	
	[_loadingPanel display];
	
	//start modal session for the progress window
	_loadingPanelModalSession = [[NSApplication sharedApplication] beginModalSessionForWindow: _loadingPanel];
	
	_cancelPressed = NO;
	
	return self;
}

- (id) initAsSheetForWindow: (NSWindow*) window
{
	self = [super init];
	
    //load Nib with progress panel
	NSArray *topLevelObjects = nil;
	const BOOL loadedNib = [[NSBundle mainBundle] loadNibNamed: @"LoadingPanel" owner: self topLevelObjects: &topLevelObjects];
	_nibTopLevelObjects = topLevelObjects;
	//This panel's nib does not set "release when closed", so AppKit defaults it
	//to YES and releases the panel itself on -close. That used to be balanced
	//by +loadNibNamed:owner: leaking the nib's top-level objects. Now that
	//_nibTopLevelObjects owns them properly, AppKit's release is one too many
	//and the app crashes tearing the window down.
	[_loadingPanel setReleasedWhenClosed: NO];
	if ( !loadedNib )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	
	//-beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo: was
	//deprecated in 10.10; nothing was ever passed for the delegate callback, so
	//the completion handler is nil too.
	[window beginSheet: _loadingPanel completionHandler: nil];
	
	[_loadingPanel setWorksWhenModal: YES];
	
	//see -init: the animation is started by -setProgressFraction:, not here
	[_loadingProgressIndicator setUsesThreadedAnimation: NO];
	
	//we don't have modal session if we show the panel as a sheet
	_loadingPanelModalSession = 0;
	
	
	_cancelPressed = NO;
	
	return self;
}

- (void) dealloc
{
	if ( _loadingPanel != nil )
		[self close];
	
}

- (void) close
{
	if ( [_loadingPanel isSheet] )
	{
		[[_loadingPanel sheetParent] endSheet: _loadingPanel];
		[_loadingPanel close]; //we own it through _nibTopLevelObjects, not AppKit
		
		_loadingPanel = nil;
		_percentageField = nil;
		_loadingProgressIndicator = nil;
		_loadingTextField = nil;
		_loadingCancelButton = nil;
	}
	else
	{
		NSAssert( _loadingPanelModalSession != 0, @"no modal session is running" );
		[[NSApplication sharedApplication] endModalSession: _loadingPanelModalSession];
		_loadingPanelModalSession = 0;
		
		[self closeNoModalEnd];
	}
}

- (void) closeNoModalEnd
{
	//this only works if we startet a modal session for a panel (no sheet)
	NSAssert( ![_loadingPanel isSheet], @"the loading panel is already a sheet" );
	
	//the sender asked us not to end the modal session (maybe because sender has run into an exception)
	_loadingPanelModalSession = 0;
	
	[_loadingPanel close]; //we own it through _nibTopLevelObjects, not AppKit
	
	_loadingPanel = nil;
	_percentageField = nil;
    _loadingProgressIndicator = nil;
	_loadingTextField = nil;
	_loadingCancelButton = nil;
}

- (void) enableCancelButton: (BOOL) enable
{
	[_loadingCancelButton setEnabled: enable];
}

- (BOOL) cancelPressed
{
	//read from the scan queue, written on the main thread
	@synchronized ( self )
	{
		return _cancelPressed;
	}
}

//The nib has no room reserved for this and there are four of them, so the label
//is made here. It sits in the gap between the progress bar and the Cancel
//button, left of the button.
- (void) _ensurePercentageField
{
	if ( _percentageField != nil || _loadingProgressIndicator == nil )
		return;

	const NSRect barFrame = [_loadingProgressIndicator frame];

	_percentageField = [NSTextField labelWithString: @""];
	[_percentageField setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
	[_percentageField setTextColor: [NSColor secondaryLabelColor]];
	[_percentageField setFrame: NSMakeRect( NSMinX(barFrame), NSMinY(barFrame) - 24.0, 160.0, 17.0 )];
	[_percentageField setAutoresizingMask: NSViewMaxXMargin | NSViewMaxYMargin];

	[[_loadingPanel contentView] addSubview: _percentageField];
}

- (void) setProgressFraction: (double) fraction
{
	[self _ensurePercentageField];

	if ( fraction < 0.0 )
	{
		//No estimate: the barber's pole. The indicator starts out indeterminate
		//from the nib but stopped, so -startAnimation: has to be sent whether or
		//not this is a transition — it is idempotent once running.
		if ( ![_loadingProgressIndicator isIndeterminate] )
			[_loadingProgressIndicator setIndeterminate: YES];

		[_loadingProgressIndicator startAnimation: nil];

		[_percentageField setStringValue: @""];
		return;
	}

	if ( [_loadingProgressIndicator isIndeterminate] )
	{
		[_loadingProgressIndicator stopAnimation: nil];
		[_loadingProgressIndicator setIndeterminate: NO];
		[_loadingProgressIndicator setMinValue: 0.0];
		[_loadingProgressIndicator setMaxValue: 100.0];
	}

	//Held below 100 until the scan actually finishes. The total is an estimate,
	//and a bar that sits full while the disk is still rattling reads as a hang.
	double percent = fraction * 100.0;
	if ( percent > 99.0 )
		percent = 99.0;

	[_loadingProgressIndicator setDoubleValue: percent];
	[_percentageField setStringValue: [NSString stringWithFormat: @"%.0f%%", percent]];
}

- (void) startAnimation;
{
	[_loadingProgressIndicator startAnimation: nil];
}

- (void) stopAnimation;
{
	[_loadingProgressIndicator stopAnimation: nil];
}

- (void) setMessageText: (NSString*) msg
{
	_message = msg;
}

- (BOOL) runModalSessionForInterval: (NSTimeInterval) seconds
{
	if ( _message != nil )
	{
		[_loadingTextField setStringValue: _message];
		_message = nil;
	}

	if ( _loadingPanelModalSession != 0 )
	{
		if ( [[NSApplication sharedApplication] runModalSession: _loadingPanelModalSession]
			 != NSModalResponseContinue )
			return NO;
	}

	//-runModalSession: returns at once when there is nothing to do, so without
	//this the caller's wait loop would spin a core doing nothing. Blocking in
	//the run loop instead lets the panel animate and the Cancel button respond.
	[[NSRunLoop currentRunLoop] runMode: NSModalPanelRunLoopMode
							 beforeDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];

	return YES;
}

- (IBAction) cancel:(id)sender
{
	@synchronized ( self )
	{
		_cancelPressed = YES;
	}

	[_loadingCancelButton setEnabled: NO];
}

@end

