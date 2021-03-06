/* HBQueueController

    This file is part of the HandBrake source code.
    Homepage: <http://handbrake.fr/>.
    It may be used under the terms of the GNU General Public License. */

#import "HBQueueController.h"
#import "Controller.h"
#import "HBImageAndTextCell.h"
#import "HBUtilities.h"

#define HB_ROW_HEIGHT_TITLE_ONLY           17.0
#define HB_ROW_HEIGHT_FULL_DESCRIPTION           200.0
// Pasteboard type for or drag operations
#define DragDropSimplePboardType 	@"MyCustomOutlineViewPboardType"

//------------------------------------------------------------------------------------
#pragma mark -
//------------------------------------------------------------------------------------

//------------------------------------------------------------------------------------
// NSMutableAttributedString (HBAdditions)
//------------------------------------------------------------------------------------

@interface NSMutableAttributedString (HBAdditions)
- (void) appendString: (NSString*)aString withAttributes: (NSDictionary *)aDictionary;
@end

@implementation NSMutableAttributedString (HBAdditions)
- (void) appendString: (NSString*)aString withAttributes: (NSDictionary *)aDictionary
{
    NSAttributedString * s = [[[NSAttributedString alloc]
        initWithString: aString
        attributes: aDictionary] autorelease];
    [self appendAttributedString: s];
}
@end


@implementation HBQueueOutlineView

- (void)viewDidEndLiveResize
{
    // Since we disabled calculating row heights during a live resize, force them to
    // recalculate now.
    [self noteHeightOfRowsWithIndexesChanged:
            [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(0, [self numberOfRows])]];
    [super viewDidEndLiveResize];
}



/* This should be for dragging, we take this info from the presets right now */
- (NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)dragRows tableColumns:(NSArray *)tableColumns event:(NSEvent*)dragEvent offset:(NSPointPointer)dragImageOffset
{
    fIsDragging = YES;

    // By default, NSTableView only drags an image of the first column. Change this to
    // drag an image of the queue's icon and desc and action columns.
    NSArray * cols = [NSArray arrayWithObjects: [self tableColumnWithIdentifier:@"desc"], [self tableColumnWithIdentifier:@"icon"],[self tableColumnWithIdentifier:@"action"], nil];
    return [super dragImageForRowsWithIndexes:dragRows tableColumns:cols event:dragEvent offset:dragImageOffset];
}



- (void) mouseDown:(NSEvent *)theEvent
{
    [super mouseDown:theEvent];
	fIsDragging = NO;
}



- (BOOL) isDragging;
{
    return fIsDragging;
}

@end

#pragma mark Toolbar Identifiers
// Toolbar identifiers
static NSString*    HBQueueToolbar                            = @"HBQueueToolbar1";
static NSString*    HBQueueStartCancelToolbarIdentifier       = @"HBQueueStartCancelToolbarIdentifier";
static NSString*    HBQueuePauseResumeToolbarIdentifier       = @"HBQueuePauseResumeToolbarIdentifier";

#pragma mark -

@implementation HBQueueController

//------------------------------------------------------------------------------------
// init
//------------------------------------------------------------------------------------
- (id)init
{
    if (self = [super initWithWindowNibName:@"Queue"])
    {
        // NSWindowController likes to lazily load its window nib. Since this
        // controller tries to touch the outlets before accessing the window, we
        // need to force it to load immadiately by invoking its accessor.
        //
        // If/when we switch to using bindings, this can probably go away.
        [self window];

        // Our defaults
        [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
            @"NO",      @"QueueWindowIsOpen",
            @"NO",      @"QueueShowsDetail",
            @"YES",     @"QueueShowsJobsAsGroups",
            nil]];

        fJobGroups = [[NSMutableArray arrayWithCapacity:0] retain];

        [self initStyles];
    }

    return self;
}

- (void)setQueueArray: (NSMutableArray *)QueueFileArray
{
    [fJobGroups setArray:QueueFileArray];
    fIsDragging = NO; 
    /* First stop any timer working now */
    //[self stopAnimatingCurrentJobGroupInQueue];
    [fOutlineView reloadData];
    
    
    
    /* lets get the stats on the status of the queue array */
    
    fPendingCount = 0;
    fCompletedCount = 0;
    fCanceledCount = 0;
    fWorkingCount = 0;
    
    /* We use a number system to set the encode status of the queue item
     * in controller.mm
     * 0 == already encoded
     * 1 == is being encoded
     * 2 == is yet to be encoded
     * 3 == cancelled
     */
	int i = 0;
    NSDictionary *thisQueueDict = nil;
	for(id tempObject in fJobGroups)
	{
		thisQueueDict = tempObject;
		if ([[thisQueueDict objectForKey:@"Status"] intValue] == 0) // Completed
		{
			fCompletedCount++;	
		}
		if ([[thisQueueDict objectForKey:@"Status"] intValue] == 1) // being encoded
		{
			fWorkingCount++;
            /* we have an encoding job so, lets start the animation timer */
            if ([thisQueueDict objectForKey:@"EncodingPID"] && [[thisQueueDict objectForKey:@"EncodingPID"] intValue] == pidNum)
            {
                fEncodingQueueItem = i;
            }
		}
        if ([[thisQueueDict objectForKey:@"Status"] intValue] == 2) // pending		
        {
			fPendingCount++;
		}
        if ([[thisQueueDict objectForKey:@"Status"] intValue] == 3) // cancelled		
        {
			fCanceledCount++;
		}
		i++;
	}
    
    /* Set the queue status field in the queue window */
    NSMutableString * string;
    if (fPendingCount == 0)
    {
        string = [NSMutableString stringWithFormat: NSLocalizedString( @"No encode pending", @"" )];
    }
    else if (fPendingCount == 1)
    {
        string = [NSMutableString stringWithFormat: NSLocalizedString( @"%d encode pending", @"" ), fPendingCount];
    }
    else
    {
        string = [NSMutableString stringWithFormat: NSLocalizedString( @"%d encodes pending", @"" ), fPendingCount];
    }
    [fQueueCountField setStringValue:string];
    
}

/* This method sets the status string in the queue window
 * and is called from Controller.mm (fHBController)
 * instead of running another timer here polling libhb
 * for encoding status
 */
- (void)setQueueStatusString: (NSString *)statusString
{
    
    [fProgressTextField setStringValue:statusString];
    
}

//------------------------------------------------------------------------------------
// dealloc
//------------------------------------------------------------------------------------
- (void)dealloc
{
    // clear the delegate so that windowWillClose is not attempted
    if( [[self window] delegate] == self )
        [[self window] setDelegate:nil];

    [fJobGroups release];

    [fSavedExpandedItems release];
    [fSavedSelectedItems release];

    [ps release];
    [detailAttr release];
    [detailBoldAttr release];
    [titleAttr release];
    [shortHeightAttr release];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

//------------------------------------------------------------------------------------
// Receive HB handle
//------------------------------------------------------------------------------------
- (void)setHandle: (hb_handle_t *)handle
{
    fQueueEncodeLibhb = handle;
}

//------------------------------------------------------------------------------------
// Receive HBController
//------------------------------------------------------------------------------------
- (void)setHBController: (HBController *)controller
{
    fHBController = controller;
}

- (void)setPidNum: (int)myPidnum
{
    pidNum = myPidnum;
    [HBUtilities writeToActivityLog: "HBQueueController : My Pidnum is %d", pidNum];
}

#pragma mark -

//------------------------------------------------------------------------------------
// Displays and brings the queue window to the front
//------------------------------------------------------------------------------------
- (IBAction) showQueueWindow: (id)sender
{
    [self showWindow:sender];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"QueueWindowIsOpen"];
    [self startAnimatingCurrentWorkingEncodeInQueue];
}



//------------------------------------------------------------------------------------
// awakeFromNib
//------------------------------------------------------------------------------------
- (void)awakeFromNib
{
    [self setupToolbar];

    if( ![[self window] setFrameUsingName:@"Queue"] )
        [[self window] center];
    [self setWindowFrameAutosaveName:@"Queue"];

    /* lets setup our queue list outline view for drag and drop here */
    [fOutlineView registerForDraggedTypes: [NSArray arrayWithObject:DragDropSimplePboardType] ];
    [fOutlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
    [fOutlineView setVerticalMotionCanBeginDrag: YES];


    // Don't allow autoresizing of main column, else the "delete" column will get
    // pushed out of view.
    [fOutlineView setAutoresizesOutlineColumn: NO];

#if HB_OUTLINE_METRIC_CONTROLS
    [fIndentation setHidden: NO];
    [fSpacing setHidden: NO];
    [fIndentation setIntegerValue:[fOutlineView indentationPerLevel]];  // debug
    [fSpacing setIntegerValue:3];       // debug
#endif

    // Show/hide UI elements
    fCurrentJobPaneShown = NO;     // it's shown in the nib

}


//------------------------------------------------------------------------------------
// windowWillClose
//------------------------------------------------------------------------------------
- (void)windowWillClose:(NSNotification *)aNotification
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"QueueWindowIsOpen"];
    [self stopAnimatingCurrentJobGroupInQueue];
}

#pragma mark Toolbar

//------------------------------------------------------------------------------------
// setupToolbar
//------------------------------------------------------------------------------------
- (void)setupToolbar
{
    // Create a new toolbar instance, and attach it to our window
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier: HBQueueToolbar] autorelease];

    // Set up toolbar properties: Allow customization, give a default display mode, and remember state in user defaults
    [toolbar setAllowsUserCustomization: YES];
    [toolbar setAutosavesConfiguration: YES];
    [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];

    // We are the delegate
    [toolbar setDelegate: self];

    // Attach the toolbar to our window
    [[self window] setToolbar:toolbar];
}

//------------------------------------------------------------------------------------
// toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
//------------------------------------------------------------------------------------
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSString *)itemIdentifier
        willBeInsertedIntoToolbar:(BOOL)flag
{
    // Required delegate method: Given an item identifier, this method returns an item.
    // The toolbar will use this method to obtain toolbar items that can be displayed
    // in the customization sheet, or in the toolbar itself.

    NSToolbarItem *toolbarItem = nil;

    if ([itemIdentifier isEqual: HBQueueStartCancelToolbarIdentifier])
    {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier] autorelease];

        // Set the text label to be displayed in the toolbar and customization palette
        [toolbarItem setLabel: @"Start"];
        [toolbarItem setPaletteLabel: @"Start/Cancel"];

        // Set up a reasonable tooltip, and image
        [toolbarItem setToolTip: @"Start Encoding"];
        [toolbarItem setImage: [NSImage imageNamed: @"encode"]];

        // Tell the item what message to send when it is clicked
        [toolbarItem setTarget: self];
        [toolbarItem setAction: @selector(toggleStartCancel:)];
    }

    if ([itemIdentifier isEqual: HBQueuePauseResumeToolbarIdentifier])
    {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier] autorelease];

        // Set the text label to be displayed in the toolbar and customization palette
        [toolbarItem setLabel: @"Pause"];
        [toolbarItem setPaletteLabel: @"Pause/Resume"];

        // Set up a reasonable tooltip, and image
        [toolbarItem setToolTip: @"Pause Encoding"];
        [toolbarItem setImage: [NSImage imageNamed: @"pauseencode"]];

        // Tell the item what message to send when it is clicked
        [toolbarItem setTarget: self];
        [toolbarItem setAction: @selector(togglePauseResume:)];
    }

    return toolbarItem;
}

//------------------------------------------------------------------------------------
// toolbarDefaultItemIdentifiers:
//------------------------------------------------------------------------------------
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar
{
    // Required delegate method: Returns the ordered list of items to be shown in the
    // toolbar by default.

    return [NSArray arrayWithObjects:
        HBQueueStartCancelToolbarIdentifier,
        HBQueuePauseResumeToolbarIdentifier,
        nil];
}

//------------------------------------------------------------------------------------
// toolbarAllowedItemIdentifiers:
//------------------------------------------------------------------------------------
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar
{
    // Required delegate method: Returns the list of all allowed items by identifier.
    // By default, the toolbar does not assume any items are allowed, even the
    // separator. So, every allowed item must be explicitly listed.

    return [NSArray arrayWithObjects:
        HBQueueStartCancelToolbarIdentifier,
        HBQueuePauseResumeToolbarIdentifier,
        NSToolbarCustomizeToolbarItemIdentifier,
        NSToolbarFlexibleSpaceItemIdentifier,
        NSToolbarSpaceItemIdentifier,
        NSToolbarSeparatorItemIdentifier,
        nil];
}

//------------------------------------------------------------------------------------
// validateToolbarItem:
//------------------------------------------------------------------------------------
- (BOOL) validateToolbarItem: (NSToolbarItem *) toolbarItem
{
    // Optional method: This message is sent to us since we are the target of some
    // toolbar item actions.

    if (!fQueueEncodeLibhb) return NO;

    BOOL enable = NO;

    hb_state_t s;
    hb_get_state2 (fQueueEncodeLibhb, &s);

    if ([[toolbarItem itemIdentifier] isEqual: HBQueueStartCancelToolbarIdentifier])
    {
        if ((s.state == HB_STATE_PAUSED) || (s.state == HB_STATE_WORKING) || (s.state == HB_STATE_MUXING))
        {
            enable = YES;
            [toolbarItem setImage:[NSImage imageNamed: @"stopencode"]];
            [toolbarItem setLabel: @"Stop"];
            [toolbarItem setToolTip: @"Stop Encoding"];
        }

        else if (fPendingCount > 0)
        {
            enable = YES;
            [toolbarItem setImage:[NSImage imageNamed: @"encode"]];
            [toolbarItem setLabel: @"Start"];
            [toolbarItem setToolTip: @"Start Encoding"];
        }

        else
        {
            enable = NO;
            [toolbarItem setImage:[NSImage imageNamed: @"encode"]];
            [toolbarItem setLabel: @"Start"];
            [toolbarItem setToolTip: @"Start Encoding"];
        }
    }

    if ([[toolbarItem itemIdentifier] isEqual: HBQueuePauseResumeToolbarIdentifier])
    {
        if (s.state == HB_STATE_PAUSED)
        {
            enable = YES;
            [toolbarItem setImage:[NSImage imageNamed: @"encode"]];
            [toolbarItem setLabel: @"Resume"];
            [toolbarItem setToolTip: @"Resume Encoding"];
       }

        else if ((s.state == HB_STATE_WORKING) || (s.state == HB_STATE_MUXING))
        {
            enable = YES;
            [toolbarItem setImage:[NSImage imageNamed: @"pauseencode"]];
            [toolbarItem setLabel: @"Pause"];
            [toolbarItem setToolTip: @"Pause Encoding"];
        }
        else
        {
            enable = NO;
            [toolbarItem setImage:[NSImage imageNamed: @"pauseencode"]];
            [toolbarItem setLabel: @"Pause"];
            [toolbarItem setToolTip: @"Pause Encoding"];
        }
    }

    return enable;
}

#pragma mark -


#pragma mark Queue Item Controls
//------------------------------------------------------------------------------------
// Delete encodes from the queue window and accompanying array
// Also handling first cancelling the encode if in fact its currently encoding.
//------------------------------------------------------------------------------------
- (IBAction)removeSelectedQueueItem: (id)sender
{
    NSIndexSet * selectedRows = [fOutlineView selectedRowIndexes];
    NSUInteger row = [selectedRows firstIndex];
    if( row == NSNotFound )
        return;
    /* if this is a currently encoding job, we need to be sure to alert the user,
     * to let them decide to cancel it first, then if they do, we can come back and
     * remove it */
    
    if ([[[fJobGroups objectAtIndex:row] objectForKey:@"Status"] integerValue] == 1)
    {
       /* We pause the encode here so that it doesn't finish right after and then
        * screw up the sync while the window is open
        */
       [fHBController Pause:NULL];
         NSString * alertTitle = [NSString stringWithFormat:NSLocalizedString(@"Stop This Encode and Remove It ?", nil)];
        // Which window to attach the sheet to?
        NSWindow * docWindow = nil;
        if ([sender respondsToSelector: @selector(window)])
            docWindow = [sender window];
        
        
        NSBeginCriticalAlertSheet(
                                  alertTitle,
                                  NSLocalizedString(@"Keep Encoding", nil),
                                  nil,
                                  NSLocalizedString(@"Stop Encoding and Delete", nil),
                                  docWindow, self,
                                  nil, @selector(didDimissCancelCurrentJob:returnCode:contextInfo:), nil,
                                  NSLocalizedString(@"Your movie will be lost if you don't continue encoding.", nil));
        
        // didDimissCancelCurrentJob:returnCode:contextInfo: will be called when the dialog is dismissed
    }
    else
    { 
    /* since we are not a currently encoding item, we can just be removed */
            [fHBController removeQueueFileItem:row];
    }
}

- (void) didDimissCancelCurrentJob: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (void *)contextInfo
{
    /* We resume encoding and perform the appropriate actions 
     * Note: Pause: is a toggle type method based on hb's current
     * state, if it paused, it will resume encoding and vice versa.
     * In this case, we are paused from the calling window, so calling
     * [fHBController Pause:NULL]; Again will resume encoding
     */
    [fHBController Pause:NULL];
    if (returnCode == NSAlertOtherReturn)
    {
        /* We need to save the currently encoding item number first */
        int encodingItemToRemove = fEncodingQueueItem;
        /* Since we are encoding, we need to let fHBController Cancel this job
         * upon which it will move to the next one if there is one
         */
        [fHBController doCancelCurrentJob];
        /* Now, we can go ahead and remove the job we just cancelled since
         * we have its item number from above
         */
        [fHBController removeQueueFileItem:encodingItemToRemove];
    }
    
}

//------------------------------------------------------------------------------------
// Show the finished encode in the finder
//------------------------------------------------------------------------------------
- (IBAction)revealSelectedQueueItem: (id)sender
{
    NSIndexSet * selectedRows = [fOutlineView selectedRowIndexes];
    NSInteger row = [selectedRows firstIndex];
    if (row != NSNotFound)
    {
        while (row != NSNotFound)
        {
           NSMutableDictionary *queueItemToOpen = [fOutlineView itemAtRow: row];
         [[NSWorkspace sharedWorkspace] selectFile:[queueItemToOpen objectForKey:@"DestinationPath"] inFileViewerRootedAtPath:nil];

            row = [selectedRows indexGreaterThanIndex: row];
        }
    }
}


//------------------------------------------------------------------------------------
// Starts or cancels the processing of jobs depending on the current state
//------------------------------------------------------------------------------------
- (IBAction)toggleStartCancel: (id)sender
{
    if (!fQueueEncodeLibhb) return;

    hb_state_t s;
    hb_get_state2 (fQueueEncodeLibhb, &s);

    if ((s.state == HB_STATE_PAUSED) || (s.state == HB_STATE_WORKING) || (s.state == HB_STATE_MUXING))
        [fHBController Cancel: fQueuePane]; // sender == fQueuePane so that warning alert shows up on queue window

    else if (fPendingCount > 0)
        [fHBController Rip: NULL];
}

//------------------------------------------------------------------------------------
// Toggles the pause/resume state of libhb
//------------------------------------------------------------------------------------
- (IBAction)togglePauseResume: (id)sender
{
    if (!fQueueEncodeLibhb) return;
    
    hb_state_t s;
    hb_get_state2 (fQueueEncodeLibhb, &s);
    
    if (s.state == HB_STATE_PAUSED)
    {
        hb_resume (fQueueEncodeLibhb);
        [self startAnimatingCurrentWorkingEncodeInQueue];
    }
    else if ((s.state == HB_STATE_WORKING) || (s.state == HB_STATE_MUXING))
    {
        hb_pause (fQueueEncodeLibhb);
        [self stopAnimatingCurrentJobGroupInQueue];
    }
}


//------------------------------------------------------------------------------------
// Send the selected queue item back to the main window for rescan and possible edit.
//------------------------------------------------------------------------------------
- (IBAction)editSelectedQueueItem: (id)sender
{
    NSIndexSet * selectedRows = [fOutlineView selectedRowIndexes];
    NSUInteger row = [selectedRows firstIndex];
    if( row == NSNotFound )
        return;
    /* if this is a currently encoding job, we need to be sure to alert the user,
     * to let them decide to cancel it first, then if they do, we can come back and
     * remove it */
    
    if ([[[fJobGroups objectAtIndex:row] objectForKey:@"Status"] integerValue] == 1)
    {
       /* We pause the encode here so that it doesn't finish right after and then
        * screw up the sync while the window is open
        */
       [fHBController Pause:NULL];
         NSString * alertTitle = [NSString stringWithFormat:NSLocalizedString(@"Stop This Encode and Remove It ?", nil)];
        // Which window to attach the sheet to?
        NSWindow * docWindow = nil;
        if ([sender respondsToSelector: @selector(window)])
            docWindow = [sender window];
        
        
        NSBeginCriticalAlertSheet(
                                  alertTitle,
                                  NSLocalizedString(@"Keep Encoding", nil),
                                  nil,
                                  NSLocalizedString(@"Stop Encoding and Delete", nil),
                                  docWindow, self,
                                  nil, @selector(didDimissCancelCurrentJob:returnCode:contextInfo:), nil,
                                  NSLocalizedString(@"Your movie will be lost if you don't continue encoding.", nil));
        
    }
    else
    { 
    /* since we are not a currently encoding item, we can just be cancelled */
    [fHBController rescanQueueItemToMainWindow:[[fJobGroups objectAtIndex:row] objectForKey:@"SourcePath"]
                                  scanTitleNum:[[[fJobGroups objectAtIndex:row] objectForKey:@"TitleNumber"] integerValue]
                             selectedQueueItem:row];
    
    }
}


#pragma mark -
#pragma mark Animate Endcoding Item




//------------------------------------------------------------------------------------
// Starts animating the job icon of the currently processing job in the queue outline
// view.
//------------------------------------------------------------------------------------
- (void) startAnimatingCurrentWorkingEncodeInQueue
{
    if (!fAnimationTimer)
        fAnimationTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0/12.0     // 1/12 because there are 6 images in the animation cycle
                target:self
                selector:@selector(animateWorkingEncodeInQueue:)
                userInfo:nil
                repeats:YES] retain];
}

//------------------------------------------------------------------------------------
// If a job is currently processing, its job icon in the queue outline view is
// animated to its next state.
//------------------------------------------------------------------------------------
- (void) animateWorkingEncodeInQueue:(NSTimer*)theTimer
{
    if (fWorkingCount > 0)
    {
        fAnimationIndex++;
        fAnimationIndex %= 6;   // there are 6 animation images; see outlineView:objectValueForTableColumn:byItem: below.
        [self animateWorkingEncodeIconInQueue];
    }
}

/* We need to make sure we denote only working encodes even for multiple instances */
- (void) animateWorkingEncodeIconInQueue
{
    NSInteger row = fEncodingQueueItem; /// need to set to fEncodingQueueItem
    NSInteger col = [fOutlineView columnWithIdentifier: @"icon"];
    if (row != -1 && col != -1)
    {
        NSRect frame = [fOutlineView frameOfCellAtColumn:col row:row];
        [fOutlineView setNeedsDisplayInRect: frame];
    }
}

//------------------------------------------------------------------------------------
// Stops animating the job icon of the currently processing job in the queue outline
// view.
//------------------------------------------------------------------------------------
- (void) stopAnimatingCurrentJobGroupInQueue
{
    if (fAnimationTimer && [fAnimationTimer isValid])
    {
        [fAnimationTimer invalidate];
        [fAnimationTimer release];
        fAnimationTimer = nil;
    }
}


#pragma mark -

- (void)moveObjectsInArray:(NSMutableArray *)array fromIndexes:(NSIndexSet *)indexSet toIndex:(NSUInteger)insertIndex
{
    NSUInteger index = [indexSet lastIndex];
    NSUInteger aboveInsertIndexCount = 0;

    while (index != NSNotFound)
    {
        NSUInteger removeIndex;

        if (index >= insertIndex)
        {
            removeIndex = index + aboveInsertIndexCount;
            aboveInsertIndexCount++;
        }
        else
        {
            removeIndex = index;
            insertIndex--;
        }

        id object = [[array objectAtIndex:removeIndex] retain];
        [array removeObjectAtIndex:removeIndex];
        [array insertObject:object atIndex:insertIndex];
        [object release];

        index = [indexSet indexLessThanIndex:index];
    }
}


#pragma mark -
#pragma mark NSOutlineView delegate


- (id)outlineView:(NSOutlineView *)fOutlineView child:(NSInteger)index ofItem:(id)item
{
    if (item == nil)
        return [fJobGroups objectAtIndex:index];

    // We are only one level deep, so we can't be asked about children
    NSAssert (NO, @"HBQueueController outlineView:child:ofItem: can't handle nested items.");
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)fOutlineView isItemExpandable:(id)item
{
    // Our outline view has no levels, but we can still expand every item. Doing so
    // just makes the row taller. See heightOfRowByItem below.
    return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
    // Our outline view has no levels, but we can still expand every item. Doing so
    // just makes the row taller. See heightOfRowByItem below.
return ![(HBQueueOutlineView*)outlineView isDragging];
}

- (NSInteger)outlineView:(NSOutlineView *)fOutlineView numberOfChildrenOfItem:(id)item
{
    // Our outline view has no levels, so number of children will be zero for all
    // top-level items.
    if (item == nil)
        return [fJobGroups count];
    else
        return 0;
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    id item = [[notification userInfo] objectForKey:@"NSObject"];
    NSInteger row = [fOutlineView rowForItem:item];
    [fOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(row,1)]];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
    id item = [[notification userInfo] objectForKey:@"NSObject"];
    NSInteger row = [fOutlineView rowForItem:item];
    [fOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(row,1)]];
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
    if ([outlineView isItemExpanded: item])
    {
        // It is important to use a constant value when calculating the height. Querying the tableColumn width will not work, since it dynamically changes as the user resizes -- however, we don't get a notification that the user "did resize" it until after the mouse is let go. We use the latter as a hook for telling the table that the heights changed. We must return the same height from this method every time, until we tell the table the heights have changed. Not doing so will quicly cause drawing problems.
        NSTableColumn *tableColumnToWrap = (NSTableColumn *) [[outlineView tableColumns] objectAtIndex:1];
        NSInteger columnToWrap = [outlineView.tableColumns indexOfObject:tableColumnToWrap];
        
        // Grab the fully prepared cell with our content filled in. Note that in IB the cell's Layout is set to Wraps.
        NSCell *cell = [outlineView preparedCellAtColumn:columnToWrap row:[outlineView rowForItem:item]];
        
        // See how tall it naturally would want to be if given a restricted with, but unbound height
        NSRect constrainedBounds = NSMakeRect(0, 0, [tableColumnToWrap width], CGFLOAT_MAX);
        NSSize naturalSize = [cell cellSizeForBounds:constrainedBounds];
        
        // Make sure we have a minimum height -- use the table's set height as the minimum.
        if (naturalSize.height > [outlineView rowHeight])
            return naturalSize.height;
        else
            return [outlineView rowHeight];
    }
    else
    {
        return HB_ROW_HEIGHT_TITLE_ONLY;
    }
}

- (void)initStyles
{
    // Attributes
    ps = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] retain];
    [ps setHeadIndent: 40.0];
    [ps setParagraphSpacing: 1.0];
    [ps setTabStops:[NSArray array]];    // clear all tabs
    [ps addTabStop: [[[NSTextTab alloc] initWithType: NSLeftTabStopType location: 20.0] autorelease]];

    detailAttr = [[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                ps, NSParagraphStyleAttributeName,
                                nil] retain];

    detailBoldAttr = [[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont boldSystemFontOfSize:10.0], NSFontAttributeName,
                                    ps, NSParagraphStyleAttributeName,
                                    nil] retain];

    titleAttr = [[NSDictionary dictionaryWithObjectsAndKeys:
                               [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
                               ps, NSParagraphStyleAttributeName,
                               nil] retain];

    shortHeightAttr = [[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont systemFontOfSize:2.0], NSFontAttributeName,
                                     nil] retain];
}

- (id)outlineView:(NSOutlineView *)fOutlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    if ([[tableColumn identifier] isEqualToString:@"desc"])
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        /* Below should be put into a separate method but I am way too f'ing lazy right now */
        NSMutableAttributedString * finalString = [[NSMutableAttributedString alloc] initWithString: @""];
        
        /* First line, we should strip the destination path and just show the file name and add the title num and chapters (if any) */
        NSString * summaryInfo;
        
        NSString * titleString = [NSString stringWithFormat:@"Title %d", [[item objectForKey:@"TitleNumber"] intValue]];
        
        NSString * startStopString = @"";
        if ([[item objectForKey:@"fEncodeStartStop"] intValue] == 0)
        {
            /* Start Stop is chapters */
            startStopString = ([[item objectForKey:@"ChapterStart"] intValue] == [[item objectForKey:@"ChapterEnd"] intValue]) ?
            [NSString stringWithFormat:@"Chapter %d", [[item objectForKey:@"ChapterStart"] intValue]] :
            [NSString stringWithFormat:@"Chapters %d through %d", [[item objectForKey:@"ChapterStart"] intValue], [[item objectForKey:@"ChapterEnd"] intValue]];
        }
        else if ([[item objectForKey:@"fEncodeStartStop"] intValue] == 1)
        {
            /* Start Stop is seconds */
            startStopString = [NSString stringWithFormat:@"Seconds %d through %d", [[item objectForKey:@"StartSeconds"] intValue], [[item objectForKey:@"StartSeconds"] intValue] + [[item objectForKey:@"StopSeconds"] intValue]];
        }
        else if ([[item objectForKey:@"fEncodeStartStop"] intValue] == 2)
        {
            /* Start Stop is Frames */
            startStopString = [NSString stringWithFormat:@"Frames %d through %d", [[item objectForKey:@"StartFrame"] intValue], [[item objectForKey:@"StartFrame"] intValue] + [[item objectForKey:@"StopFrame"] intValue]];
        }
        
        NSString * passesString = @"";
        /* check to see if our first subtitle track is Foreign Language Search, in which case there is an in depth scan */
        if ([[item objectForKey:@"SubtitleList"] count] && [[[[item objectForKey:@"SubtitleList"] objectAtIndex:0] objectForKey:@"keySubTrackIndex"] intValue] == -1)
        {
          passesString = [passesString stringByAppendingString:@"1 Foreign Language Search Pass - "];
        }
        if ([[item objectForKey:@"VideoTwoPass"] intValue] == 0)
        {
            passesString = [passesString stringByAppendingString:@"1 Video Pass"];
        }
        else
        {
            if ([[item objectForKey:@"VideoTurboTwoPass"] intValue] == 1)
            {
                passesString = [passesString stringByAppendingString:@"2 Video Passes First Turbo"];
            }
            else
            {
                passesString = [passesString stringByAppendingString:@"2 Video Passes"];
            }
        }
        
        [finalString appendString:[NSString stringWithFormat:@"%@", [item objectForKey:@"SourceName"]] withAttributes:titleAttr];
        
        /* lets add the output file name to the title string here */
        NSString * outputFilenameString = [[item objectForKey:@"DestinationPath"] lastPathComponent];
        
        summaryInfo = [NSString stringWithFormat: @" (%@, %@, %@) -> %@", titleString, startStopString, passesString, outputFilenameString];
        
        [finalString appendString:[NSString stringWithFormat:@"%@\n", summaryInfo] withAttributes:detailAttr];  
        
        // Insert a short-in-height line to put some white space after the title
        [finalString appendString:@"\n" withAttributes:shortHeightAttr];
        // End of Title Stuff
        
        /* Second Line  (Preset Name)*/
        [finalString appendString: @"Preset: " withAttributes:detailBoldAttr];
        [finalString appendString:[NSString stringWithFormat:@"%@\n", [item objectForKey:@"PresetName"]] withAttributes:detailAttr];
        
        /* Third Line  (Format Summary) */
        NSString * audioCodecSummary = @"";	//	This seems to be set by the last track we have available...
        /* Lets also get our audio track detail since we are going through the logic for use later */
		unsigned int ourMaximumNumberOfAudioTracks = [HBController maximumNumberOfAllowedAudioTracks];
		NSMutableArray *audioDetails = [NSMutableArray arrayWithCapacity: ourMaximumNumberOfAudioTracks];
		NSString *base;
		NSString *detailString;
		NSNumber *drc;
        NSNumber *gain;
        BOOL autoPassthruPresent = NO;
		for (unsigned int i = 1; i <= ourMaximumNumberOfAudioTracks; i++) {
			base = [NSString stringWithFormat: @"Audio%d", i];
			if (0 < [[item objectForKey: [base stringByAppendingString: @"Track"]] intValue])
            {
				audioCodecSummary = [NSString stringWithFormat: @"%@", [item objectForKey: [base stringByAppendingString: @"Encoder"]]];
				drc = [item objectForKey: [base stringByAppendingString: @"TrackDRCSlider"]];
                gain = [item objectForKey: [base stringByAppendingString: @"TrackGainSlider"]];
				detailString = [NSString stringWithFormat: @"%@ Encoder: %@ Mixdown: %@ SampleRate: %@(khz) Bitrate: %@(kbps), DRC: %@, Gain: %@",
								[item objectForKey: [base stringByAppendingString: @"TrackDescription"]],
								[item objectForKey: [base stringByAppendingString: @"Encoder"]],
								[item objectForKey: [base stringByAppendingString: @"Mixdown"]],
								[item objectForKey: [base stringByAppendingString: @"Samplerate"]],
								[item objectForKey: [base stringByAppendingString: @"Bitrate"]],
                                (0.0 < [drc floatValue]) ? (NSObject *)drc : (NSObject *)@"Off",
								(0.0 != [gain floatValue]) ? (NSObject *)gain : (NSObject *)@"Off"
								]
                                ;
				[audioDetails addObject: detailString];
                // check if we have an Auto Passthru output track
                if ([[item objectForKey: [NSString stringWithFormat: @"Audio%dEncoder", i]] isEqualToString: @"Auto Passthru"])
                {
                    autoPassthruPresent = YES;
                }
			}
		}
        
        
        NSString * jobFormatInfo;
        if ([[item objectForKey:@"ChapterMarkers"] intValue] == 1)
            jobFormatInfo = [NSString stringWithFormat:@"%@ Container, %@ Video  %@ Audio, Chapter Markers\n", [item objectForKey:@"FileFormat"], [item objectForKey:@"VideoEncoder"], audioCodecSummary];
        else
            jobFormatInfo = [NSString stringWithFormat:@"%@ Container, %@ Video  %@ Audio\n", [item objectForKey:@"FileFormat"], [item objectForKey:@"VideoEncoder"], audioCodecSummary];
        
        
        [finalString appendString: @"Format: " withAttributes:detailBoldAttr];
        [finalString appendString: jobFormatInfo withAttributes:detailAttr];
        
        /* Optional String for muxer options */
        if ([[item objectForKey:@"MuxerOptionsSummary"] length])
        {
            NSString *containerOptions = [NSString stringWithFormat:@"%@",
                                          [item objectForKey:@"MuxerOptionsSummary"]];
            [finalString appendString:@"Container Options: " withAttributes:detailBoldAttr];
            [finalString appendString:containerOptions       withAttributes:detailAttr];
            [finalString appendString:@"\n"                  withAttributes:detailAttr];
        }
        
        /* Fourth Line (Destination Path)*/
        [finalString appendString: @"Destination: " withAttributes:detailBoldAttr];
        [finalString appendString: [item objectForKey:@"DestinationPath"] withAttributes:detailAttr];
        [finalString appendString:@"\n" withAttributes:detailAttr];
        
        /* Fifth Line Picture Details*/
        NSString *pictureInfo = [NSString stringWithFormat:@"%@",
                                 [item objectForKey:@"PictureSettingsSummary"]];
        if ([[item objectForKey:@"PictureKeepRatio"] intValue] == 1)
        {
            pictureInfo = [pictureInfo stringByAppendingString:@" Keep Aspect Ratio"];
        }
        [finalString appendString:@"Picture: " withAttributes:detailBoldAttr];
        [finalString appendString:pictureInfo  withAttributes:detailAttr];
        [finalString appendString:@"\n"        withAttributes:detailAttr];
        
        /* Optional String for Picture Filters */
        if ([[item objectForKey:@"PictureFiltersSummary"] length])
        {
            NSString *pictureFilters = [NSString stringWithFormat:@"%@",
                                        [item objectForKey:@"PictureFiltersSummary"]];
            [finalString appendString:@"Filters: "   withAttributes:detailBoldAttr];
            [finalString appendString:pictureFilters withAttributes:detailAttr];
            [finalString appendString:@"\n"          withAttributes:detailAttr];
        }
        
        /* Sixth Line Video Details*/
        NSString * videoInfo;
        videoInfo = [NSString stringWithFormat:@"Encoder: %@", [item objectForKey:@"VideoEncoder"]];
        
        /* for framerate look to see if we are using vfr detelecine */
        if ([[item objectForKey:@"JobIndexVideoFramerate"] intValue] == 0)
        {
            if ([[item objectForKey:@"VideoFramerateMode"] isEqualToString:@"vfr"])
            {
                /* we are using same as source with vfr detelecine */
                videoInfo = [NSString stringWithFormat:@"%@ Framerate: Same as source (Variable Frame Rate)", videoInfo];
            }
            else
            {
                /* we are using a variable framerate without dropping frames */
                videoInfo = [NSString stringWithFormat:@"%@ Framerate: Same as source (Constant Frame Rate)", videoInfo];
            }
        }
        else
        {
            /* we have a specified, constant framerate */
            if ([[item objectForKey:@"VideoFramerateMode"] isEqualToString:@"pfr"])
            {
            videoInfo = [NSString stringWithFormat:@"%@ Framerate: %@ (Peak Frame Rate)", videoInfo ,[item objectForKey:@"VideoFramerate"]];
            }
            else
            {
            videoInfo = [NSString stringWithFormat:@"%@ Framerate: %@ (Constant Frame Rate)", videoInfo ,[item objectForKey:@"VideoFramerate"]];
            }
        }
        
        if ([[item objectForKey:@"VideoQualityType"] intValue] == 0)// Target Size MB
        {
            videoInfo = [NSString stringWithFormat:@"%@ Target Size: %@(MB) (%d(kbps) abr)", videoInfo ,[item objectForKey:@"VideoTargetSize"],[[item objectForKey:@"VideoAvgBitrate"] intValue]];
        }
        else if ([[item objectForKey:@"VideoQualityType"] intValue] == 1) // ABR
        {
            videoInfo = [NSString stringWithFormat:@"%@ Bitrate: %d(kbps)", videoInfo ,[[item objectForKey:@"VideoAvgBitrate"] intValue]];
        }
        else // CRF
        {
            videoInfo = [NSString stringWithFormat:@"%@ Constant Quality: %.2f", videoInfo ,[[item objectForKey:@"VideoQualitySlider"] floatValue]];
        }
        
        [finalString appendString: @"Video: " withAttributes:detailBoldAttr];
        [finalString appendString: videoInfo withAttributes:detailAttr];
        [finalString appendString:@"\n" withAttributes:detailAttr];
        
        if ([[item objectForKey:@"VideoEncoder"] isEqualToString: @"H.264 (x264)"])
        {
            /* we are using x264 */
            NSString *x264Info = @"";
            if ([[item objectForKey:@"x264UseAdvancedOptions"] intValue])
            {
                // we are using the old advanced panel
                if ([item objectForKey:@"x264Option"] &&
                    [[item objectForKey:@"x264Option"] length])
                {
                    x264Info = [x264Info stringByAppendingString: [item objectForKey:@"x264Option"]];
                }
                else
                {
                    x264Info = [x264Info stringByAppendingString: @"default settings"];
                }
            }
            else
            {
                // we are using the x264 system
                x264Info = [x264Info stringByAppendingString: [NSString stringWithFormat:@"Preset: %@", [item objectForKey:@"x264Preset"]]];
                if ([[item objectForKey:@"x264Tune"] length])
                {
                    x264Info = [x264Info stringByAppendingString: [NSString stringWithFormat:@" - Tune: %@", [item objectForKey:@"x264Tune"]]];
                }
                if ([[item objectForKey:@"x264OptionExtra"] length])
                {
                    x264Info = [x264Info stringByAppendingString: [NSString stringWithFormat:@" - Options: %@", [item objectForKey:@"x264OptionExtra"]]];
                }
                if ([[item objectForKey:@"h264Profile"] length])
                {
                    x264Info = [x264Info stringByAppendingString: [NSString stringWithFormat:@" - Profile: %@", [item objectForKey:@"h264Profile"]]];
                }
                if ([[item objectForKey:@"h264Level"] length])
                {
                    x264Info = [x264Info stringByAppendingString: [NSString stringWithFormat:@" - Level: %@", [item objectForKey:@"h264Level"]]];
                }
            }
            [finalString appendString: @"x264: " withAttributes:detailBoldAttr];
            [finalString appendString: x264Info withAttributes:detailAttr];
            [finalString appendString:@"\n" withAttributes:detailAttr];
        }
        else if (![[item objectForKey:@"VideoEncoder"] isEqualToString: @"VP3 (Theora)"])
        {
            /* we are using libavcodec */
            NSString *lavcInfo = @"";
            if ([item objectForKey:@"lavcOption"] &&
                [[item objectForKey:@"lavcOption"] length])
            {
                lavcInfo = [lavcInfo stringByAppendingString: [item objectForKey:@"lavcOption"]];
            }
            else
            {
                lavcInfo = [lavcInfo stringByAppendingString: @"default settings"];
            }
            [finalString appendString: @"ffmpeg: " withAttributes:detailBoldAttr];
            [finalString appendString: lavcInfo withAttributes:detailAttr];
            [finalString appendString:@"\n" withAttributes:detailAttr];
        }
        
        
        
        
        /* Seventh Line Audio Details*/
        NSEnumerator *audioDetailEnumerator = [audioDetails objectEnumerator];
		NSString *anAudioDetail;
		int audioDetailCount = 0;
		while (nil != (anAudioDetail = [audioDetailEnumerator nextObject])) {
			audioDetailCount++;
			if (0 < [anAudioDetail length]) {
				[finalString appendString: [NSString stringWithFormat: @"Audio Track %d ", audioDetailCount] withAttributes: detailBoldAttr];
				[finalString appendString: anAudioDetail withAttributes: detailAttr];
				[finalString appendString: @"\n" withAttributes: detailAttr];
			}
		}
        
        /* Eigth Line Auto Passthru Details */
        // only print Auto Passthru settings if we have an Auro Passthru output track
        if (autoPassthruPresent == YES)
        {
            NSString *autoPassthruFallback = @"", *autoPassthruCodecs = @"";
            autoPassthruFallback = [autoPassthruFallback stringByAppendingString: [item objectForKey: @"AudioEncoderFallback"]];
            if (0 < [[item objectForKey: @"AudioAllowAACPass"] intValue])
            {
                autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @"AAC"];
            }
            if (0 < [[item objectForKey: @"AudioAllowAC3Pass"] intValue])
            {
                if (0 < [autoPassthruCodecs length])
                {
                    autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @", "];
                }
                autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @"AC3"];
            }
            if (0 < [[item objectForKey: @"AudioAllowDTSHDPass"] intValue])
            {
                if (0 < [autoPassthruCodecs length])
                {
                    autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @", "];
                }
                autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @"DTS-HD"];
            }
            if (0 < [[item objectForKey: @"AudioAllowDTSPass"] intValue])
            {
                if (0 < [autoPassthruCodecs length])
                {
                    autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @", "];
                }
                autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @"DTS"];
            }
            if (0 < [[item objectForKey: @"AudioAllowMP3Pass"] intValue])
            {
                if (0 < [autoPassthruCodecs length])
                {
                    autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @", "];
                }
                autoPassthruCodecs = [autoPassthruCodecs stringByAppendingString: @"MP3"];
            }
            [finalString appendString: @"Auto Passthru Codecs: " withAttributes: detailBoldAttr];
            if (0 < [autoPassthruCodecs length])
            {
                [finalString appendString: autoPassthruCodecs withAttributes: detailAttr];
            }
            else
            {
                [finalString appendString: @"None" withAttributes: detailAttr];
            }
            [finalString appendString: @"\n" withAttributes: detailAttr];
            [finalString appendString: @"Auto Passthru Fallback: " withAttributes: detailBoldAttr];
            [finalString appendString: autoPassthruFallback withAttributes: detailAttr];
            [finalString appendString: @"\n" withAttributes: detailAttr];
        }
        
        /* Ninth Line Subtitle Details */
        
        int i = 0;
        NSEnumerator *enumerator = [[item objectForKey:@"SubtitleList"] objectEnumerator];
        id tempObject;
        while (tempObject = [enumerator nextObject])
        {
            /* remember that index 0 of Subtitles can contain "Foreign Audio Search*/
            [finalString appendString: @"Subtitle: " withAttributes:detailBoldAttr];
            [finalString appendString: [tempObject objectForKey:@"keySubTrackName"] withAttributes:detailAttr];
            if ([[tempObject objectForKey:@"keySubTrackForced"] intValue] == 1)
            {
                [finalString appendString: @" - Forced Only" withAttributes:detailAttr];
            }
            if ([[tempObject objectForKey:@"keySubTrackBurned"] intValue] == 1)
            {
                [finalString appendString: @" - Burned In" withAttributes:detailAttr];
            }
            if ([[tempObject objectForKey:@"keySubTrackDefault"] intValue] == 1)
            {
                [finalString appendString: @" - Default" withAttributes:detailAttr];
            }
            [finalString appendString:@"\n" withAttributes:detailAttr];
            i++;
        }

        [pool release];

        return [finalString autorelease];
    }
    else if ([[tableColumn identifier] isEqualToString:@"icon"])
    {
        if ([[item objectForKey:@"Status"] intValue] == 0)
        {
            return [NSImage imageNamed:@"EncodeComplete"];
        }
        else if ([[item objectForKey:@"Status"] intValue] == 1)
        {
            return [NSImage imageNamed: [NSString stringWithFormat: @"EncodeWorking%d", fAnimationIndex]];
        }
        else if ([[item objectForKey:@"Status"] intValue] == 3)
        {
            return [NSImage imageNamed:@"EncodeCanceled"];
        }
        else
        {
            return [NSImage imageNamed:@"JobSmall"];
        }
        
    }
    else
    {
        return @"";
    }
}
/* This method inserts the proper action icons into the far right of the queue window */
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if ([[tableColumn identifier] isEqualToString:@"desc"])
    {


        // nb: The "desc" column is currently an HBImageAndTextCell. However, we are longer
        // using the image portion of the cell so we could switch back to a regular NSTextFieldCell.

        // Set the image here since the value returned from outlineView:objectValueForTableColumn: didn't specify the image part
        [cell setImage:nil];
    }
    else if ([[tableColumn identifier] isEqualToString:@"action"])
    {
        [cell setEnabled: YES];
        BOOL highlighted = [outlineView isRowSelected:[outlineView rowForItem: item]] && [[outlineView window] isKeyWindow] && ([[outlineView window] firstResponder] == outlineView);
        
        if ([[item objectForKey:@"Status"] intValue] == 0 || ([[item objectForKey:@"Status"] intValue] == 1 && [[item objectForKey:@"EncodingPID"] intValue] != pidNum))
        {
            [cell setAction: @selector(revealSelectedQueueItem:)];
            if (highlighted)
            {
                [cell setImage:[NSImage imageNamed:@"RevealHighlight"]];
                [cell setAlternateImage:[NSImage imageNamed:@"RevealHighlightPressed"]];
            }
            else
                [cell setImage:[NSImage imageNamed:@"Reveal"]];
        }
        else
        {
            
                [cell setAction: @selector(removeSelectedQueueItem:)];
                if (highlighted)
                {
                    [cell setImage:[NSImage imageNamed:@"DeleteHighlight"]];
                    [cell setAlternateImage:[NSImage imageNamed:@"DeleteHighlightPressed"]];
                }
                else
                    [cell setImage:[NSImage imageNamed:@"Delete"]];
   
        }
    }
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayOutlineCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    // By default, the disclosure image gets centered vertically in the cell. We want
    // always at the top.
    if ([outlineView isItemExpanded: item])
        [cell setImagePosition: NSImageAbove];
    else
        [cell setImagePosition: NSImageOnly];
}

#pragma mark -
#pragma mark NSOutlineView delegate (dragging related)

//------------------------------------------------------------------------------------
// NSTableView delegate
//------------------------------------------------------------------------------------


- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
    // Dragging is only allowed of the pending items.
    if ([[[items objectAtIndex:0] objectForKey:@"Status"] integerValue] != 2) // 2 is pending
    {
        return NO;
    }
    
    // Don't retain since this is just holding temporaral drag information, and it is
    //only used during a drag!  We could put this in the pboard actually.
    fDraggedNodes = items;
    
    // Provide data for our custom type, and simple NSStrings.
    [pboard declareTypes:[NSArray arrayWithObjects: DragDropSimplePboardType, nil] owner:self];
    
    // the actual data doesn't matter since DragDropSimplePboardType drags aren't recognized by anyone but us!.
    [pboard setData:[NSData data] forType:DragDropSimplePboardType];
    
    return YES;
}


/* This method is used to validate the drops. */
- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    // Don't allow dropping ONTO an item since they can't really contain any children.
    BOOL isOnDropTypeProposal = index == NSOutlineViewDropOnItemIndex;
    if (isOnDropTypeProposal)
    {
        return NSDragOperationNone;
    }
    
    // Don't allow dropping INTO an item since they can't really contain any children.
    if (item != nil)
    {
        index = [fOutlineView rowForItem: item] + 1;
        item = nil;
    }
    
    // NOTE: Should we allow dropping a pending job *above* the
    // finished or already encoded jobs ?
    // We do not let the user drop a pending job before or *above*
    // already finished or currently encoding jobs.
    if (index <= fEncodingQueueItem)
    {
        return NSDragOperationNone;
        index = MAX (index, fEncodingQueueItem);
	}
    
    [outlineView setDropItem:item dropChildIndex:index];
    return NSDragOperationGeneric;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    NSMutableIndexSet *moveItems = [NSMutableIndexSet indexSet];

    for( id obj in fDraggedNodes )
        [moveItems addIndex:[fJobGroups indexOfObject:obj]];

    // Successful drop, we use moveObjectsInQueueArray:... in fHBController
    // to properly rearrange the queue array, save it to plist and then send it back here.
    // since Controller.mm is handling all queue array manipulation.
    // We *could do this here, but I think we are better served keeping that code together.
    [fHBController moveObjectsInQueueArray:fJobGroups fromIndexes:moveItems toIndex: index];
    return YES;
}


@end
