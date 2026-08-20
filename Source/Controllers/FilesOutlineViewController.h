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

    //Folder -> the kind filling most of it, for the row chips. Built in one
    //pass over the tree and thrown away when the items change; weak keys, so
    //a tree dropped between refreshes takes its entries with it.
    NSMapTable<FSItem*, NSString*> *_dominantKinds;
}

- (FileSystemDoc*) document;

- (FSItem*) rootItem;

@end
