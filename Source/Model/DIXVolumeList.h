//
//  DIXVolumeList.h
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

//One mounted volume, read once when the list is built. A value object rather
//than a live wrapper around its NSURL: two surfaces show these at the same time
//and both need them to change together, which they only do if the list decides
//when a re-read happens.
@interface DIXVolume : NSObject

- (NSURL*) url;
- (NSString*) name;
- (NSImage*) icon;
- (NSString*) formatDescription;    //"APFS", "Mac OS Extended" - nil if unknown

//Both zero when the volume cannot say. A network share can mount without
//reporting a size, so nothing may assume these are meaningful - ask
//-knowsItsSize first, and draw the row without a bar when it answers NO.
- (unsigned long long) totalCapacity;
- (unsigned long long) availableCapacity;
- (BOOL) knowsItsSize;

//How full, 0 to 1. Zero when the size is unknown, which is the same thing a
//brand new empty volume would report - hence -knowsItsSize being separate.
- (double) usedFraction;

@end

//Posted when volumes are mounted, unmounted or renamed, and after -refreshSizes.
//No userInfo: the list is short and an observer that redraws it wholesale is
//simpler than one working out which row moved.
extern NSString *DIXVolumeListChangedNotification;

//The mounted volumes, in one place.
//
//This is the retired Drives panel's enumeration, lifted out of it because the
//sidebar and the volume picker both need the same list and neither should own
//it. The workspace notifications it watches are process-wide, so it is a
//singleton: two instances would mean two sets of observers rebuilding two arrays
//that always agree.
@interface DIXVolumeList : NSObject
{
	NSArray<DIXVolume*> *_volumes;
}

+ (DIXVolumeList*) sharedList;

- (NSArray<DIXVolume*>*) volumes;

//Re-reads free space, which is the only figure that moves without a mount or an
//unmount to announce it. Callers drive this from a timer while they are on
//screen and stop when they are not - free space that is a few seconds stale is
//not worth waking the machine for.
- (void) refreshSizes;

@end
