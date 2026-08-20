//
//  DIXScanHistory.h
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

@class FSItem;

//One thing that is a different size than it was.
@interface DIXScanChange : NSObject

- (NSString*) path;         //absolute
- (NSString*) name;         //its last component
- (NSString*) folderPath;   //what holds it, with the home folder as a tilde
- (long long) delta;        //signed: positive is growth

@end

//What a scan of one folder found, kept so the next scan of it can be compared.
//
//This is not DIXRecentScans, which keeps one total per folder for the sidebar
//and the picker. This keeps the sizes *inside* a scan, which is the only way to
//answer "what changed" rather than "how much changed" - and is why it writes
//files rather than user defaults: a full volume contributes thousands of rows.
//
//One snapshot per folder, overwritten by the next scan of it. Two are never
//needed at once: the comparison is always against the last one.
@interface DIXScanHistory : NSObject

+ (DIXScanHistory*) sharedHistory;

//Walks the finished tree and writes what it holds. Cheap next to the scan that
//produced it - the tree is already in memory - and bounded: see the note on
//kSnapshotFloor in the implementation.
- (void) recordSnapshotForItem: (FSItem*) rootItem;

//When the last snapshot of this folder was taken, or nil if there is none.
- (NSDate*) snapshotDateForURL: (NSURL*) url;

//What has changed since. Biggest first, and empty when there is no snapshot to
//compare against - a first scan has nothing to say.
- (NSArray<DIXScanChange*>*) changesForItem: (FSItem*) rootItem;

//Every stored snapshot, for the settings screen's "Delete history now".
- (void) deleteAllSnapshots;

@end
