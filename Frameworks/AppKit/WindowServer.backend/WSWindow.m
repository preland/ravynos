/*
 * Copyright (C) 2022-2024 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <Foundation/NSException.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPopUpWindow.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>
#import "WSWindow.h"
#import "O2Context_builtin_FT.h"
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2ImageSource_PNG.h>
#import <Onyx2D/O2Image.h>
#import <QuartzCore/CAWindowOpenGLContext.h>


CGL_EXPORT CGLError CGLCreateContextForWindow(CGLPixelFormatObj pixelFormat,
    CGLContextObj share, CGLContextObj *resultp, unsigned long window);

void CGNativeBorderFrameWidthsForStyle(unsigned styleMask,CGFloat *top,CGFloat *left,
                                       CGFloat *bottom,CGFloat *right)
{
    switch(styleMask & 0x0FFF) {
        case NSBorderlessWindowMask:
            *top=0;
            *left=0;
            *bottom=0;
            *right=0;
            break;
        // FIXME: tool window style?
        default:
            *top=30;
            *left=0;
            *bottom=0;
            *right=0;
    }
}

@implementation WSWindow
- initWithFrame:(O2Rect)frame styleMask:(unsigned)styleMask isPanel:(BOOL)isPanel
    backingType:(NSUInteger)backingType windowNumber:(int)number
{
    _level = kCGNormalWindowLevel;
    _number = number;
    _backingType = backingType;
    _deviceDictionary = [NSMutableDictionary new];
    _frame = frame;
    _cglContext = NULL;
    _caContext = NULL;
    _styleMask = styleMask;
    _ready = NO;
    _display = [NSDisplay currentDisplay];
    _delegate = nil;

    buffer = NULL;
    bundleID = [[NSBundle mainBundle] bundleIdentifier];
    shmPath = [NSString stringWithFormat:@"/%s/%u/win/%u", [bundleID cString], getpid(), _number];

    if(isPanel && (styleMask & NSDocModalWindowMask))
        _styleMask=NSBorderlessWindowMask;

    _context = [self cgContext];

    return self;
}

-(void)close {
    [self release];
}

-(void)dealloc
{
    _ready = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(buffer && bufsize)
        munmap(buffer, bufsize);
    shm_unlink([shmPath cString]);
    if(_context)
        [_context release];
    if(_cglContext)
        [_cglContext release];
    if(_caContext)
        [_caContext release];
    [_deviceDictionary release];
    [super dealloc];
}

-(void) setDelegate:delegate {
    _delegate=delegate;
}

- delegate {
    return _delegate;
}

-(void) invalidate
{
    [_delegate platformWindowDidInvalidateCGContext:self];
}


-(void)createCGLContextObjIfNeeded {
   if(_cglContext==NULL){
    CGLError error;
    
    if((error=CGLCreateContextForWindow(NULL,NULL,&_cglContext,(uintptr_t)self))!=kCGLNoError)
     NSLog(@"CGLCreateContextForWindow failed at %s %d with error %d",__FILE__,__LINE__,error);
   }
   if(_cglContext!=NULL && _caContext==NULL){
    _caContext=[[CAWindowOpenGLContext alloc] initWithCGLContext:_cglContext];
   }
}

-(O2Context *) createCGContextIfNeeded
{
    if(_context == nil) {
        if(buffer != NULL && bufsize > 0)
            munmap(buffer, bufsize);

        int depth = [_display depth] / 8;
        int shmfd = shm_open([shmPath cString], O_RDWR, 0600);
        bufsize = depth * _frame.size.width * _frame.size.height;

        if(shmfd >= 0) {
            buffer = mmap(NULL, bufsize, PROT_WRITE|PROT_READ, MAP_SHARED|MAP_NOCORE, shmfd, 0);
            close(shmfd);
        }

        /* If WS has not created the shared mem yet, buffer will be NULL here. This results
         * in us creating a surface and context anyway, but they won't be visible on the
         * screen yet. That's ok - when WS finishes creating the display surface, it will
         * trigger invalidateContextsWithNewSize: to recreate the context and set the actual
         * size if it changed from the client's request.
         */

        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc] initWithBytes:buffer
                width:_frame.size.width height:_frame.size.height
                bitsPerComponent:8 bytesPerRow:4*_frame.size.width colorSpace:colorSpace
                bitmapInfo:kO2BitmapByteOrderDefault|kCGImageAlphaPremultipliedFirst];
        _context = [[O2Context_builtin_FT alloc] initWithSurface:surface flipped:NO];
        _ready = YES;
    }
    return _context;
}

-(O2Context *) createBackingCGContextIfNeeded
{
    return nil;
}

-(O2Context *) cgContext
{
    return [self createCGContextIfNeeded];
}

-(void) invalidateContextsWithNewSize:(NSSize)size forceRebuild:(BOOL)forceRebuild
{
    O2Image *snapshot = O2BitmapContextCreateImage(_context);
    NSSize oldSize = _frame.size;

    if(!NSEqualSizes(_frame.size,size) || forceRebuild) {
        _frame.size = size;

        [self setReady:NO];
        [_context release];
        _context = nil;
        [_caContext release];
        _caContext = NULL;
        //CGLReleaseContext(_cglContext);
        _cglContext = NULL;
        //[self createCGLContextObjIfNeeded];
    }

    [self cgContext];
    [_context drawImage:snapshot inRect:NSMakeRect(0,0,oldSize.width,oldSize.height)];
    [snapshot release];
    [_delegate platformWindowDidInvalidateCGContext:self];

    //CGLSurfaceResize(_cglContext, size.width, size.height);
}

-(void) invalidateContextsWithNewSize:(NSSize)size
{
    [self invalidateContextsWithNewSize:size forceRebuild:NO];
}

-(void) setTitle:(NSString *)title
{
    //if(xdg_toplevel)
    //    xdg_toplevel_set_title(xdg_toplevel, [title UTF8String]);
    // FIXME: send a "window modify" message to WS
}

-(BOOL) setProperty:(NSString *)property toValue:(NSString *)value
{
    return YES;
}

-(void) setFrame:(O2Rect)frame
{
    [self invalidateContextsWithNewSize:frame.size];
    // move window
    _frame = frame;
}

-(void) showWindowForAppActivation:(O2Rect)frame
{
    NSUnimplementedMethod();
}

-(void) hideWindowForAppDeactivation:(O2Rect)frame
{
    NSUnimplementedMethod();
}

-(void) hideWindow
{
    _mapped=NO;
}

-(void) placeAboveWindow:(int)otherNumber
{
    // map and stack order
}

-(void) placeBelowWindow:(int)otherNumber
{
    // map and stack order
}

-(void) makeKey
{
    // map and stack order
}

-(void) makeMain
{
    // map and stack order
}

-(void) captureEvents
{
    // FIXME: find out what this is supposed to do
}

-(void) miniaturize
{
    NSUnimplementedMethod();
}

-(void) deminiaturize
{
    NSUnimplementedMethod();
}

-(BOOL) isMiniaturized
{
    return NO;
}


-(void) openGLFlushBuffer
{
    if(! _ready)
        return;

    CGLError error;
    CGLContextObj prevContext = CGLGetCurrentContext();
   
    [self createCGLContextObjIfNeeded];
    if(_caContext == NULL)
        return;

    O2Surface *surface = [_context surface];
    [_caContext prepareViewportWidth:_frame.size.width height:_frame.size.height];
    [_caContext renderSurface:surface];
    CGLFlushDrawable(_cglContext);

    CGLSetCurrentContext(prevContext);
}

-(void) flushBuffer
{
    /* flush pending changes to our O2Surface & tell compositor we're ready */
    O2ContextFlush(_context);
}

// This seems wrong but it's exactly what was done in the Win32 version
-(NSPoint) mouseLocationOutsideOfEventStream
{
#if notyet
    Window window;
    int rootX, rootY, winX, winY;
    unsigned int mask;

    BOOL result = XQueryPointer(_display, DefaultRootWindow(_display),
        &window, &window, &rootX, &rootY, &winX, &winY, &mask);
    if(result == YES) {
        return [self transformPoint:NSMakePoint(rootX, rootY)];
    }
#endif
    NSLog(@"-[WSWindow mouseLocationOutsideOfEventStream] unable to locate mouse pointer");
    return NSMakePoint(0,0);
}


-(O2Rect) frame
{
    CGRect rect = CGInsetRectForNativeWindowBorder(_frame,_styleMask);
    return rect;
}

-(void) addEntriesToDeviceDictionary:(NSDictionary *)entries
{
    [_deviceDictionary addEntriesFromDictionary:entries];
}

- (NSPoint)transformPoint:(NSPoint)pos
{
    return pos;
}

- (O2Rect)transformFrame:(O2Rect)frame
{
    return frame;
}

- (void)frameChanged
{
    [self invalidateContextsWithNewSize:_frame.size];
}

- (void)setReady:(BOOL)ready
{
    _ready = ready;
}

- (BOOL)isReady
{
    return _ready;
}

- (void)requestMove:(NSEvent *)event
{
    [[self delegate] platformWindowWillMove:self];
}

- (void)requestResize:(NSEvent *)event
{
    NSLog(@"resize not implemented");
}

- (int)windowNumber {
    //return (int)self;
    return _number;
}

-(void)_setWindowNumber:(int)number {
    _number = number;
}

-(void)setStyleMask:(unsigned)mask {
    _styleMask = mask;
    // FIXME: do we need to do anything else?
}

@end

CGRect CGInsetRectForNativeWindowBorder(CGRect frame,unsigned styleMask)
{
#if 0
    CGFloat top,left,bottom,right;
    
    CGNativeBorderFrameWidthsForStyle(styleMask,&top,&left,&bottom,&right);
    
    frame.origin.x+=left;
    frame.origin.y+=bottom;
    frame.size.width-=left+right;
    frame.size.height-=top+bottom;
#endif 
    return frame;
}

CGRect CGOutsetRectForNativeWindowBorder(CGRect frame,unsigned styleMask)
{
#if 0
    CGFloat top,left,bottom,right;
    
    CGNativeBorderFrameWidthsForStyle(styleMask,&top,&left,&bottom,&right);
    
    frame.origin.x-=left;
    frame.origin.y-=bottom;
    frame.size.width+=left+right;
    frame.size.height+=top+bottom;
#endif 
    return frame;
}
