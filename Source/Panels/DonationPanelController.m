//
//  DonationPanelController.m
//  Disk Inventory Next
//
//  Copyright (C) 2026 Disk Inventory Next contributors.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "DonationPanelController.h"
#import "Preferences.h"
#import <CoreImage/CoreImage.h>

//One constant. The QR code is generated from it at runtime rather than shipped
//as an image, so the code and the text below it cannot drift apart.
static NSString * const kDonationAddress = @"0xe56f2b8e59c96e2bcb7b4d9f636cb3badfdd5abc";

static NSString * const kOriginalAuthorSite = @"http://www.derlien.com";

static const CGFloat kMargin      = 20.0;
static const CGFloat kQRSize      = 132.0;
static const CGFloat kPanelWidth  = 460.0;

@interface DonationPanelController()
- (void) buildPanel;
- (NSImage*) qrCodeImageOfSize: (CGFloat) size;
- (NSTextField*) labelWithString: (NSString*) string;
@end

@implementation DonationPanelController

+ (DonationPanelController*) sharedController
{
	static DonationPanelController *controller = nil;
	static dispatch_once_t once;

	dispatch_once( &once, ^{ controller = [[DonationPanelController alloc] init]; });

	return controller;
}

+ (NSString*) donationAddress
{
	return kDonationAddress;
}

- (void) showPanelIfWanted
{
	if ( [[NSUserDefaults standardUserDefaults] boolForKey: DontShowDonationMessage] )
		return;

	if ( _panel == nil )
		[self buildPanel];

	[_panel center];
	[_panel makeKeyAndOrderFront: nil];
}

#pragma mark --------the QR code-----------------

//CIQRCodeGenerator emits one pixel per module, so it has to be scaled up — and
//with no interpolation, or the modules blur into each other and readers start
//failing at small sizes.
- (NSImage*) qrCodeImageOfSize: (CGFloat) size
{
	CIFilter *generator = [CIFilter filterWithName: @"CIQRCodeGenerator"];

	if ( generator == nil )
		return nil;

	//ISO Latin 1 is what the generator documents for inputMessage; the address
	//is ASCII either way
	[generator setValue: [kDonationAddress dataUsingEncoding: NSISOLatin1StringEncoding]
				 forKey: @"inputMessage"];

	//"M" recovers from about 15% damage, which is plenty for a screen and keeps
	//the modules large enough to scan from a phone held at arm's length
	[generator setValue: @"M" forKey: @"inputCorrectionLevel"];

	CIImage *code = [generator outputImage];
	if ( code == nil )
		return nil;

	const CGFloat scale = size / NSWidth( NSRectFromCGRect( [code extent] ) );
	CIImage *scaled = [code imageByApplyingTransform: CGAffineTransformMakeScale( scale, scale )];

	NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage: scaled];
	NSImage *image = [[NSImage alloc] initWithSize: [rep size]];
	[image addRepresentation: rep];

	return image;
}

#pragma mark --------building the panel-----------------

- (NSTextField*) labelWithString: (NSString*) string
{
	NSTextField *field = [NSTextField wrappingLabelWithString: string];

	[field setSelectable: NO];
	[field setFont: [NSFont systemFontOfSize: [NSFont systemFontSize]]];

	return field;
}

- (void) buildPanel
{
	const CGFloat contentWidth = kPanelWidth - kMargin * 2.0;
	const CGFloat textWidth    = contentWidth - kQRSize - kMargin;

	// ---- supporting this fork ------------------------------------------
	NSTextField *heading = [NSTextField labelWithString:
		NSLocalizedString( @"Support Disk Inventory Next", @"donation panel heading" )];
	[heading setFont: [NSFont boldSystemFontOfSize: [NSFont systemFontSize] + 2.0]];

	NSTextField *blurb = [self labelWithString:
		NSLocalizedString( @"Disk Inventory Next is free software, developed in spare time. "
						   @"If you find it useful, you can support it with a donation to "
						   @"this address on any EVM-compatible chain.",
						   @"donation panel explanation" )];
	[blurb setPreferredMaxLayoutWidth: textWidth];

	//Monospaced, so the address can be read character by character and compared
	//against what a wallet shows. Selectable as well as copyable: someone who
	//distrusts the button can select it by hand.
	_addressField = [NSTextField labelWithString: kDonationAddress];
	[_addressField setFont: [NSFont monospacedSystemFontOfSize: 11.0 weight: NSFontWeightRegular]];
	[_addressField setSelectable: YES];
	[_addressField setPreferredMaxLayoutWidth: contentWidth];
	[[_addressField cell] setWraps: YES];
	[_addressField setUsesSingleLineMode: NO];
	[_addressField setMaximumNumberOfLines: 0];

	_copyButton = [NSButton buttonWithTitle: NSLocalizedString( @"Copy Address", @"donation panel button" )
									 target: self
									 action: @selector(copyAddress:)];

	NSImageView *qrView = [[NSImageView alloc] initWithFrame: NSMakeRect( 0.0, 0.0, kQRSize, kQRSize )];
	[qrView setImage: [self qrCodeImageOfSize: kQRSize * 2.0]];
	[qrView setImageScaling: NSImageScaleProportionallyUpOrDown];
	[qrView setToolTip: kDonationAddress];
	//the code is the address; a reader should hear that rather than "image"
	[qrView setAccessibilityLabel:
		[NSString stringWithFormat: NSLocalizedString( @"QR code for the donation address %@",
													   @"accessibility" ), kDonationAddress]];

	// ---- supporting the original author --------------------------------
	NSBox *separator = [[NSBox alloc] initWithFrame: NSZeroRect];
	[separator setBoxType: NSBoxSeparator];

	NSTextField *forkNote = [self labelWithString:
		NSLocalizedString( @"Disk Inventory Next is a fork of Disk Inventory X by Tjark Derlien, "
						   @"who wrote most of the code it is built on. Donations on his website "
						   @"go to him and not to this fork.",
						   @"donation panel, about the original author" )];
	[forkNote setPreferredMaxLayoutWidth: contentWidth];
	[forkNote setTextColor: [NSColor secondaryLabelColor]];
	[forkNote setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];

	NSButton *authorButton =
		[NSButton buttonWithTitle: NSLocalizedString( @"Support the Original Author…",
													  @"donation panel button" )
						   target: self
						   action: @selector(visitOriginalAuthorSite:)];

	// ---- dismissal -----------------------------------------------------
	NSButton *dontShow = [NSButton checkboxWithTitle:
		NSLocalizedString( @"Don't show again", @"donation panel checkbox" )
										  target: nil action: NULL];
	[dontShow bind: NSValueBinding
		  toObject: [NSUserDefaultsController sharedUserDefaultsController]
	   withKeyPath: [@"values." stringByAppendingString: DontShowDonationMessage]
		   options: nil];

	NSButton *closeButton = [NSButton buttonWithTitle: NSLocalizedString( @"Close", @"" )
											   target: self
											   action: @selector(closePanel:)];
	[closeButton setKeyEquivalent: @"\r"];

	// ---- lay it out ----------------------------------------------------
	//The address sits on its own full-width row rather than beside the QR code.
	//In the column next to it there is not quite room for 42 monospaced
	//characters, and it wrapped mid-address — which is how a transcription error
	//starts.
	NSStackView *addressColumn = [NSStackView stackViewWithViews: @[ blurb ]];
	[addressColumn setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[addressColumn setAlignment: NSLayoutAttributeLeading];
	[addressColumn setSpacing: 8.0];

	NSStackView *topRow = [NSStackView stackViewWithViews: @[ qrView, addressColumn ]];
	[topRow setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[topRow setAlignment: NSLayoutAttributeTop];
	[topRow setSpacing: kMargin];

	NSStackView *authorRow = [NSStackView stackViewWithViews: @[ forkNote, authorButton ]];
	[authorRow setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[authorRow setAlignment: NSLayoutAttributeLeading];
	[authorRow setSpacing: 8.0];

	NSStackView *footer = [NSStackView stackViewWithViews: @[ dontShow, closeButton ]];
	[footer setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[footer setSpacing: kMargin];

	//The window title already says this, so the panel does not repeat it.
	(void) heading;

	NSStackView *content = [NSStackView stackViewWithViews:
		@[ topRow, _addressField, _copyButton, separator, authorRow, footer ]];
	[content setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[content setAlignment: NSLayoutAttributeLeading];
	[content setSpacing: 14.0];
	[content setEdgeInsets: NSEdgeInsetsMake( kMargin, kMargin, kMargin, kMargin )];

	[qrView setTranslatesAutoresizingMaskIntoConstraints: NO];
	[NSLayoutConstraint activateConstraints: @[
		[[qrView widthAnchor] constraintEqualToConstant: kQRSize],
		[[qrView heightAnchor] constraintEqualToConstant: kQRSize],
		[[separator widthAnchor] constraintEqualToAnchor: [content widthAnchor] constant: -kMargin * 2.0],
		[[content widthAnchor] constraintEqualToConstant: kPanelWidth],
	]];

	const NSSize fitting = [content fittingSize];

	_panel = [[NSPanel alloc] initWithContentRect: NSMakeRect( 0.0, 0.0, fitting.width, fitting.height )
										styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
										  backing: NSBackingStoreBuffered
											defer: YES];

	[_panel setTitle: NSLocalizedString( @"Support Disk Inventory Next", @"donation panel heading" )];
	[_panel setReleasedWhenClosed: NO];
	[_panel setWorksWhenModal: YES];
	[_panel setContentView: content];
}

#pragma mark --------actions-----------------

- (IBAction) copyAddress: (id) sender
{
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

	[pasteboard clearContents];
	[pasteboard setString: kDonationAddress forType: NSPasteboardTypeString];

	//confirm it went somewhere, since a silent copy of something this
	//consequential invites a second and third click
	[_copyButton setTitle: NSLocalizedString( @"Copied", @"donation panel button, after copying" )];

	__weak DonationPanelController *weakSelf = self;
	dispatch_after( dispatch_time( DISPATCH_TIME_NOW, (int64_t)( 1.5 * NSEC_PER_SEC ) ),
					dispatch_get_main_queue(), ^{
		DonationPanelController *strongSelf = weakSelf;
		[strongSelf->_copyButton setTitle: NSLocalizedString( @"Copy Address",
															  @"donation panel button" )];
	});
}

- (IBAction) visitOriginalAuthorSite: (id) sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: kOriginalAuthorSite]];
}

- (IBAction) closePanel: (id) sender
{
	[_panel close];
}

@end
