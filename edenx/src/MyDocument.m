//
//  MyDocument.m
//  orchard
//
//  Created by Guillaume Laurent on 4/13/08.
//  Copyright telegraph-road.org 2008 . All rights reserved.
//

#include <CoreAudio/CoreAudio.h>

#import "MyDocument.h"

#import "PYMIDI.h"

#import "SegmentEditor.h"
#import "SegmentNotationEditor.h"
#import "Player.h"
#import "SMMessage.h"
#import "MIDIReceiver.h"
#import "AppController.h"
#import "Recorder.h"
#import "CoreDataStuff.h"
#import "SegmentCanvas.h"
#import "CompositionController.h"
#import "TracksController.h"
#import "SegmentSelector.h"

#import <CoreAudio/CoreAudioTypes.h>

@interface MyDocument (private)

- (void)setupTempo;
- (void)fillSequence;
- (void)documentIsBeingModified:(NSNotification*)notification;
- (void)compositionControllerContentSet:(NSNotification*)notification;

@end


@implementation MyDocument

- (id)init 
{
    self = [super init];
    if (self != nil) {
        player = [(AppController*)[NSApp delegate] player];
        NewMusicSequence(&sequence);
        documentModifiedSinceLastPlay = YES; // this is a new document, so player needs setup.
        firstDocumentModif = YES;
        
        
        
    }
    return self;
}

- (NSString *)windowNibName 
{
    return @"MyDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController 
{
    [super windowControllerDidLoadNib:windowController];

    // synchronize track list and track canvas scroll views
    [trackListView setSynchronizedScrollView:trackCanvasView];

    [trackCanvasView setHasHorizontalRuler:YES];
    [trackCanvasView setRulersVisible:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentIsBeingModified:) name:NSManagedObjectContextObjectsDidChangeNotification object:[self managedObjectContext]];
    
    [[NSNotificationCenter defaultCenter] addObserver:tracksController selector:@selector(handleMIDIRemoveObject:) name:PYMIDIObjectRemoved object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(compositionControllerContentSet:) name:CompositionControllerContentSet object:compositionController];

    //segmentCanvas.tracksArrayController = tracksController;
    
    NSLog(@"MyDocument windowControllerDidLoadNib - tracksController = %@", tracksController);
    
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    NSLog(@"MyDocument writeToURL");
    return [super writeToURL:absoluteURL ofType:typeName error:outError];
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation originalContentsURL:(NSURL *)absoluteOriginalContentsURL error:(NSError **)outError
{
    NSLog(@"MyDocument writeToURL 2");
    BOOL res = [super writeToURL:absoluteURL ofType:typeName forSaveOperation:saveOperation originalContentsURL:absoluteOriginalContentsURL error:outError];
    if (!res) {
        // code from http://stackoverflow.com/questions/1283960/iphone-core-data-unresolved-error-while-saving/1297157#1297157
        NSLog(@"Failed to save to data store: %@", [*outError localizedDescription]);
        NSArray* detailedErrors = [[*outError userInfo] objectForKey:NSDetailedErrorsKey];
        if(detailedErrors != nil && [detailedErrors count] > 0) {
            for(NSError* detailedError in detailedErrors) {
                NSLog(@"  DetailedError: %@", [detailedError userInfo]);
            }
        }
        else {
            NSLog(@"  %@", [*outError userInfo]);
        }
    }
    
    return res;
}

- (void)setupZoomSlider
{
        
    // attach as observer to Composition.testRowHeight
    //
    NSLog(@"MyDocument:setupZoomSlider adding SegmentCanvas as observer: %@ observing zoomVertical on %@", segmentCanvas, [compositionController content]);
    [[compositionController content] addObserver:segmentCanvas
                                        forKeyPath:@"zoomVertical"
                                           options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld
                                           context:NULL];    


    NSLog(@"MyDocument:setupZoomSlider: adding observer on composition tracks");
    [[compositionController content] addObserver:segmentCanvas
                                      forKeyPath:@"tracks"
                                         options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld
                                         context:NULL];
   
   
//    NSLog(@"MyDocument:windowControllerDidLoadNib: tracksArrayController content : %@ - arrangedObjects : %@",
//          [tracksController content], [tracksController arrangedObjects]);

    segmentCanvas.tracksController = tracksController;
    
    [segmentCanvas addStripLayerForTracks:[tracksController content]];
    [[segmentCanvas segmentSelector] setSegmentArrayController:segmentsController];
}

- (NSManagedObject<Segment>*)createSegmentInTrack:(NSManagedObject<Track>*)track startingAtTime:(double)startTime endingAtTime:(double)endTime
{
    NSManagedObjectContext* managedObjectContext = [self managedObjectContext];
    
    NSEntityDescription* segmentEntity = [NSEntityDescription entityForName:@"Segment" inManagedObjectContext:managedObjectContext];
    
    NSManagedObject<Segment>* newSegment = (NSManagedObject<Segment>*)[[NSManagedObject alloc] initWithEntity:segmentEntity insertIntoManagedObjectContext:nil];
    
//    NSLog(@"createSegmentInTrack : newSegment = %@", newSegment);
    
    // TODO convert to composition time
    newSegment.startTime = [NSNumber numberWithFloat:startTime];
    newSegment.endTime = [NSNumber numberWithFloat:(endTime)];
    
    [managedObjectContext insertObject:newSegment];
    
    // insert segment into its track
    [segmentsController addObject:newSegment];
    
    return newSegment;
}

- (void)deleteSegment:(NSManagedObject<Segment>*)segment
{
    NSManagedObjectContext* managedObjectContext = [self managedObjectContext];

    [managedObjectContext deleteObject:segment];
}

- (IBAction)showPlayBackCursor:(id)sender
{
    // TODO - implement me with a CoreAnim layer
    NSLog(@"showPlayBackCursor : %ld", [sender state]);
    
}

- (IBAction)editSelectedSegmentEventList:(id)sender
{
    NSLog(@"MyDocument:editSelectedSegmentEventList");
    
    if (!segmentEventListEditor) {
        NSLog(@"editSelectedTrack : allocating track editor");
        segmentEventListEditor = [[SegmentEditor alloc] initWithCurrentDocument:self];
    }
    
    [segmentEventListEditor showWindow:self];
}

- (IBAction)editSelectedSegmentNotation:(id)sender
{
    NSLog(@"MyDocument:editSelectedSegmentNotation");
    if (!segmentNotationEditor) {
        NSLog(@"editSelectedTrack : allocating track editor");
        segmentNotationEditor = [[SegmentNotationEditor alloc] initWithCurrentDocument:self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notationEditorClosing:) name:NSWindowWillCloseNotification object:segmentNotationEditor.window];
    }
    
    [segmentNotationEditor showWindow:self];
}

- (IBAction)togglePlay:(id)sender
{
    if ([player isPlaying])
        [self stop:self];
    else
        [self play:self];
}

- (IBAction)play:(id)sender
{
    NSLog(@"start playing");
    if (documentModifiedSinceLastPlay) {
        documentModifiedSinceLastPlay = NO;
        DisposeMusicSequence(sequence);
        NewMusicSequence(&sequence);
        [self fillSequence];
        [player setUpWithSequence:sequence];
    }
    
    [player play];
}

- (IBAction)stop:(id)sender
{
    [player stop];
    NSLog(@"stop playing"); 
}

- (BOOL)playing
{
    return [player isPlaying];
}


- (IBAction)rewind:(id)sender
{
    [player rewind];
}

- (NSArrayController*)midiSourcesController
{
    Recorder* recorder = [(AppController*)[NSApp delegate] recorder];
    return [recorder midiSourcesController];
}

- (IBAction)toggleRecording:(id)sender
{
    NSLog(@"toggle recording");

    Recorder* recorder = [(AppController*)[NSApp delegate] recorder];

    if ([sender state] == NSOnState) {
        NSLog(@"MyDocument : start recording");
        [self setupTempo];
        [recorder start];
    } else {
        [recorder stop];
    }
}


- (IBAction)testAddEvent:(id)sender
{
    NSManagedObject<Track>* currentTrack = [[tracksController selectedObjects] objectAtIndex:0];
    NSManagedObject<Segment>* currentSegment = [[segmentsController selectedObjects] objectAtIndex:0];
    
    NSManagedObjectContext* managedObjectContext = [currentTrack managedObjectContext];
    
    NSManagedObject<Note>* newNote = [NSEntityDescription insertNewObjectForEntityForName:@"Note" 
                                                                   inManagedObjectContext:managedObjectContext];
    
//    NSLog(@"MyDocument:testAddEvent note = %@", newNote);
//    NSLog(@"MyDocument:testAddEvent note duration = %@, pitch = %@", [newNote duration], [newNote note]);
    
    UInt64 d = AudioConvertNanosToHostTime(1000000000);
    
    [newNote setDuration:[NSNumber numberWithUnsignedLong:d]];
    [newNote setNote:[NSNumber numberWithInt:60]];
    [newNote setVelocity:[NSNumber numberWithInt:120]];
    
    [currentSegment addEventsObject:newNote];

}

- (void)setupTempo
{
    NSManagedObjectContext* moc = [self managedObjectContext];
    
    // Get tempo from composition
    NSEntityDescription *compositionEntityDescription = [NSEntityDescription entityForName:@"Composition" inManagedObjectContext:moc];
    NSFetchRequest *compositionRequest = [[NSFetchRequest alloc] init];
    [compositionRequest setEntity:compositionEntityDescription];    
    
    NSError *error = nil;
    NSArray *composition = [moc executeFetchRequest:compositionRequest error:&error];
    
    id<Composition> theComposition = [composition objectAtIndex:0];
    
    NSNumber* f = [theComposition playbackTempo];
    
    NSLog(@"MyDocument:setupTempo : tempo = %@", f);
    
    MusicTrack tempoTrack;
    
    MusicSequenceGetTempoTrack(sequence, &tempoTrack);
    
    MusicTrackClear(tempoTrack, 0.0, 1.0); // clear first tempo event, if any
    
    MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, [f doubleValue]);
    
}

- (void)compositionControllerContentSet:(NSNotification *)notification
{
    NSLog(@"MyDocument:compositionControllerContentSet");
    [self setupZoomSlider];
}

- (void)documentIsBeingModified:(NSNotification*)notification
{
    NSLog(@"MyDocument:documentIsBeingModified");
    
    documentModifiedSinceLastPlay = YES;    
}

- (void)fillSequence
{
    NSLog(@"MyDocument:fillSequence");

    [self setupTempo];
    
    NSManagedObjectContext* moc = [self managedObjectContext];

    NSEntityDescription *trackEntityDescription = [NSEntityDescription entityForName:@"Track" inManagedObjectContext:moc];
    
    NSFetchRequest *tracksRequest = [[NSFetchRequest alloc] init];
    [tracksRequest setEntity:trackEntityDescription];    
    
    NSError *error = nil;
    NSArray *tracks = [moc executeFetchRequest:tracksRequest error:&error];
    
    // TODO: rewrite this using composition.tracks accessor ?
    
    if (tracks != nil) {
        NSEnumerator *tracksEnumerator = [tracks objectEnumerator];
        
        id aTrack;
        
        while((aTrack = [tracksEnumerator nextObject])) {
            MusicTrack sequenceTrack;
            MusicSequenceNewTrack(sequence, &sequenceTrack);
            
            
            // Fetch all playable events from that track
            NSEntityDescription *playableEventDescription = [NSEntityDescription entityForName:@"PlayableElement" inManagedObjectContext:moc];
            
            NSFetchRequest *playableEventsRequest = [[NSFetchRequest alloc] init];
            [playableEventsRequest setEntity:playableEventDescription];
            
            // I could get the events directly from aTrack, but with a query I get the filtering of playable events for free
            //
            NSPredicate *eventsFromThisTrackPredicate = [NSPredicate predicateWithFormat:@"segment.track == %@", aTrack];
            [playableEventsRequest setPredicate:eventsFromThisTrackPredicate];
            [playableEventsRequest setSortDescriptors:[coreDataUtils absoluteTimeSortDescriptorArray]];
            
            NSArray *playableEvents = [moc executeFetchRequest:playableEventsRequest error:&error];
            if (playableEvents != nil) {
                NSEnumerator *eventsEnumerator = [playableEvents objectEnumerator];
                
                NSLog(@"got %lu playable events for track '%@'", [playableEvents count], [aTrack name]);
                
                NSManagedObject<Element,Note>* anEvent;
                
                while((anEvent = [eventsEnumerator nextObject])) {
                    // NSLog(@"event : %@ ", anEvent);
                    MIDINoteMessage msg;
                    msg.channel = [[aTrack channel] intValue];
                    msg.duration = [[anEvent duration] floatValue];
                    msg.velocity = [[anEvent velocity] intValue];
                    msg.note = [[anEvent note] intValue];
                    MusicTimeStamp timeStamp = [[anEvent absoluteTime] doubleValue];
                    MusicTrackNewMIDINoteEvent(sequenceTrack, timeStamp, &msg);
                }
            } else {
                NSLog(@"error when fetching events for track");
            }
        }
        
    } else {
        NSLog(@"error when fetching track");
    }
    
    NSLog(@"CAShow sequence :");
    CAShow(sequence);
}


- (void)notationEditorClosing:(NSNotification *)notification
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:segmentNotationEditor.window];
    segmentNotationEditor = nil;
}

@synthesize tracksController;
@synthesize compositionController;
@synthesize timeSignaturesController;
@synthesize temposController;
@synthesize coreDataUtils;
@synthesize segmentCanvas;

@synthesize sequence;
@synthesize segmentsController;

@end
