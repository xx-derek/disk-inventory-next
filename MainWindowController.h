/* MainWindowController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import <TreeMapView/TreeMapView.h>
#import "ToolbarWindowController.h"

@interface MainWindowController : ToolbarWindowController <NSSplitViewDelegate>
{
    //The nib still builds these, but only as containers: their content views are
    //re-parented into split views at load time and the drawers themselves are
    //never opened. Typed id so no deprecated NSDrawer symbol appears in code.
    IBOutlet id _kindsDrawer;
    IBOutlet id _selectionListDrawer;

    //the panes that replaced them, and the split views holding them
    NSView *_kindStatisticsPane;
    NSView *_selectionListPane;
    NSSplitView *_kindStatisticsSplitView;
    NSSplitView *_selectionListSplitView;
	IBOutlet NSSplitView *_splitter;
	IBOutlet NSOutlineView *_filesOutlineView;
	IBOutlet TreeMapView *_treeMapView;
	IBOutlet NSMenu *_openWithSubMenu;
}

+ (FileSystemDoc*) documentForView: (NSView*) view;

+ (void) poofEffectInView: (NSView*)view inRect: (NSRect) rect; //rect in view coords

//The kind statistics and selection list used to be NSDrawers, deprecated since
//10.13 and visually wrong in dark mode. They are now collapsible split-view
//panes: statistics to the left of the outline and treemap, selection list below
//them, matching the edges the drawers slid out from.
- (BOOL) isKindStatisticsVisible;
- (void) setKindStatisticsVisible: (BOOL) visible;

- (BOOL) isSelectionListVisible;
- (void) setSelectionListVisible: (BOOL) visible;

- (IBAction) copy:(id)sender;
- (IBAction) openFile:(id)sender;
- (IBAction) toggleFileKindsDrawer:(id)sender;
- (IBAction) toggleSelectionListDrawer:(id)sender;
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) zoomOutTo:(id)sender;
- (IBAction) showInFinder:(id)sender;
- (IBAction) refresh:(id)sender;
- (IBAction) refreshAll:(id)sender;
- (IBAction) moveToTrash:(id)sender;
- (IBAction) showPackageContents:(id)sender;
- (IBAction) showFreeSpace:(id)sender;
- (IBAction) showOtherSpace:(id)sender;
- (IBAction) selectParentItem:(id)sender;
- (IBAction) changeSplitting:(id)sender;
- (IBAction) showInformationPanel:(id)sender;
- (IBAction) showPhysicalSizes:(id) sender;
- (IBAction) ignoreCreatorCode:(id) sender;

- (IBAction) performRenderBenchmark:(id)sender;
- (IBAction) performLayoutBenchmark:(id)sender;
@end

//posted by MainWindowController when the selection list is shown or hidden, so
//the list can stop recomputing itself while it is not on screen
extern NSString *SelectionListVisibilityChangedNotification;
