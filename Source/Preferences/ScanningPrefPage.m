//
//  ScanningPrefPage.m
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

#import "ScanningPrefPage.h"
#import "PrefsPageLayout.h"
#import "Preferences.h"
#import "DIXScanHistory.h"
#import "FileSizeFormatter.h"

static NSString * const PrefsTitlesTable = @"Preferences";

//the choices offered for concurrency, from the bounds the preference declares
static NSArray<NSNumber*>* ScanConcurrencyValues( void )
{
	NSMutableArray *values = [NSMutableArray array];

	for ( NSInteger i = ScanConcurrencyMinimum; i <= ScanConcurrencyMaximum; i++ )
		[values addObject: [NSNumber numberWithInteger: i]];

	return values;
}

static NSArray<NSString*>* ScanConcurrencyTitles( void )
{
	NSMutableArray *titles = [NSMutableArray array];

	for ( NSInteger i = ScanConcurrencyMinimum; i <= ScanConcurrencyMaximum; i++ )
		[titles addObject: [NSString stringWithFormat: @"%ld", (long) i]];

	return titles;
}

@interface ScanningPrefPage()
{
	PrefsStatusRow *_storedRow;
	PrefsPathRow *_pathRow;
}
- (IBAction) chooseHistoryFolder: (id) sender;
- (IBAction) deleteHistory: (id) sender;
- (void) refreshStoredRow;
@end

@implementation ScanningPrefPage

- (NSView*) buildControlBox
{
	PrefsPageLayout *layout = [PrefsPageLayout layoutWithWidth: [[self class] contentWidth]];

	[layout beginSectionWithLabel: @"History"];

	[layout addPopUpTitled: @"Keep scan history for"
					  help: @"Older scans are deleted automatically. Set to Off to keep none and turn the change view off."
			   defaultsKey: ScanHistoryRetentionDays
					titles: @[ @"Off", @"30 days", @"3 months", @"6 months", @"1 year", @"Forever" ]
					values: @[ @(DIXHistoryOff), @30, @90, @180, @365, @(DIXHistoryForever) ]];

	_pathRow = [layout addPathRowTitled: @"Store history in"
								   help: @"Defaults to Application Support. Point it at a synced folder to compare across Macs."
							buttonTitle: @"Choose…"
								 target: self
								 action: @selector(chooseHistoryFolder:)];

	_storedRow = [layout addStatusTitled: @"Stored now" help: @""];

	[layout addButtonTitled: @"Delete history now"
					   help: @"Removes every stored scan. This cannot be undone."
				buttonTitle: @"Delete…"
				destructive: YES
					 target: self
					 action: @selector(deleteHistory:)];

	[layout addFootnote: @"History is what makes “what changed since last time” possible. It stores sizes and paths only — no file contents. Moving the folder moves the existing scans with it."];

	[layout beginSectionWithLabel: @"While scanning"];

	//Concurrency is a setting rather than a constant because it is the one part
	//of the scan whose best value depends on the drive: a fast internal SSD
	//likes several requests outstanding, a network share or a spinning disk can
	//be made slower by them. One walks everything in order, as the scan did
	//before this was settable.
	[layout addPopUpTitled: @"Folders at a time"
					  help: @"How many folders inside the one being scanned are read at once. Higher is usually faster on an internal drive; choose 1 to scan everything in order, which can be better over a network."
			   defaultsKey: ScanConcurrency
					titles: ScanConcurrencyTitles()
					values: ScanConcurrencyValues()];

	//"Follow symbolic links" is in the design and is deliberately not here. The
	//walk does not follow them and nothing in this application makes it - and a
	//switch whose On position does nothing is a claim about what the scan does.
	//Implementing it means cycle detection on the hot path of every directory,
	//which is a change to the walk rather than a setting to expose.

	[layout addToggleTitled: @"Show partial results"
					   help: @"Lets you open the window before the scan finishes."
				defaultsKey: ShowPartialResults];

	[self addRestoreDefaultsSectionTo: layout
								 help: @"Returns this tab to its factory settings. Stored scans and their folder are kept."];

	[self setLayout: layout];

	[self refreshStoredRow];

	return [layout view];
}

#pragma mark --------what is stored-----------------

- (void) refreshStoredRow
{
	DIXScanHistory *history = [DIXScanHistory sharedHistory];

	[_pathRow setPath: [[history storageDirectory] path]];

	const NSUInteger count = [history snapshotCount];
	const unsigned long long bytes = [history storedByteCount];

	FileSizeFormatter *sizeFormatter = [[FileSizeFormatter alloc] init];

	//Nothing stored is not a fault, so it is not the accent - it is the state a
	//fresh install is in, and the state Off leaves behind.
	[_storedRow setStatusText: [sizeFormatter stringForObjectValue: @(bytes)] good: ( count > 0 )];

	[_storedRow setHelpText: ( count == 1 )
		? NSLocalizedStringFromTable( @"1 folder.", PrefsTitlesTable, @"" )
		: [NSString stringWithFormat:
			NSLocalizedStringFromTable( @"%lu folders.", PrefsTitlesTable, @"" ),
			(unsigned long) count]];
}

- (void) valuesHaveChanged
{
	[super valuesHaveChanged];

	//A retention of Off deletes what is there, so the row has to be counted
	//again rather than left saying what used to be true.
	[[DIXScanHistory sharedHistory] pruneToRetentionWindow];

	[self refreshStoredRow];
}

#pragma mark --------the two buttons-----------------

- (IBAction) chooseHistoryFolder: (id) sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];

	[panel setCanChooseDirectories: YES];
	[panel setCanChooseFiles: NO];
	[panel setCanCreateDirectories: YES];
	[panel setAllowsMultipleSelection: NO];
	[panel setDirectoryURL: [[DIXScanHistory sharedHistory] storageDirectory]];
	[panel setPrompt: NSLocalizedStringFromTable( @"Choose", PrefsTitlesTable, @"" )];

	NSWindow *window = [[self controlBox] window];

	void (^respond)( NSModalResponse ) = ^( NSModalResponse response )
	{
		if ( response != NSModalResponseOK || [panel URL] == nil )
			return;

		NSError *error = nil;

		if ( ![[DIXScanHistory sharedHistory] moveStorageToDirectory: [panel URL] error: &error] )
		{
			//The old location is still the one being used, which is what the
			//alert has to say - otherwise "it failed" leaves someone wondering
			//where their history went.
			NSAlert *alert = [[NSAlert alloc] init];

			[alert setMessageText: NSLocalizedStringFromTable(
				@"The scan history could not be moved.", PrefsTitlesTable, @"" )];
			[alert setInformativeText: [error localizedDescription] ?:
				NSLocalizedStringFromTable( @"It is still stored where it was.",
											PrefsTitlesTable, @"" )];

			[alert runModal];
		}

		[self refreshStoredRow];
	};

	if ( window != nil )
		[panel beginSheetModalForWindow: window completionHandler: respond];
	else
		respond( [panel runModal] );
}

- (IBAction) deleteHistory: (id) sender
{
	NSAlert *alert = [[NSAlert alloc] init];

	[alert setMessageText: NSLocalizedStringFromTable( @"Delete every stored scan?",
													   PrefsTitlesTable, @"" )];
	[alert setInformativeText: NSLocalizedStringFromTable(
		@"This cannot be undone. Until each folder is scanned twice again, nothing can be compared.",
		PrefsTitlesTable, @"" )];

	[alert addButtonWithTitle: NSLocalizedStringFromTable( @"Delete", PrefsTitlesTable, @"" )];
	[alert addButtonWithTitle: NSLocalizedStringFromTable( @"Cancel", PrefsTitlesTable, @"" )];

	//the destructive one must not be what Return presses
	[[[alert buttons] objectAtIndex: 0] setKeyEquivalent: @""];
	[[[alert buttons] objectAtIndex: 1] setKeyEquivalent: @"\r"];

	NSWindow *window = [[self controlBox] window];

	void (^respond)( NSModalResponse ) = ^( NSModalResponse returnCode )
	{
		if ( returnCode != NSAlertFirstButtonReturn )
			return;

		[[DIXScanHistory sharedHistory] deleteAllSnapshots];
		[self refreshStoredRow];
	};

	if ( window != nil )
		[alert beginSheetModalForWindow: window completionHandler: respond];
	else
		respond( [alert runModal] );
}

@end
