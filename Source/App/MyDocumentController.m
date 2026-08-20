//
//  MyDocumentController.m
//  Disk Accountant
//
//  Created by Tjark Derlien on Wed Oct 08 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "MyDocumentController.h"

NSString *DIXRecentDocumentsChangedNotification = @"DIXRecentDocumentsChanged";
#import "DonationPanelController.h"
#import "DIXScanPickerController.h"
#import "Preferences.h"
#import "PrefsPanelController.h"
#import "FileSystemDoc.h"
#import "AppController.h"

//global variable which enables/disables logging
BOOL g_EnableLogging;

//============ implementation MyDocumentController ==========================================================

@implementation MyDocumentController

- (NSInteger) runModalOpenPanel: (NSOpenPanel*) openPanel forTypes: (NSArray*) extensions
{
    //we want the user to choose a directory (including packages)
    [openPanel setCanChooseDirectories: YES];
    [openPanel setCanChooseFiles: NO];
    [openPanel setTreatsFilePackagesAsDirectories: YES];

    return [openPanel runModal];
}

- (void) openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if ( returnCode == NSModalResponseOK )
	{
		//open selected folders
		for ( NSURL *fileURL in [sheet URLs] )
		{
			//defer it till the next loop cycle to let the sheet closes itself first
			[[NSRunLoop currentRunLoop] performSelector:@selector(openDocumentWithContentsOfFile:)
												 target: self
                                               argument: [fileURL path]
												  order: 1
												  modes: [NSArray arrayWithObject: NSDefaultRunLoopMode]];
		}
	}
}

- (void) openDocumentWithContentsOfFile: (NSString*) fileName
{
	//-openDocumentWithContentsOfFile:display: and -shouldCreateUI were both
	//deprecated in 10.4; the URL form reports failure through the completion
	//handler rather than returning a document.
	[self openDocumentWithContentsOfURL: [NSURL fileURLWithPath: fileName]
								display: YES
					  completionHandler: ^( NSDocument *document, BOOL alreadyOpen, NSError *error )
	{
		if ( document == nil )
		{
			if ( error != nil )
				LOG( @"could not open '%@': %@", fileName, [error localizedDescription] );
			return;
		}

		//Noted by hand. -application:openFile: has said "called if file from
		//recent list is selected" since this app was written, but nothing ever
		//put anything in that list: -recentDocumentURLs came back empty, so
		//Open Recent was always empty too. The sidebar lists these below the
		//volumes, so now it matters twice.
		[self noteNewRecentDocumentURL: [NSURL fileURLWithPath: fileName]];

		[[NSNotificationCenter defaultCenter]
			postNotificationName: DIXRecentDocumentsChangedNotification object: self];
	}];
}

- (BOOL) applicationShouldOpenUntitledFile: (NSApplication*) sender
{
    //we don't want any untitled document as we need an existing folder
    return NO;
}

- (id)makeDocumentWithContentsOfFile:(NSString *)fileName ofType:(NSString *)docType
{
	//check whether "fileName" is a folder
	NSDictionary *attribs = [[NSFileManager defaultManager] fileAttributesAtPath: fileName traverseLink: NO];
    if ( attribs != nil )
	{
		NSString *type = [attribs fileType];
		if ( type != nil && [type isEqualToString: NSFileTypeDirectory] )
			return [super makeDocumentWithContentsOfFile:fileName ofType: @"Folder"];
	}
	
	return nil;
}

//"Open..." menu handler
- (IBAction)openDocument:(id)sender
{
	//we implement this method by ourself, so we can avoid that stupid message "document couldn't be opened"
	//in the case the user canceled the opening
	NSArray<NSURL *> *fileNames = [self URLsFromRunningOpenPanel];
	
	if ( fileNames == nil )
		return; //cancel pressed in open panel
	
	for ( NSURL *dir in fileNames )
	{
		[self openDocumentWithContentsOfFile: [dir path]];
	}
}

+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    // prevent any window, which was open when quitting the app last time, to be re-opened now at the next lauch
    // (see https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/DocBasedAppProgrammingGuideForOSX/StandardBehaviors/StandardBehaviors.html#//apple_ref/doc/uid/TP40011179-CH5-SW4
    // Document-Based App Programming Guide for Mac/Core App Behaviors/Windows Are Restored Automatically)
    completionHandler(nil, nil);
}

//Application's delegate; called if file from recent list is selected
- (BOOL) application: (NSApplication*) theApp openFile: (NSString*) fileName
{
	//if "fileName" doesn't exist or isn't a folder, return NO so that it is removed from the recent list
	NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath: fileName error:nil];
    if ( attribs == nil || ![[attribs fileType] isEqualToString: NSFileTypeDirectory] )
		return NO;

	[self openDocumentWithContentsOfFile: fileName];
	
	//return TRUE to avoid nasty message if user canceled loading
	return TRUE;
}

- (NSString *)typeFromFileExtension:(NSString *)fileExtensionOrHFSFileType
{
	OSType type = NSHFSTypeCodeFromFileType(fileExtensionOrHFSFileType);
	if ( type == 0 )
		return @"Folder";
	else	
		return [super typeFromFileExtension: fileExtensionOrHFSFileType];
}

- (IBAction) showPreferencesPanel: (id) sender
{
	[[PrefsPanelController sharedPreferenceController] showPreferencesPanel: self];
}

//Kept because the Help menu's "Disk Inventory X Website" item is wired to it in
//the main menu nib. The donation panel has its own, clearly labelled button.
- (IBAction) gotoHomepage: (id) sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"http://www.derlien.com"]];
}


//AppKit has no public "find the item with this action" that descends into
//submenus, and the Preferences item is inside the application menu.
static NSMenuItem* FindMenuItemWithAction( NSMenu *menu, SEL action )
{
	for ( NSMenuItem *item in [menu itemArray] )
	{
		if ( [item action] == action )
			return item;

		if ( [item hasSubmenu] )
		{
			NSMenuItem *found = FindMenuItemWithAction( [item submenu], action );
			if ( found != nil )
				return found;
		}
	}

	return nil;
}

#pragma mark --------app notifications-----------------

- (void) applicationWillFinishLaunching: (NSNotification*) notification
{
    //verify that our custom DocumentController is in use 
    NSAssert( [[NSDocumentController sharedDocumentController] isKindOfClass: [MyDocumentController class]], @"the shared DocumentController is not our custom class!" );
    
	
	g_EnableLogging = [[NSUserDefaults standardUserDefaults] boolForKey: EnableLogging];
    
	[self _renameSettingsMenuItem];

	//Shown before -applicationDidFinishLaunching:, so it is up before the first
	//document can be loaded from a drag or a Recent Item - which would otherwise
	//open a window behind it.
	[[DIXScanPickerController sharedController] showPicker];
}

//macOS 13 renamed Preferences to Settings. The item lives in the main menu nib,
//four localized copies of it, so it is retitled here rather than by editing
//them — and only on the systems where the new wording is the right one.
- (void) _renameSettingsMenuItem
{
	if ( @available( macOS 13.0, * ) )
	{
		NSMenuItem *item = FindMenuItemWithAction( [NSApp mainMenu],
												   @selector(showPreferencesPanel:) );

		if ( item != nil )
			[item setTitle: NSLocalizedStringFromTable( @"Settings…", @"Preferences",
														@"application menu item" )];
	}
}

- (void) applicationDidFinishLaunching:(NSNotification *)notification
{
	[[DonationPanelController sharedController] showPanelIfWanted];
	
//	DIXFinderCMInstaller *installer = [DIXFinderCMInstaller installer];
//	if ( ![installer isInstalled] )
//		[installer installToDomain: kUserDomain];
}

#pragma mark -----------------NSMenu delegates-----------------------

- (void) menuNeedsUpdate: (NSMenu*) zoomStackMenu
{
	NSAssert( _zoomStackMenu == zoomStackMenu, @"asked to update a menu that is not the zoom stack" );
	
	FileSystemDoc *doc = [self currentDocument];
	NSArray *zoomStack = [doc zoomStack];
	
	//thanks to ObjC, [zoomStack count] will evaluate to 0 if there is no current doc
	unsigned i;
	for ( i = 0; i < [zoomStack count]; i++ )
	{
		FSItem *fsItem = nil;
		if ( i == 0 )
			fsItem = [doc rootItem];
		else
			fsItem = [zoomStack objectAtIndex: i-1];
		
		if ( i >= ((unsigned) [zoomStackMenu numberOfItems]) )
			[zoomStackMenu addItem: [[NSMenuItem alloc] init]];
		
		NSMenuItem *menuItem = [zoomStackMenu itemAtIndex: i];
		
		[menuItem setTitle: [fsItem displayName]];
		if ( i > 0 ) //no tooltip for first item as the tooltip is the same as the title
			[menuItem setToolTip: [fsItem displayPath]];
		[menuItem setImage: [fsItem iconWithSize: 16]];
		[menuItem setRepresentedObject: fsItem];
		[menuItem setTarget: nil];
		[menuItem setAction: @selector(zoomOutTo:)];
	}
	
	//remove any supernumerary menu items
	while ( ((unsigned) [zoomStackMenu numberOfItems]) > [zoomStack count] )
		[zoomStackMenu removeItemAtIndex: [zoomStackMenu numberOfItems] -1];
}

@end

