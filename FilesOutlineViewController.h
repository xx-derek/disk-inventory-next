/* FilesOutlineViewController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import "ImageAndTextCell.h"
#import "FileSizeFormatter.h"
#import "DIXOutlineView.h"

@interface FilesOutlineViewController : NSObject
{
    //weak: this points back up the ownership chain
    __weak IBOutlet FileSystemDoc *_document;
    IBOutlet DIXOutlineView *_outlineView;
    IBOutlet NSMenu *_contextMenu;
}

- (FileSystemDoc*) document;

- (FSItem*) rootItem;

@end
