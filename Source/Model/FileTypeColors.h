//
//  FileTypeColors.h
//  Disk Inventory Next
//
//  Created by Tjark Derlien on Sun Oct 05 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import <Foundation/Foundation.h>
#import "FSItem.h"

@interface FileTypeColors : NSObject {
    NSMutableDictionary *_colors;
    NSMutableArray *_predefinedColors;
    NSMutableArray *_modernColors;
    NSMutableArray *_classicColors;
    BOOL _usesClassicPalette;
}

+ (FileTypeColors*) instance;

- (NSColor *) colorForItem: (FSItem*) item;
- (NSColor *) colorForKind: (NSString*) kind;

- (void) reset;

//Which of the two kind palettes is in use. The classic one goes with the classic
//cushion shading and its ambient floor; see the comment beside it.
- (BOOL) usesClassicPalette;
- (void) setUsesClassicPalette: (BOOL) classic;

@end
