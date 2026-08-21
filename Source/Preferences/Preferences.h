/*
 *  Preferences.h
 *  Disk Inventory Next
 *
 *  Created by Tjark Derlien on 24.11.04.
 *  Copyright 2004 Tjark Derlien. All rights reserved.
 *
 */

#import <Cocoa/Cocoa.h>

//keys for preference values
//top-level Info.plist key holding the factory defaults and the preference page list
extern NSString *AppRegistrationsKey;

extern NSString *ShowPackageContents;
extern NSString *ShowFreeSpace;
extern NSString *ShowOtherSpace;
extern NSString *IgnoreCreatorCode;
extern NSString *ShowPhysicalFileSize; //logical size otherwise (like the Finder)
extern NSString *UseSmallFontInKindStatistic;
extern NSString *UseSmallFontInFilesView;
extern NSString *UseSmallFontInSelectionList;
extern NSString *SplitWindowHorizontally;
extern NSString *AnimatedZooming;
extern NSString *EnableLogging;

//How many subdirectories of the folder being scanned are walked at once. 1 walks
//everything in order, which is what the scan did before this was settable.
extern NSString *ScanConcurrency;
extern const NSInteger ScanConcurrencyMinimum;
extern const NSInteger ScanConcurrencyMaximum;
extern NSString *DontShowDonationMessage;
extern NSString *DontShowPrivacyWarningMessage;
extern NSString *ShareKindColors;
extern NSString *LabelLargeCells;

//Cell shading: the nested-pillow cushion the application has always drawn, or
//the design's flat cell with a bevelled edge. Off by default - the bevel is the
//design's, and the separator now drawn between every pair of cells does the job
//the cushion's depth cue used to do on its own.
extern NSString *ClassicCushions;

#pragma mark --------what the redesign added-----------------

//What the application shows when it is started with no document.
typedef NS_ENUM( NSInteger, DIXOpenWithChoice )
{
	DIXOpenWithLastVolume = 0,
	DIXOpenWithPicker     = 1,
	DIXOpenWithNothing    = 2,
};

extern NSString *OpenWith;

//Reopen the last scan rather than rescanning it. Only meaningful when OpenWith
//is DIXOpenWithLastVolume.
extern NSString *ReopenLastScan;

//How long a scan snapshot is kept, in days. 0 keeps none - which also turns the
//change view and the summary strip's delta off, since both are answers this
//would have no data for - and -1 keeps them forever.
extern NSString *ScanHistoryRetentionDays;

extern const NSInteger DIXHistoryOff;
extern const NSInteger DIXHistoryForever;

//Where the snapshots live. A bookmark rather than a path, so the folder can be
//renamed or moved and still be found - but not a *security-scoped* one, which
//is what the handoff suggests: this application is not sandboxed, and asking
//for security scope without the entitlement fails to make a bookmark at all.
//An absent or unresolvable value means the default place in Application Support.
extern NSString *ScanHistoryLocationBookmark;

//Offer "Show partial results" on the scanning screen.
extern NSString *ShowPartialResults;

//Show a banner on a scan that could not read everything it was asked to.
extern NSString *ShowSkippedFoldersBanner;

@interface NSUserDefaults(VersionDepedantValues)

- (bool) boolForVersionDependantKey: (NSString*) key;
- (void) setBool: (BOOL) val forVersionDependantKey: (NSString*) key;

@end

@interface NSMutableDictionary(DocumentPreferences)

- (id) initWithDefaults;

- (BOOL) showPackageContents;
- (void) setShowPackageContents: (BOOL) value;

- (BOOL) showFreeSpace;
- (void) setShowFreeSpace: (BOOL) value;

- (BOOL) showOtherSpace;
- (void) setShowOtherSpace: (BOOL) value;

- (BOOL) ignoreCreatorCode;
- (void) setIgnoreCreatorCode: (BOOL) value;

- (BOOL) showPhysicalFileSize;
- (void) setShowPhysicalFileSize: (BOOL) value;

@end
