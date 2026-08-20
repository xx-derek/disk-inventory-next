/* MainWindowController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import <TreeMapView/TreeMapView.h>
#import "ToolbarWindowController.h"

@class DIXSummaryStripView;
@class DIXStatusBarView;
@class DIXBreadcrumbView;
@class DIXInspectorView;

@interface MainWindowController : ToolbarWindowController <NSSplitViewDelegate>
{
    //Connected straight from the nib. These were the two drawers' content views
    //until the drawers were removed; they are now installed as collapsible
    //split-view panes at window load.
    IBOutlet NSView *_kindStatisticsPane;
	CGFloat _kindStatisticsWidth;   //remembered across a collapse, so reopening restores it
	NSTimer *_kindStatisticsAnimationTimer;
	BOOL _animatingKindStatistics;  //lifts the minimum-width constraint while sliding
    IBOutlet NSView *_selectionListPane;

    NSSplitView *_kindStatisticsSplitView;
    NSSplitView *_selectionListSplitView;

    //Code-built window chrome, installed as siblings of the nib's views:
    //the summary strip above the split view, the status bar along the bottom.
    DIXSummaryStripView *_summaryStripView;
    DIXStatusBarView *_statusBarView;

    //Toolbar items with custom views. Held so they can be refreshed when the
    //document changes without walking the toolbar's item array.
    DIXBreadcrumbView *_breadcrumbView;
    NSSegmentedControl *_viewModeControl;

    //The right-hand pane, replacing the floating Info window.
    DIXInspectorView *_inspectorView;
    CGFloat _inspectorWidth;    //remembered across a collapse, like the sidebar's

    //Set once the panes have been given their opening widths. Until then the
    //split view is still being assembled and resized, and the widths it reports
    //describe nothing anyone chose.
    BOOL _paneWidthsPlaced;

	IBOutlet NSSplitView *_splitter;
	IBOutlet NSOutlineView *_filesOutlineView;
	IBOutlet TreeMapView *_treeMapView;
	IBOutlet NSMenu *_openWithSubMenu;
}

+ (FileSystemDoc*) documentForView: (NSView*) view;

+ (void) poofEffectInView: (NSView*)view inRect: (NSRect) rect; //rect in view coords

//The status bar along the bottom of the window, for the controllers that feed
//it - the treemap routes its hover readout here.
- (DIXStatusBarView*) statusBarView;

//The kind statistics and selection list used to be NSDrawers, deprecated since
//10.13 and visually wrong in dark mode. They are now collapsible split-view
//panes: statistics to the left of the outline and treemap, selection list below
//them, matching the edges the drawers slid out from.
- (BOOL) isKindStatisticsVisible;
- (void) setKindStatisticsVisible: (BOOL) visible;

//Map / List / Both. The window already holds both views in one split; a mode
//is which of them get space. Sent by the toolbar's segmented control.
- (IBAction) changeViewMode: (id) sender;

//The inspector pane down the right-hand side.
- (BOOL) isInspectorVisible;
- (void) setInspectorVisible: (BOOL) visible;
- (IBAction) toggleInspector: (id) sender;

- (BOOL) isSelectionListVisible;
- (void) setSelectionListVisible: (BOOL) visible;

- (IBAction) copy:(id)sender;
- (IBAction) openFile:(id)sender;
- (IBAction) toggleFileKindsDrawer:(id)sender;

//The toolbar's standard sidebar button sends this down the responder chain;
//AppKit supplies the item, the glyph and the placement.
- (IBAction) toggleSidebar:(id)sender;
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
