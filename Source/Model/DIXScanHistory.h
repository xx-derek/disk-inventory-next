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

#pragma mark --------what the settings screen asks-----------------

//Where the snapshots are kept. The folder behind ScanHistoryLocationBookmark
//when there is one and it still resolves, and a folder inside Application
//Support otherwise.
- (NSURL*) storageDirectory;

//The default place, whatever the preference says.
- (NSURL*) defaultStorageDirectory;

//Moves what is stored to "url" and remembers it. Copies, verifies, then removes
//the originals; on any failure nothing is moved, the old location is kept, and
//the error comes back - abandoning someone's history in a folder they have just
//stopped pointing at would be the worst of the three outcomes.
- (BOOL) moveStorageToDirectory: (NSURL*) url error: (NSError**) error;

//Back to the default place, moving the files with it.
- (BOOL) resetStorageLocationWithError: (NSError**) error;

//How much is stored, for the "Stored now" row.
- (NSUInteger) snapshotCount;
- (unsigned long long) storedByteCount;

//Drops snapshots older than the ScanHistoryRetentionDays window. Run at launch.
//A retention of 0 deletes everything and stops recording; -1 keeps everything.
- (void) pruneToRetentionWindow;

//NO when the retention window is Off, in which case nothing is recorded, the
//change window is not offered, and the summary strip shows no delta.
- (BOOL) isRecording;

@end
