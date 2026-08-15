/* TreeMapViewController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"

@interface TreeMapViewController : NSObject
{
    IBOutlet id _fileNameTextField;
    IBOutlet id _fileSizeTextField;
    IBOutlet id _treeMapView;
    //weak: this points back up the ownership chain
    IBOutlet __weak FileSystemDoc *_document;
	
	FSItem *_otherSpaceItem;
	FSItem *_freeSpaceItem;
}

- (FileSystemDoc*) document;

- (FSItem*) rootItem;

@end
