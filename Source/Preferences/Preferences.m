/*
 *  Preferences.m
 *  Disk Inventory Next
 *
 *  Created by Tjark Derlien on 24.11.04.
 *  Copyright 2004 Tjark Derlien. All rights reserved.
 *
 */

#include "Preferences.h"

//keys for preference values
NSString *AppRegistrationsKey			= @"Registrations";

NSString *ShowPackageContents			= @"ShowPackageContents";
NSString *ShowFreeSpace					= @"ShowFreeSpace";
NSString *ShowOtherSpace				= @"ShowOtherSpace";
NSString *IgnoreCreatorCode				= @"IgnoreCreatorCode";
NSString *ShowPhysicalFileSize			= @"ShowPhysicalFileSize"; //logical size otherwise (like the Finder)
NSString *UseSmallFontInKindStatistic	= @"UseSmallFontInKindStatisticView";
NSString *UseSmallFontInFilesView		= @"UseSmallFontInFilesView";
NSString *UseSmallFontInSelectionList	= @"UseSmallFontInSelectionList";
NSString *SplitWindowHorizontally		= @"SplitWindowHorizontally";
NSString *AnimatedZooming				= @"AnimatedZooming";
NSString *LabelLargeCells				= @"LabelLargeCells";
NSString *ClassicCushions				= @"ClassicCushions";
NSString *EnableLogging					= @"EnableLogging";
NSString *ScanConcurrency				= @"ScanConcurrency";

//The walk is I/O bound, and measurement flattens out well before eight: over
///System/Library, 1.52x at two, 1.96x at four, 2.23x at eight and nothing after.
//So the ceiling is where the gain stops, not where the hardware does.
const NSInteger ScanConcurrencyMinimum = 1;
const NSInteger ScanConcurrencyMaximum = 8;
NSString *DontShowDonationMessage        = @"DontShowDonationMessage";
NSString *DontShowPrivacyWarningMessage        = @"DontShowPrivacyWarningMessage";
NSString *ShareKindColors				= @"ShareKindColors";

NSString *OpenWith                      = @"OpenWith";
NSString *ScanHistoryRetentionDays      = @"ScanHistoryRetentionDays";
NSString *ScanHistoryLocationBookmark   = @"ScanHistoryLocationBookmark";
NSString *ShowPartialResults            = @"ShowPartialResults";
NSString *ShowSkippedFoldersBanner      = @"ShowSkippedFoldersBanner";

const NSInteger DIXHistoryOff     =  0;
const NSInteger DIXHistoryForever = -1;


#pragma mark ----------------- NSUserDefaults(VersionDepedantValues) -------------------

@implementation NSUserDefaults(VersionDepedantValues)

- (NSString*) mainBundleVersion
{
    static NSString * _bundleVersion = nil;
    if ( _bundleVersion == nil )
    {
        NSBundle *bundle = [NSBundle mainBundle];
        
        NSArray *keys = [NSArray arrayWithObjects: @"CFBundleShortVersionString", @"CFBundleGetInfoString", nil];
        NSDictionary *dict = [bundle infoDictionary];
                         
         for ( int i = 0;
              i < [keys count]
             && (_bundleVersion == nil || [_bundleVersion length] == 0);
             i++)
         {
             _bundleVersion = [dict objectForKey:[keys objectAtIndex:i]];
         }
    }
    return _bundleVersion == nil ? @"" : _bundleVersion;
}

- (NSString*) versionDependantKeyForKey: (NSString*) key
{
    NSString *mainBundleVer = [self mainBundleVersion];
    
    return [mainBundleVer length] > 0
            ? [key stringByAppendingFormat:@" v%@", mainBundleVer]
            : key;
}

- (bool) boolForVersionDependantKey: (NSString*) key
{
    return [self boolForKey:[self versionDependantKeyForKey:key]];
}

- (void) setBool: (BOOL) val forVersionDependantKey: (NSString*) key
{
    [self setBool: val forKey:[self versionDependantKeyForKey:key]];
}

@end

#pragma mark ----------------- NSMutableDictionary(PreferencesValues) -------------------

@interface NSMutableDictionary(DocumentPreferences_Private)
- (void) copyValuesFromSharedDefaults;
@end


@implementation NSMutableDictionary(PreferencesValues)

- (id) initWithDefaults
{
	self = [self init];
	
	[self copyValuesFromSharedDefaults];
	
	return self;
}

- (BOOL) showPackageContents
{
	return [[self objectForKey: ShowPackageContents] boolValue];
}

- (void) setShowPackageContents: (BOOL) value;
{
	[self setObject: [NSNumber numberWithBool: value] forKey: ShowPackageContents];
}

- (BOOL) showFreeSpace;
{
	return [[self objectForKey: ShowFreeSpace] boolValue];
}

- (void) setShowFreeSpace: (BOOL) value;
{
	[self setObject: [NSNumber numberWithBool: value] forKey: ShowFreeSpace];
}

- (BOOL) showOtherSpace;
{
	return [[self objectForKey: ShowOtherSpace] boolValue];
}

- (void) setShowOtherSpace: (BOOL) value;
{
	[self setObject: [NSNumber numberWithBool: value] forKey: ShowOtherSpace];
}

- (BOOL) ignoreCreatorCode;
{
	return [[self objectForKey: IgnoreCreatorCode] boolValue];
}

- (void) setIgnoreCreatorCode: (BOOL) value
{
	[self setObject: [NSNumber numberWithBool: value] forKey: IgnoreCreatorCode];
}

- (BOOL) showPhysicalFileSize
{
	return [[self objectForKey: ShowPhysicalFileSize] boolValue];
}

- (void) setShowPhysicalFileSize: (BOOL) value
{
	[self setObject: [NSNumber numberWithBool: value] forKey: ShowPhysicalFileSize];
}

@end

@implementation NSMutableDictionary(DocumentPreferences_Private)

- (void) copyValuesFromSharedDefaults
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
#define COPYVALUEBOOL( name ) \
	[self setObject: [NSNumber numberWithBool: [defaults boolForKey: name]] forKey: name]
	
	COPYVALUEBOOL( ShowPackageContents );
	COPYVALUEBOOL( ShowFreeSpace );
	COPYVALUEBOOL( ShowOtherSpace );
	COPYVALUEBOOL( IgnoreCreatorCode );
	COPYVALUEBOOL( ShowPhysicalFileSize );
	
#undef COPYVALUEBOOL
}

@end

