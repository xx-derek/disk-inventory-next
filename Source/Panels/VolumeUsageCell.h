//
//  VolumeUsageCell.h
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

//The capacity bar in the drives panel's "usagePercent" column.
//
//This is a cell rather than an NSProgressIndicator parked in the table view as a
//subview, which is what it replaces: a subview is not clipped to its row and is
//not repositioned when rows scroll or the volume list changes, so stale bars
//were left drawn over unrelated rows. A cell draws only while its own row draws.
//
//Every bar is the same length whatever the volume's size, so the column reads as
//one scale and the fills can be compared down it at a glance. The bar length used
//to encode the volume's capacity relative to the largest mounted one, which made
//two bars of different lengths mean two different things and left a small volume
//with almost no bar to read. Capacity is spelled out in words in the column
//beside this one, so nothing is lost by not also drawing it.
//
//The fill has two segments because an APFS container's space is shared. The
//volume's own bytes are drawn in the accent colour and the rest of the
//container's usage — its sibling volumes — in a muted grey behind it. The two
//together come to the same total the bar always showed, so a volume that has its
//container to itself looks exactly as it did, while two volumes sharing one
//container are no longer drawn identically.
@interface VolumeUsageCell : NSCell
{
    double _usedFraction;
    double _sharedUsedFraction;
    BOOL _hasSizeInfo;
}

//0..1, the portion of the capacity holding this volume's own bytes. Values
//outside that range are clamped, which also catches the NaN a zero-capacity
//volume would otherwise divide to.
@property (nonatomic) double usedFraction;

//0..1, the portion held by other volumes in the same container. Zero whenever
//the volume does not share one, or where the file system cannot say.
@property (nonatomic) double sharedUsedFraction;

//NO for a volume that does not report sizes; the cell then draws nothing.
@property (nonatomic) BOOL hasSizeInfo;

@end
