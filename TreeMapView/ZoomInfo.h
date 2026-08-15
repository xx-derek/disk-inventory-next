//
//  ZoomInfo.h
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

//Drives the zoom effect. Laying a treemap out again from a different root
//changes every cell at once, so instead of animating cells the view takes a
//snapshot of what it had and slides that image between two rects while the new
//layout is prepared behind it.

@interface ZoomInfo : NSObject
{
	NSImage *_image;
	NSRect _rect;
	unsigned _zoomStepsLeft;
	CGFloat _leftStep;
	CGFloat _topStep;
	CGFloat _rightStep;
	CGFloat _bottomStep;
	__weak id _delegate;
	SEL _delegateSelector;
	NSTimer *_timer;
}

//"selector" is sent to "delegate" after each step, to trigger a redisplay
- (id) initWithImage: (NSImage*) image delegate: (id) delegate selector: (SEL) selector;

//starts the animation; the image travels from one rect to the other
- (void) calculateZoomFromRect: (NSRect) fromRect toRect: (NSRect) toRect;

//stops the animation and breaks the timer's hold on the receiver
- (void) cancel;

- (BOOL) hasFinished;

- (NSImage*) image;
- (NSRect) imageRect;

//draws the snapshot at its current position
- (void) drawImage;

@end
