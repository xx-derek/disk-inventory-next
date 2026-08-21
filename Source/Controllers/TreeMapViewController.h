/* TreeMapViewController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"

@class TMVItem;

@interface TreeMapViewController : NSObject
{
    IBOutlet id _fileNameTextField;
    IBOutlet id _fileSizeTextField;
    IBOutlet id _treeMapView;
    //weak: this points back up the ownership chain
    IBOutlet __weak FileSystemDoc *_document;

	FSItem *_otherSpaceItem;
	FSItem *_freeSpaceItem;

	//The cell a click on the map put the document's selection on, so that
	//pushing that selection back at the map can tell "the map already shows
	//this" from "somebody else picked this item" - see
	//-onDocumentSelectionChanged. Weak, so a reload that throws the renderer
	//tree away leaves nil here rather than a stale pointer to compare against.
	__weak TMVItem *_selectionSourceCell;
}

- (FileSystemDoc*) document;

- (FSItem*) rootItem;

@end
