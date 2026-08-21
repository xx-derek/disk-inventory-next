//
//  PrivacyPrefPage.m
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

#import "PrivacyPrefPage.h"
#import "PrefsPageLayout.h"
#import "Preferences.h"

static NSString * const PrefsTitlesTable = @"Preferences";

//The pane the Open button goes to. A URL rather than a scripted click, and the
//anchor is what puts it on Full Disk Access rather than the top of Privacy.
static NSString * const kFullDiskAccessPane =
	@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles";

@interface PrivacyPrefPage()
{
	PrefsStatusRow *_accessRow;
}
- (IBAction) openSystemSettings: (id) sender;
- (void) refreshAccessRow;
@end

@implementation PrivacyPrefPage

- (NSView*) buildControlBox
{
	PrefsPageLayout *layout = [PrefsPageLayout layoutWithWidth: [[self class] contentWidth]];

	[layout beginSectionWithLabel: @"Access"];

	_accessRow = [layout addStatusTitled: @"Full Disk Access" help: @""];

	[layout addButtonTitled: @"Manage in System Settings"
					   help: @"Opens the Privacy & Security pane."
				buttonTitle: @"Open"
				destructive: NO
					 target: self
					 action: @selector(openSystemSettings:)];

	[layout addFootnote: @"Without Full Disk Access, protected folders are skipped and the total is lower than the real one."];

	[layout beginSectionWithLabel: @"Protected folders"];

	//The stored key is a suppression flag - DontShowPrivacyWarningMessage - and
	//the row reads the other way round, which is what "inverted" is for. The
	//alternative was renaming the key and losing everyone's existing choice.
	[layout addToggleTitled: @"Warn before scanning them"
					   help: @"Explains the macOS prompt the first time it appears."
				defaultsKey: DontShowPrivacyWarningMessage
				   inverted: YES];

	[layout addToggleTitled: @"Show a banner when folders are skipped"
					   help: @"Tells you the total is incomplete, at the moment you read the total."
				defaultsKey: ShowSkippedFoldersBanner];

	//"Send anonymous crash reports" is in the design and is deliberately not
	//here: the handoff says to ship the row only if it is implemented, and
	//nothing in this application sends anything anywhere. A switch that did
	//nothing would be a claim about what the application does.

	[self addRestoreDefaultsSectionTo: layout
								 help: @"Returns this tab to its factory settings. System permissions are unaffected."];

	[self setLayout: layout];

	[self refreshAccessRow];

	return [layout view];
}

#pragma mark --------what the system allows-----------------

//There is no API that answers "do I have Full Disk Access". The way to find out
//is to read something only that permission opens: TCC's own database. Reading a
//protected folder's *listing* is not enough - a folder can be empty - so this
//opens a file that always exists and that nothing else grants.
- (BOOL) hasFullDiskAccess
{
	NSString *probe = [NSHomeDirectory() stringByAppendingPathComponent:
		@"Library/Application Support/com.apple.TCC/TCC.db"];

	return [[NSFileManager defaultManager] isReadableFileAtPath: probe];
}

- (void) refreshAccessRow
{
	const BOOL granted = [self hasFullDiskAccess];

	[_accessRow setStatusText: NSLocalizedStringFromTable( granted ? @"Granted" : @"Not granted",
														   PrefsTitlesTable, @"" )
						 good: granted];

	[_accessRow setHelpText: granted
		? @"Granted in System Settings › Privacy & Security."
		: @"Protected folders will be skipped until it is granted."];
}

- (void) valuesHaveChanged
{
	[super valuesHaveChanged];

	[self refreshAccessRow];
}

- (IBAction) openSystemSettings: (id) sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: kFullDiskAccessPane]];

	//Granting it quits and relaunches the application, so this will usually not
	//be here to see the answer change - but a user who only looked and came
	//back should not be told something stale.
	[self performSelector: @selector(refreshAccessRow) withObject: nil afterDelay: 1.0];
}

@end
