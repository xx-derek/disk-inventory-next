//
//  main.m
//  Disk Accountant
//
//  Created by Tjark Derlien on Sun Oct 26 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import <Cocoa/Cocoa.h>
#import "Preferences.h"

//The factory settings live in Info.plist, under Registrations, because that
//is where the OmniGroup frameworks used to read them from. They are still kept
//there so the preference pages and their defaults stay described in one place,
//but registering them is now this application's own job.
static void RegisterFactoryDefaults(void)
{
	NSDictionary *registrations = [[[NSBundle mainBundle] infoDictionary] objectForKey: AppRegistrationsKey];
	NSDictionary *defaults = [[registrations objectForKey: @"NSUserDefaults"] objectForKey: @"defaultsDictionary"];

	if ( defaults == nil )
	{
		NSLog( @"no factory defaults found in Info.plist under Registrations" );
		return;
	}

	[[NSUserDefaults standardUserDefaults] registerDefaults: defaults];
}

int main(int argc, const char *argv[])
{
	//before NSApplicationMain, because the nibs load bindings against these
	//as soon as the application starts up
	RegisterFactoryDefaults();

	return NSApplicationMain(argc, argv);
}
