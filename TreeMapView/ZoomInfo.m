//
//  ZoomInfo.m
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

#import "ZoomInfo.h"

//Short enough to feel like a transition rather than an animation to sit through,
//long enough to show which cell the new view came out of.
static const unsigned TMVZoomStepCount = 12;
static const NSTimeInterval TMVZoomStepInterval = 1.0 / 60.0;

@interface ZoomInfo(Private)

- (void) calculateNewRect;
- (void) onTimer: (NSTimer*) timer;

@end

@implementation ZoomInfo

- (id) initWithImage: (NSImage*) image delegate: (id) delegate selector: (SEL) selector
{
	self = [super init];
	if ( self == nil )
		return nil;

	_image = image;
	_delegate = delegate;
	_delegateSelector = selector;
	_rect = NSZeroRect;
	_zoomStepsLeft = 0;
	_timer = nil;

	return self;
}

- (void) dealloc
{
	[_timer invalidate];

}

- (void) calculateZoomFromRect: (NSRect) fromRect toRect: (NSRect) toRect
{
	_rect = fromRect;
	_zoomStepsLeft = TMVZoomStepCount;

	//each edge travels independently, so the image can stretch as well as move
	_leftStep   = ( NSMinX(toRect) - NSMinX(fromRect) ) / TMVZoomStepCount;
	_topStep    = ( NSMinY(toRect) - NSMinY(fromRect) ) / TMVZoomStepCount;
	_rightStep  = ( NSMaxX(toRect) - NSMaxX(fromRect) ) / TMVZoomStepCount;
	_bottomStep = ( NSMaxY(toRect) - NSMaxY(fromRect) ) / TMVZoomStepCount;

	[_timer invalidate];

	_timer = [NSTimer timerWithTimeInterval: TMVZoomStepInterval
									  target: self
									selector: @selector(onTimer:)
									userInfo: nil
									 repeats: YES];

	//scheduled in the common modes, so the zoom keeps running while a menu is
	//tracking or the window is being resized
	[[NSRunLoop currentRunLoop] addTimer: _timer forMode: NSRunLoopCommonModes];
}

- (void) calculateNewRect
{
	const CGFloat left   = NSMinX(_rect) + _leftStep;
	const CGFloat top    = NSMinY(_rect) + _topStep;
	const CGFloat right  = NSMaxX(_rect) + _rightStep;
	const CGFloat bottom = NSMaxY(_rect) + _bottomStep;

	_rect = NSMakeRect( left, top, right - left, bottom - top );
}

- (void) onTimer: (NSTimer*) timer
{
	if ( _zoomStepsLeft > 0 )
	{
		[self calculateNewRect];
		_zoomStepsLeft--;
	}

	if ( _zoomStepsLeft == 0 )
	{
		[_timer invalidate];
		_timer = nil;
	}

	//the view redraws, and tears us down once -hasFinished says so
	if ( _delegate != nil && [_delegate respondsToSelector: _delegateSelector] )
	{
		//called through the IMP rather than -performSelector:, which ARC warns
		//about because it cannot know the selector's memory semantics
		void (*notify)( id, SEL, id ) = (void (*)( id, SEL, id ))
			[_delegate methodForSelector: _delegateSelector];

		notify( _delegate, _delegateSelector, self );
	}
}

//An NSTimer retains its target, so a running zoom keeps the receiver alive.
//Nothing else will break that cycle if the view goes away mid-animation.
- (void) cancel
{
	[_timer invalidate];
	_timer = nil;
	_zoomStepsLeft = 0;
}

- (BOOL) hasFinished
{
	return _zoomStepsLeft == 0;
}

- (NSImage*) image
{
	return _image;
}

- (NSRect) imageRect
{
	return _rect;
}

- (void) drawImage
{
	if ( _image == nil || NSIsEmptyRect(_rect) )
		return;

	[_image drawInRect: _rect
			  fromRect: NSZeroRect
			 operation: NSCompositingOperationSourceOver
			  fraction: 1.0
		respectFlipped: YES
				 hints: nil];
}

@end
