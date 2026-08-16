//
//  NSURL-Extensions.m
//  DirectoryListingTest
//
//  Created by Doom on 11.08.19.
//
//  Copyright (C) 2019 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import "NSURL-Extensions.h"

#include <sys/attr.h>

NS_ASSUME_NONNULL_BEGIN

//-volumeSpaceUsed is not an NSURL resource key, so like -cachedPath it needs a
//key of its own in the cache dictionary.
static NSString * const kVolumeSpaceUsedCacheKey = @"DIXVolumeSpaceUsedKey";

NSMutableDictionary<NSURL*, NSURL*> * g_Firmlinks = nil;
NSString *firmlinkListFile = @"/usr/share/firmlinks";

void LoadFirmlinks()
{
    if ( g_Firmlinks != nil )
        return;
    
    g_Firmlinks = [[NSMutableDictionary<NSURL*, NSURL*> alloc] init];
    
    // read everything from file
    NSString* fileContents = [NSString stringWithContentsOfFile: firmlinkListFile
                                                       encoding: NSASCIIStringEncoding
                                                          error: nil];

    // separate by new line
    NSArray<NSString*>* allLines =
          [fileContents componentsSeparatedByCharactersInSet:
          [NSCharacterSet newlineCharacterSet]];

    for ( NSString * line in allLines )
    {
        NSArray<NSString*> *LinkFromTo = [line componentsSeparatedByCharactersInSet: [NSCharacterSet characterSetWithCharactersInString:@"\t"]];
        
        if ( [LinkFromTo count] >= 2)
        {
            NSString *firmlinkSrcPath = [LinkFromTo objectAtIndex:0];
            
            NSURL *firmlinkSrcURL = [NSURL fileURLWithPath:firmlinkSrcPath];
            
            if ( [firmlinkSrcURL stillExists])
                [g_Firmlinks setObject:firmlinkSrcURL forKey:firmlinkSrcURL];
        }
    }
}


@implementation NSURL(AccessExtensions)

#pragma mark ***** functions to access NSURL resource keys (! removed after each pass through the run loop !) *****

#pragma mark ----------------- file/folder attributes -----------------------

- (BOOL) isFile
{
    return [self getBoolValue: NSURLIsRegularFileKey];
}

- (BOOL) isDirectory
{
    return [self getBoolValue: NSURLIsDirectoryKey];
}

- (BOOL) isVolume
{
    // NSURLIsVolumeKey: True for the root directory of a volume (Read-only, value type boolean NSNumber)
    return [self getBoolValue: NSURLIsVolumeKey];
}

- (BOOL) isPackage
{
    return [self getBoolValue: NSURLIsPackageKey];
}

- (BOOL) isAliasOrSymbolicLink
{
    // NSURLIsAliasFileKey: true if the resource is a Finder alias file or a symlink, false otherwise
    return [self getBoolValue: NSURLIsAliasFileKey];
}

- (BOOL) isFirmlink
{
    LoadFirmlinks();
    
    return [g_Firmlinks objectForKey:self] != nil;
}

- (NSString*) name
{
    return [self getStringValue: NSURLNameKey];
}

- (NSString*) displayName
{
    return [self getStringValue: NSURLLocalizedNameKey];
}

- (NSString*) displayPath
{
    NSArray<NSString *> *pathComponents = [[NSFileManager defaultManager] componentsToDisplayForPath: [self path]];
    
    return [NSString pathWithComponents: pathComponents];
}

- (NSString*_Nullable) UTI // uniform type identifier
{
    return [self getStringValue: NSURLTypeIdentifierKey];
}

- (NSImage*_Nullable) icon
{
    return [[NSWorkspace sharedWorkspace] iconForFile:[self path]];
}

- (NSNumber*) logicalSize
{
    //NSURLTotalFileSizeKey: Total displayable size of the file in bytes (this may include space used by metadata), or nil if not available. (Read-only, value type NSNumber)
    NSNumber *fileSizeBytes = [self getNumberValue: NSURLTotalFileSizeKey];
    
    // fallback to NSURLFileSizeKey
    if ( fileSizeBytes == nil )
        fileSizeBytes = [self getNumberValue: NSURLFileSizeKey];
 
    return fileSizeBytes;
}

- (NSNumber*) physicalSize
{
    //NSURLTotalFileAllocatedSizeKey: Total allocated size of the file in bytes (this may include space used by metadata), or nil if not available. This can be less than the value returned by NSURLTotalFileSizeKey if the resource is compressed. (Read-only, value type NSNumber)
    NSNumber *fileSizeBytes = [self getNumberValue: NSURLTotalFileAllocatedSizeKey];
    
    // fallback to NSURLTotalFileSizeKey
    if ( fileSizeBytes == nil )
        fileSizeBytes = [self getNumberValue: NSURLTotalFileSizeKey];
    
    return fileSizeBytes;
}

- (NSDate*) creationDate
{
    return [self getDateValue: NSURLCreationDateKey];
}

- (NSDate*) modificationDate;
{
    return [self getDateValue: NSURLContentModificationDateKey];
}


- (BOOL) stillExists //works only for file URLs
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self path]];
}

- (BOOL) residesInDirectoryURL: (NSURL*) parentDir
{
    NSURL *myParentURL = [self URLByDeletingLastPathComponent];
    
    return [myParentURL isEqualToURL: parentDir];
}

- (BOOL) isEqualToURL: (NSURL*) url
{
    return [[self scheme] isEqualToString:[url scheme]]
        && [[self resourceSpecifier] isEqualToString:[url resourceSpecifier]];
}

#pragma mark ----------------- volume attributes -----------------------

- (BOOL) isLocalVolume
{
    // NSURLVolumeIsLocalKey: true if the volume is stored on a local device. (Read-only, value type boolean NSNumber)
    return [self getBoolValue: NSURLVolumeIsLocalKey];
}

- (NSNumber*_Nullable) volumeTotalCapacity
{
    // Total volume capacity in bytes (Read-only, value type NSNumber)
    return [self getNumberValue:NSURLVolumeTotalCapacityKey];
}

- (NSNumber*_Nullable) volumeAvailableCapacity
{
    // Total free space in bytes (Read-only, value type NSNumber)
    return [self getNumberValue:NSURLVolumeAvailableCapacityKey];
}

- (NSString*_Nonnull) volumeFormatName
{
    // The user-visible volume format (Read-only, value type NSString)
    return [self getStringValue:NSURLVolumeLocalizedFormatDescriptionKey];
}

// Returns NO where the file system does not implement ATTR_VOL_SPACEUSED —
// network volumes most of all — and the caller then has to fall back on the
// capacity-minus-free arithmetic.
static BOOL SpaceUsedAtPath( const char *path, unsigned long long *spaceUsed )
{
    if ( path == NULL )
        return NO;

    struct attrlist attrs;
    memset( &attrs, 0, sizeof(attrs) );
    attrs.bitmapcount = ATTR_BIT_MAP_COUNT;
    attrs.volattr = ATTR_VOL_INFO | ATTR_VOL_SPACEUSED;

    struct
    {
        uint32_t length;
        off_t spaceUsed;
    } __attribute__((aligned(4), packed)) result;

    if ( getattrlist( path, &attrs, &result, sizeof(result), 0 ) != 0 )
        return NO;

    *spaceUsed = (unsigned long long)result.spaceUsed;

    return YES;
}

- (NSNumber*_Nullable) volumeSpaceUsed
{
    // NSURLVolumeTotalCapacityKey and NSURLVolumeAvailableCapacityKey both answer
    // for the whole APFS container, so on a container holding several volumes
    // their difference is the same number for every one of them. ATTR_VOL_SPACEUSED
    // (10.13+) answers for one volume. Measured on a stock boot disk it separates
    // the 12.6 GB system volume from the 184.6 GB data volume, where
    // capacity-minus-free reports 211.9 GB for both.
    const char *path = [self fileSystemRepresentation];
    unsigned long long spaceUsed = 0;

    if ( !SpaceUsedAtPath( path, &spaceUsed ) )
        return nil;

    // The boot volume is a firmlinked pair — a read-only system volume mounted at
    // "/" and a writable data volume holding everything the user owns — which
    // macOS presents as one volume and Finder reports as one. Only the system half
    // is listed as a mounted volume, so without its partner it accounts for the
    // 12.6 GB of macOS and none of the 184.6 GB of the user's own files, which
    // would then look like they belonged to some other volume entirely.
    //
    // Identified by the mount point, and not by NSURLVolumeIsRootFileSystemKey:
    // firmlinks make the data volume part of the root file system too, so that key
    // answers YES for both halves and the data half would count itself twice.
    if ( path != NULL && strcmp( path, "/" ) == 0 )
    {
        unsigned long long dataSpaceUsed = 0;

        if ( SpaceUsedAtPath( "/System/Volumes/Data", &dataSpaceUsed ) )
            spaceUsed += dataSpaceUsed;
    }

    return [NSNumber numberWithUnsignedLongLong: spaceUsed];
}

#pragma mark ----------------- helper functions -----------------------

- (BOOL) getBoolValue: (NSString*) resourceName
{
    NSNumber *val = nil;
    [self getResourceValue: &val forKey: resourceName error: nil];
    
    return val == nil ? NO : [val boolValue];
}

- (NSString*_Nullable) getStringValue: (NSString*) resourceName
{
    NSString *val = nil;
    [self getResourceValue: &val forKey: resourceName error: nil];
    
    return val;
}

- (NSNumber*_Nullable) getNumberValue: (NSString*) resourceName
{
    NSNumber *val = nil;
    [self getResourceValue: &val forKey: resourceName error: nil];
    return val;
}

- (NSDate*_Nullable) getDateValue: (NSString*) resourceName
{
    NSDate *val = nil;
    [self getResourceValue: &val forKey: resourceName error: nil];
    return val;
}

#pragma mark ***** cached resource values (kept in memory as temporary resource keys *****

- (BOOL) cachedIsFile
{
    return [self getCachedBoolValue: NSURLIsRegularFileKey];
}

- (BOOL) cachedIsDirectory
{
    return [self getCachedBoolValue: NSURLIsDirectoryKey];
}

- (BOOL) cachedIsVolume
{
    // NSURLIsVolumeKey: True for the root directory of a volume (Read-only, value type boolean NSNumber)
    return [self getCachedBoolValue: NSURLIsVolumeKey];
}

- (BOOL) cachedIsPackage
{
    return [self getCachedBoolValue: NSURLIsPackageKey];
}

- (BOOL) cachedIsAliasOrSymbolicLink
{
    // NSURLIsAliasFileKey: true if the resource is a Finder alias file or a symlink, false otherwise
    return [self getCachedBoolValue: NSURLIsAliasFileKey];
}

- (NSString*) cachedName
{
    return [self getCachedStringValue: NSURLNameKey];
}

- (NSString*) cachedPath
{
    // URL does not provide the path as a resource value, so we cannot use the "getCachedStringValue" function
    
    static NSString *key = @"URLFilePathKey";

    NSMutableDictionary *cache = [self resourceValueCache];
    
    id cachedVal = [cache objectForKey:key];
    
    if ( cachedVal == nil )
    {
        // resource not cached, so load the resource from NSURL ...
        cachedVal = [self path];

        if ( cachedVal == nil )
            cachedVal = [NSNull null]; // mark resource as not present
        
        // ... and cache it for next time
        [cache setValue:cachedVal forKey:key];
    }
    
    return (cachedVal == (id)[NSNull null]) ? @"" : cachedVal;
}

- (NSString*) cachedDisplayName
{
    return [self getCachedStringValue: NSURLLocalizedNameKey];
}

- (NSString*_Nullable) cachedUTI // uniform type identifier
{
    return [self getCachedStringValue: NSURLTypeIdentifierKey];
}

- (NSNumber*) cachedLogicalSize
{
    //NSURLTotalFileSizeKey: Total displayable size of the file in bytes (this may include space used by metadata), or nil if not available. (Read-only, value type NSNumber)
    NSNumber *fileSizeBytes = [self getCachedNumberValue: NSURLTotalFileSizeKey];
    
    // fallback to NSURLFileSizeKey
    if ( fileSizeBytes == nil )
        fileSizeBytes = [self getCachedNumberValue: NSURLFileSizeKey];
    
    return fileSizeBytes;
}

- (NSNumber*) cachedPhysicalSize
{
    //NSURLTotalFileAllocatedSizeKey: Total allocated size of the file in bytes (this may include space used by metadata), or nil if not available. This can be less than the value returned by NSURLTotalFileSizeKey if the resource is compressed. (Read-only, value type NSNumber)
    NSNumber *fileSizeBytes = [self getCachedNumberValue: NSURLTotalFileAllocatedSizeKey];
    
    // fallback to NSURLTotalFileSizeKey
    if ( fileSizeBytes == nil )
        fileSizeBytes = [self getCachedNumberValue: NSURLTotalFileSizeKey];
    
    return fileSizeBytes;
}

- (NSDate*) cachedCreationDate
{
    return [self getCachedDateValue: NSURLCreationDateKey];
}

- (NSDate*) cachedModificationDate
{
    return [self getCachedDateValue: NSURLContentModificationDateKey];
}

- (BOOL) cachedIsLocalVolume
{
    return [self getCachedBoolValue: NSURLVolumeIsLocalKey];
}

- (NSNumber*_Nullable) cachedVolumeTotalCapacity
{
   return [self getCachedNumberValue: NSURLVolumeTotalCapacityKey];
}

- (NSNumber*_Nullable) cachedVolumeAvailableCapacity
{
   return [self getCachedNumberValue: NSURLVolumeAvailableCapacityKey];
}

- (NSString*_Nonnull) cachedVolumeFormatName
{
    return [self getCachedStringValue: NSURLVolumeLocalizedFormatDescriptionKey];
}

- (NSNumber*_Nullable) cachedVolumeSpaceUsed
{
    // not an NSURL resource key, so this cannot go through getCachedNumberValue:
    NSMutableDictionary *cache = [self resourceValueCache];

    id cachedVal = [cache objectForKey: kVolumeSpaceUsedCacheKey];

    if ( cachedVal == nil )
    {
        cachedVal = [self volumeSpaceUsed];

        if ( cachedVal == nil )
            cachedVal = [NSNull null]; // mark resource as not present

        [cache setValue: cachedVal forKey: kVolumeSpaceUsedCacheKey];
    }

    return (cachedVal == (id)[NSNull null]) ? nil : cachedVal;
}

- (void) cacheResourcesInArray: (NSArray<NSURLResourceKey>*) resourceKeys
{
    NSMutableDictionary *cache = [self resourceValueCache];

    for (NSString *key in resourceKeys)
    {
        id val = nil;
        [self getResourceValue: &val forKey: key error: nil];

        if ( val == nil )
            val = (id)[NSNull null]; // mark as "resource not present"

        [cache setValue: val forKey: key];
    }
}

- (void) recacheResourcesInArray: (NSArray<NSURLResourceKey>*) resourceKeys
{
    NSMutableDictionary *cache = [self resourceValueCache];

    for (NSURLResourceKey key in resourceKeys)
    {
        // NSURL keeps a cache of its own behind -getResourceValue:forKey:error:,
        // so dropping this dictionary's copy alone would just read that one back.
        // -removeAllCachedResourceValues would do it too, but it also discards
        // temporary resource values — and the cache dictionary above is one.
        [self removeCachedResourceValueForKey: key];

        id val = nil;
        [self getResourceValue: &val forKey: key error: nil];

        if ( val == nil )
            val = (id)[NSNull null]; // mark as "resource not present"

        [cache setValue: val forKey: key];
    }
}

- (void) invalidateCachedVolumeSpaceUsed
{
    [[self resourceValueCache] removeObjectForKey: kVolumeSpaceUsedCacheKey];
}

#pragma mark ----------------- helper functions -----------------------

- (NSMutableDictionary*) resourceValueCache
{
    // we keep the cached values in a seperate NSMutableDictionary object, as keeping them individually as "temporary resource values" (see NSURL docs) takes about 50% more memory.
    // The NSMutableDictionary is then kept as the single URL's temporary resource value.
    
    static NSString* cacheKey = @"com.derlien.URLResourceValueCacheKey";
    
    NSMutableDictionary* cache = nil;
    
    // first, try to get the cached resource value
    // (return value 'NO' does NOT mean resource is not present, but that an error occured)
    if ( ![self getResourceValue: &cache forKey: cacheKey error: nil] )
        return nil;
    
    if ( cache == nil )
    {
        cache = [[NSMutableDictionary alloc] init];
        [self setTemporaryResourceValue:cache forKey:cacheKey];
    }

    return cache;
}

- (BOOL)getCachedResourceValue:(out id _Nullable * _Nonnull)value forKey:(NSURLResourceKey)key error:(out NSError ** _Nullable)error
{
    NSMutableDictionary *cache = [self resourceValueCache];
    
    id cachedVal = [cache objectForKey:key];
    
    if ( cachedVal == nil )
    {
        // resource not cached, so load the resource from NSURL ...
        // (return value "NO" does not mean resource is not present, but that an error occured)
        if ( ![self getResourceValue: &cachedVal forKey: key error: error] )
            return NO;

        if ( cachedVal == nil )
            cachedVal = [NSNull null]; // mark resource as not present
        
        // cache it for next time
        [cache setValue:cachedVal forKey:key];
    }
    
    *value = (cachedVal == [NSNull null]) ? nil : cachedVal;
    
    return YES;
}

- (BOOL) getCachedBoolValue: (NSString*) resourceName
{
    NSNumber *val = nil;

    [self getCachedResourceValue: &val forKey: resourceName error: nil];
    
    return (val == nil) ? NO : [val boolValue];
}

- (NSString*_Nullable) getCachedStringValue: (NSString*) resourceName
{
    NSString *val = nil;
    
    [self getCachedResourceValue: &val forKey: resourceName error: nil];
    
    return val;
}

- (NSNumber*_Nullable) getCachedNumberValue: (NSString*) resourceName
{
    NSNumber *val = nil;
    
    [self getCachedResourceValue: &val forKey: resourceName error: nil];

    return val;
}

- (NSDate*_Nullable) getCachedDateValue: (NSString*) resourceName
{
    NSDate *val = nil;
    
    [self getCachedResourceValue: &val forKey: resourceName error: nil];

    return val;
}


@end

NS_ASSUME_NONNULL_END
