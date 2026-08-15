//
//  ToolbarWindowController.m
//  Disk Inventory Next
//
//  Created by Tjark Derlien on 01.12.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "ToolbarWindowController.h"
#import "NSImage-Extensions.h"

//a "target" of this means "whatever is first responder", not a key path
static NSString * const ToolbarFirstResponderTarget = @"firstResponder";

@interface NSMenu(FindExtensions)

- (NSMenuItem*) menuItemWithAction: (SEL) action;

@end

#pragma mark -----------------ToolbarItem---------------------

@implementation ToolbarItem

@synthesize delegate = _delegate;

- (void) validate
{
	if ( [_delegate respondsToSelector: @selector(validateToolbarItem:)] )
		[self setEnabled: [_delegate validateToolbarItem: self]];
	else
		[super validate];
}

@end

#pragma mark -----------------validation adapter---------------------

@implementation NSToolbarItemValidationAdapter

- (void) setToolbarItem: (NSToolbarItem*) toolbarItem
{
	_toolbarItem = toolbarItem;
}


- (void) forwardInvocation: (NSInvocation*) anInvocation
{
	if ( [_toolbarItem respondsToSelector: [anInvocation selector]] )
	{
		[anInvocation setTarget: _toolbarItem];
		[anInvocation invoke];
	}
	else
		[super forwardInvocation: anInvocation];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector
{
	if ( [_toolbarItem respondsToSelector: aSelector] )
		return [_toolbarItem methodSignatureForSelector: aSelector];
	else
		return [super methodSignatureForSelector: aSelector];
}

//NSToolbarItem has no notion of state, so this is where a validating
//-validateMenuItem: gets turned into the right image for the toolbar.
- (void) setState: (NSControlStateValue) itemState
{
	ToolbarWindowController *controller = (ToolbarWindowController *)[[_toolbarItem toolbar] delegate];

    if ( [controller respondsToSelector:@selector(toolbar:imageForToolbarItem:forState:)] )
    {
        NSImage *image = [controller toolbar: [_toolbarItem toolbar]
                         imageForToolbarItem: _toolbarItem
                                    forState: itemState];

        if ( image != nil && image != [_toolbarItem image] )
            [_toolbarItem setImage: image];
    }
}

@end

#pragma mark -----------------ToolbarWindowController---------------------

static NSToolbarItemValidationAdapter *g_toolbarItemValidationAdapter = nil;
static NSMutableDictionary *g_toolbarStateImages = nil;

@implementation ToolbarWindowController

+ (void) initialize
{
	if ( self != [ToolbarWindowController class] )
		return;

	g_toolbarItemValidationAdapter = [[NSToolbarItemValidationAdapter alloc] init];
	g_toolbarStateImages = [[NSMutableDictionary alloc] init];
}

#pragma mark -----------------the configuration file---------------------

- (NSString*) toolbarConfigurationName
{
	return nil;
}

- (NSDictionary*) toolbarConfigurationInfo
{
	NSString *name = [self toolbarConfigurationName];
	if ( name == nil )
		return nil;

	//cached per configuration name, since every document window builds its
	//toolbar from the same file
	static NSMutableDictionary *configurationsByName = nil;
	if ( configurationsByName == nil )
		configurationsByName = [[NSMutableDictionary alloc] init];

	NSDictionary *configuration = [configurationsByName objectForKey: name];
	if ( configuration != nil )
		return configuration;

	NSString *path = [[NSBundle mainBundle] pathForResource: name ofType: @"toolbar"];
	if ( path == nil )
	{
		NSLog( @"no toolbar configuration named '%@' in the bundle", name );
		return nil;
	}

	configuration = [NSDictionary dictionaryWithContentsOfFile: path];
	if ( configuration == nil )
	{
		NSLog( @"toolbar configuration '%@' could not be read", path );
		return nil;
	}

	[configurationsByName setObject: configuration forKey: name];

	return configuration;
}

- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier;
{
	NSDictionary *storedInfo =
		[[[self toolbarConfigurationInfo] objectForKey: @"itemInfoByIdentifier"] objectForKey: identifier];

	if ( storedInfo == nil )
		return [NSDictionary dictionary];

	NSMutableDictionary *itemInfo = [NSMutableDictionary dictionaryWithDictionary: storedInfo];

	//localize existing strings
#define LOCALIZE_PROPERTY( propname )									\
	if ( [[itemInfo objectForKey: propname] length] > 0 )				\
	{																	\
		NSString *localized = NSLocalizedString( [itemInfo objectForKey: propname], @"" ); \
		[itemInfo setObject: localized forKey: propname];				\
	}

	LOCALIZE_PROPERTY( @"label" );
	LOCALIZE_PROPERTY( @"paletteLabel" );
	LOCALIZE_PROPERTY( @"toolTip" );

#undef LOCALIZE_PROPERTY

	//We now try get the title and tooltip for the toolbar item from the menu.
	//This is done by searching for a menu item with the same action as the toolbar item.
	//Doing this, we don't need to type indentical strings in both the menu resource and the toolbar resource (.toolbar plist file).
	//And they only need to be localized in one place!

	NSString *actionString = [itemInfo objectForKey:@"action"];
	//did someone forgot the ':' at the end of the string? (actions always have the sender as a parameter)
	if ( [actionString length] > 0 && [actionString characterAtIndex: [actionString length] -1] != ':' )
	{
		actionString = [actionString stringByAppendingString: @":"];
		[itemInfo setObject: actionString forKey:@"action"];
	}

	SEL action = NSSelectorFromString( actionString );

	if (  action != 0
		  && ( [itemInfo objectForKey:@"label"] == nil || [itemInfo objectForKey:@"toolTip"] == nil ) )
	{
		NSMenuItem * menuItem = [[NSApp mainMenu] menuItemWithAction: action];
		if ( menuItem != nil )
		{
			//set label?
			if ( [itemInfo objectForKey:@"label"] == nil && [[menuItem title] length] > 0 )
			{
				//delete periods at end of title (e.g. "Preferences...")
				NSString *title = [menuItem title];
				NSUInteger numOfRemainingChars = [title length];
				unichar lastChar;
				do
				{
					numOfRemainingChars--;
					lastChar = [title characterAtIndex: numOfRemainingChars];
				}
				while ( ( lastChar == '.' || isspace(lastChar) ) && numOfRemainingChars > 0 );
				title = [title substringToIndex: numOfRemainingChars+1];

				[itemInfo setObject: title forKey: @"label"];
			}
			//set tooltip?
			if ( [itemInfo objectForKey:@"toolTip"] == nil && [[menuItem toolTip] length] > 0 )
				[itemInfo setObject: [menuItem toolTip] forKey: @"toolTip"];
		}
	}

	//if no string for "paletteLabel" is set, use the one for "label"
	//(the paletteLabel is used as the toolbar item's title in the customizable sheet)
	if ( [itemInfo objectForKey:@"paletteLabel"] == nil
		 && [itemInfo objectForKey:@"label"] != nil )
		[itemInfo setObject: [itemInfo objectForKey:@"label"] forKey: @"paletteLabel"];

    return itemInfo;
}

#pragma mark -----------------building the toolbar---------------------

- (void) windowDidLoad
{
	[super windowDidLoad];

	if ( [self toolbarConfigurationInfo] == nil )
		return;

	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: [self toolbarConfigurationName]];

	[toolbar setDelegate: self];
	[toolbar setAllowsUserCustomization: YES];
	[toolbar setAutosavesConfiguration: YES];

	[[self window] setToolbar: toolbar];
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarAllowedItemIdentifiers: (NSToolbar*) toolbar
{
	return [[self toolbarConfigurationInfo] objectForKey: @"allowedItemIdentifiers"];
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarDefaultItemIdentifiers: (NSToolbar*) toolbar
{
	return [[self toolbarConfigurationInfo] objectForKey: @"defaultItemIdentifiers"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)aToolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)willInsert
{
	//separators, spaces and the customize item are AppKit's to build
	if ( [[[self toolbarConfigurationInfo] objectForKey: @"itemInfoByIdentifier"] objectForKey: itemIdentifier] == nil )
		return nil;

	NSDictionary *itemInfo = [self toolbarInfoForItem: itemIdentifier];

	ToolbarItem *toolbarItem = [[ToolbarItem alloc] initWithItemIdentifier: itemIdentifier];

	NSString *label = [itemInfo objectForKey: @"label"];
	if ( label != nil )
		[toolbarItem setLabel: label];

	NSString *paletteLabel = [itemInfo objectForKey: @"paletteLabel"];
	[toolbarItem setPaletteLabel: ( paletteLabel != nil ) ? paletteLabel : [toolbarItem label]];

	NSString *toolTip = [itemInfo objectForKey: @"toolTip"];
	if ( toolTip != nil )
		[toolbarItem setToolTip: toolTip];

	//Item images are SF Symbols named in the toolbar plist, so they are vector,
	//tint with the appearance, and carry the item's label to VoiceOver.
	NSString *symbolName = [itemInfo objectForKey: @"symbolName"];
	if ( symbolName != nil )
	{
		NSImage *image = [NSImage imageForSymbolName: symbolName
							accessibilityDescription: [toolbarItem label]];
		if ( image != nil )
			[toolbarItem setImage: image];
		else
			NSLog( @"toolbar item '%@' wants a missing symbol '%@'", itemIdentifier, symbolName );
	}

	NSString *actionName = [itemInfo objectForKey: @"action"];
	if ( actionName != nil )
		[toolbarItem setAction: NSSelectorFromString( actionName )];

	//An absent target is the controller itself. Anything else is a key path
	//evaluated against the controller, except "firstResponder", which means
	//leaving the target nil so the action travels the responder chain.
	NSString *targetKeyPath = [itemInfo objectForKey: @"target"];

	if ( targetKeyPath == nil )
		[toolbarItem setTarget: self];
	else if ( ![targetKeyPath isEqualToString: ToolbarFirstResponderTarget] )
		[toolbarItem setTarget: [self valueForKeyPath: targetKeyPath]];

    //NSToolbarItem calls it's target to validate itself (through validateToolbarItem:).
	//If the target is not self we have no control over the validation.
	//This "problem" can be solved to set ourself as the delegate. ToolbarItem's delegate
	//has the last word in the validation process.
    [toolbarItem setDelegate: self];

	return toolbarItem;
}

#pragma mark -----------------state images---------------------

//returns an image for a toolbar item with a specific state (on, off or mixed, like menu items)
- (NSImage*) toolbar: (NSToolbar*) theToolbar imageForToolbarItem: (NSToolbarItem*) item forState: (NSControlStateValue) state;
{
	NSString *imageKey = nil;
	switch( state )
	{
		case NSControlStateValueOn:
			imageKey = @"symbolName";
			break;
		case NSControlStateValueOff:
			imageKey = @"symbolNameOffState";
			break;
		case NSControlStateValueMixed:
			imageKey = @"symbolNameMixedState";
			break;
		default:
			NSAssert( NO, @"invalid item state for ToolbarItem" );
	}

	//get the image cache for our toolbar
	NSMutableDictionary *toolbarImageCache = [g_toolbarStateImages objectForKey: [self toolbarConfigurationName]];
	if ( toolbarImageCache == nil )
	{
		toolbarImageCache = [NSMutableDictionary dictionary];
		[g_toolbarStateImages setObject: toolbarImageCache forKey: [self toolbarConfigurationName]];
	}

	//get image cache for the toolbar item
	NSMutableDictionary *itemImageCache = [toolbarImageCache objectForKey: [item itemIdentifier]];
	if ( itemImageCache == nil )
	{
		itemImageCache = [NSMutableDictionary dictionary];
		[toolbarImageCache setObject: itemImageCache forKey: [item itemIdentifier]];
	}

	//get the state image from the toolbar item image cache
	NSImage *image = [itemImageCache objectForKey: imageKey];
	if ( image == nil )
	{
		NSDictionary *itemInfo = [self toolbarInfoForItem: [item itemIdentifier]];

		//get symbol name from info dictionary, falling back to the on-state one
		NSString *symbolName = [itemInfo objectForKey: imageKey];
		if ( symbolName == nil )
			symbolName = [itemInfo objectForKey: @"symbolName"];

		NSAssert1( symbolName != nil, @"no symbol name for item '%@'", [item itemIdentifier] );

		image = [NSImage imageForSymbolName: symbolName accessibilityDescription: [item label]];
		NSAssert1( image != nil, @"couldn't load symbol '%@'", symbolName );

		[itemImageCache setObject: image forKey: imageKey];
	}

	return image;
}

#pragma mark -----------------targets and validation---------------------

// if a toolbar item description contains a "target" property, it is resolved by
// calling valueForKeyPath. So for every target besides the window controller
// ("target" not set) or the first responder ("target" property == "firstResponder"),
// the toolbar delegate has to declare a property. We declare two.

- (NSDocumentController*) documentController
{
    return [NSDocumentController sharedDocumentController];
}

- (NSApplication*) application
{
    return NSApp;
}

// NSObject (NSToolbarItemValidation)

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
{
    if ( ![[self window] isKeyWindow] )
		return NO;

	[g_toolbarItemValidationAdapter setToolbarItem: theItem];

	return [self validateMenuItem: (NSMenuItem*) g_toolbarItemValidationAdapter];
}

@end

@implementation NSMenu(FindExtensions)

//linear search through all menu items (including sub menus)
- (NSMenuItem*) menuItemWithAction: (SEL) action
{
	//we enumerate backwards as for the main menu bar the more application specific actions
	//are often in the menus after "File" and "Edit", so it is more likely to find the
	//item in question in the rear menus (this may not apply to sub menus, but we do a linar search anyway)
	NSInteger i = [self numberOfItems];
	while ( i-- )
	{
		NSMenuItem *menuItem = [self itemAtIndex: i];

		if ( [menuItem action] == action )
			return menuItem;

		if ( [menuItem hasSubmenu] )
		{
			menuItem = [[menuItem submenu] menuItemWithAction: action];
			if ( menuItem != nil )
				return menuItem;
		}
	}

	//not found
	return nil;
}

@end
