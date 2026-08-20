//
//  DIXRecentScans.h
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

#import <Foundation/Foundation.h>

//What a folder came to last time it was scanned.
@interface DIXRecentScan : NSObject

- (NSURL*) url;
- (NSString*) name;                 //the folder's own name
- (NSString*) abbreviatedPath;      //with the home folder as a tilde
- (unsigned long long) size;
- (NSDate*) scannedAt;

//"8 seconds ago", "2 minutes ago". One wording for when something was scanned,
//used by the sidebar rows and by the summary strip above the map, so the two
//cannot say different things about the same scan - which they did: the strip
//floored anything under a minute to "now" and then sat on it, while the row
//beside it counted the minutes up.
+ (NSString*) relativeTimeStringForDate: (NSDate*) date;

@end

//The folders this application has scanned, most recent first, one entry each.
//
//This is deliberately *not* the scan history the settings screen describes.
//That keeps a record per scan so two of them can be compared - it is what the
//change view is built on, and it belongs with that. This keeps one line per
//folder, overwritten each time, and exists so the sidebar can offer somewhere
//you have already been.
//
//Cocoa's own recent-documents list would almost do, and the application notes
//folders there as well so the Open Recent menu works. It cannot serve here for
//one reason: it has no way to remove a single entry, only to clear the lot, and
//these rows have a button to forget one.
@interface DIXRecentScans : NSObject

+ (instancetype) sharedList;

//Most recent first. Entries whose folder has gone are left out.
- (NSArray<DIXRecentScan*>*) scans;

//What the last scan of this folder came to, or nil for one never scanned.
- (DIXRecentScan*) scanForURL: (NSURL*) url;

//Records a completed scan, moving the folder to the front if it is already
//known. Posts DIXRecentScansChangedNotification.
- (void) recordScanOfURL: (NSURL*) url size: (unsigned long long) size;

- (void) removeScanForURL: (NSURL*) url;

@end

//the list gained, lost or reordered an entry; userInfo is nil
extern NSString *DIXRecentScansChangedNotification;
