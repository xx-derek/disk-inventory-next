/* MainWindowController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import <TreeMapView/TreeMapView.h>
#import "ToolbarWindowController.h"

@class DIXSummaryStripView;
@class DIXStatusBarView;
@class DIXBreadcrumbView;
@class DIXInspectorView;
@class DIXSourcesView;
@class DIXKindsView;
@class DIXSegmentedControl;
@class DIXChangesController;
@class DIXPrivacyBannerView;

@interface MainWindowController : ToolbarWindowController <NSSplitViewDelegate, NSWindowDelegate>
{
    //The sidebar's pane. It was the kind-statistics drawer's content view in the
    //nib; it is built in -buildSidePanes now, and the selection list that sat
    //beside it went with the nib - the inspector's siblings list replaced it.
    NSView *_kindStatisticsPane;
	CGFloat _kindStatisticsWidth;   //remembered across a collapse, so reopening restores it
	NSTimer *_kindStatisticsAnimationTimer;
	BOOL _animatingKindStatistics;  //lifts the minimum-width constraint while sliding

    NSSplitView *_kindStatisticsSplitView;

    //The middle column: the summary strip, the outline/treemap split, and the
    //status bar. The design scopes the strip and the bar to this column - the
    //sidebar and the inspector run the window's full height beside them - so
    //they are held by a container rather than by the content view.
    NSView *_centreColumn;

    //The two halves of the outline/map split, each holding its pane and the band
    //the design puts under or over it: the list its caption, the map the summary
    //strip. They are the split view's subviews now, so hiding one is what
    //collapses that pane - see -placeSummaryStrip.
    NSView *_listColumn;
    NSView *_listFooterView;
    NSView *_mapColumn;

    DIXSummaryStripView *_summaryStripView;
    DIXStatusBarView *_statusBarView;

    //restates "scanned 8 seconds ago" as it ages; see -startSummaryAgeClock
    NSTimer *_summaryAgeTimer;

    //The title bar's leading accessory: the sidebar button and the breadcrumb.
    //Neither is a toolbar item - see -installTitleAccessory for why - so both
    //are held here rather than looked up in the toolbar's item array.
    NSView *_titleAccessoryView;
    NSButton *_sidebarButton;
    DIXBreadcrumbView *_breadcrumbView;

    //And the trailing one: the mode switch, the search field and the inspector
    //button. In the toolbar each of those was wrapped in a Liquid Glass capsule
    //that the design does not have - see -installTrailingAccessory.
    NSView *_trailingAccessoryView;
    NSView *_searchBox;
    NSButton *_scopeButton;
    NSMenu *_searchScopeMenu;
    NSButton *_inspectorButton;

    //The title bar's fill, the sidebar's fill and trailing edge carried up
    //through it, and the line underneath. All four are drawn by the application
    //rather than by AppKit - see -colourTitleBar for why each one has to be.
    NSBox *_titleBarBand;
    NSBox *_titleBarSidebarBand;
    NSBox *_titleBarSidebarEdge;
    NSBox *_titleBarSeparator;

    //The sidebar is two sections in one pane: SOURCES over FILE KINDS. The pane
    //is a plain container so the split view still sees one subview per column
    //and the collapse logic does not have to learn about the split inside it.
    DIXSourcesView *_sourcesView;
    DIXKindsView *_kindsView;
    NSBox *_sectionRule;        //the 2pt rule between the two sections
    NSView *_sidebarPane;
    DIXSegmentedControl *_viewModeControl;

    //The toolbar's search field. The query itself lives on the document.
    NSSearchField *_searchField;

    //"Since 8 Aug", built on the first ask and kept: it is one window per
    //document, and rebuilding it would lose where the user had scrolled to.
    DIXChangesController *_changesController;

    //"3 folders were skipped", across the top of the centre column. Nil until
    //there is something to say, and dropped for good once dismissed.
    DIXPrivacyBannerView *_privacyBannerView;

    //The right-hand pane, replacing the floating Info window.
    DIXInspectorView *_inspectorView;
    CGFloat _inspectorWidth;    //remembered across a collapse, like the sidebar's
    BOOL _collapsingInspector;  //lifts its minimum while the divider moves to the edge
    NSTimer *_inspectorAnimationTimer;

    //Set once the panes have been given their opening widths. Until then the
    //split view is still being assembled and resized, and the widths it reports
    //describe nothing anyone chose.
    BOOL _paneWidthsPlaced;

    //Later still: set a run-loop turn after the window loads, once the dividers
    //have been placed against the window's real frame. From then on a change of
    //the split view's width is a window resize and belongs to the middle column
    //- see -splitView:shouldAdjustSizeOfSubview:.
    BOOL _paneWidthsSettled;

	//Built in -loadWindow, not loaded from a nib - see the note there.
	NSSplitView *_splitter;
	NSOutlineView *_filesOutlineView;
	TreeMapView *_treeMapView;
	NSMenu *_openWithSubMenu;

	//The two per-view controllers the nib used to instantiate. Held because
	//nothing else does: the views' data source and delegate are unretained.
	id _filesOutlineController;
	id _treeMapController;

	//set before -loadWindow runs, so the re-entry from -buildSidePanes asking
	//for the window does not start building a second one
	BOOL _windowBuilt;
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
- (void) setInspectorVisible: (BOOL) visible animated: (BOOL) animated;
- (IBAction) toggleInspector: (id) sender;


- (IBAction) copy:(id)sender;
- (IBAction) openFile:(id)sender;
- (IBAction) toggleFileKindsDrawer:(id)sender;

//The toolbar's standard sidebar button sends this down the responder chain;
//AppKit supplies the item, the glyph and the placement.
- (IBAction) toggleSidebar:(id)sender;
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) zoomOutTo:(id)sender;
- (IBAction) showInFinder:(id)sender;
- (IBAction) refresh:(id)sender;
- (IBAction) refreshAll:(id)sender;
- (IBAction) moveToTrash:(id)sender;
- (IBAction) reclaimBasket:(id)sender;
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
