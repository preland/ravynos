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

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSEvent.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>

#import "message.h"

#define WINDOWSERVER_SVC_NAME "com.ravynos.WindowServer"

mach_port_t _wsReplyPort;
mach_port_t _wsSvcPort;

BOOL ready = YES;

// this is our NSApp window list :)
int windowID = 123;
BOOL platformCreated = NO;

// this needs to go in AppKit
void receiveMachMessage(void) {
    ReceiveMessage msg = {0};
    mach_msg_return_t result = mach_msg((mach_msg_header_t *)&msg, MACH_RCV_MSG|MACH_RCV_TIMEOUT, 0,
            sizeof(msg), _wsReplyPort, 20, MACH_PORT_NULL);
    
    if(result != MACH_MSG_SUCCESS)
        return;

    if(msg.code == CODE_WINDOW_CREATED) {
        if(msg.len != sizeof(struct mach_win_data)) {
            NSLog(@"Incorrect data size in window created: %d vs %d", msg.len, sizeof(struct mach_win_data));
            return;
        }
        int _id = ((struct mach_win_data *)msg.data)->windowID;
        // find window with _id
        if(platformCreated != NO) {
            NSLog(@"windowCreated event for window %u already created", _id);
            return;
        }
        platformCreated = YES;
        NSLog(@"window %u created", windowID);
        return;
    }

    if(msg.code == CODE_INPUT_EVENT) {
        struct mach_event me;
        if(msg.len != sizeof(me)) {
            NSLog(@"Incorrect data size in input event: %d vs %d", msg.len, sizeof(me));
            return;
        }
        memcpy(&me, msg.data, msg.len);
        switch(me.code) {
            case NSKeyUp:
            case NSKeyDown: {
                NSEvent *e = [NSEvent keyEventWithType:me.code
                                              location:NSMakePoint(me.x, me.y)
                                         modifierFlags:me.mods
                                             timestamp:0.0
                                          windowNumber:me.windowID
                                               context:nil
                                            characters:[[NSString alloc] initWithUTF8String:me.chars]
                           charactersIgnoringModifiers:[[NSString alloc] initWithUTF8String:me.charsIg]
                                             isARepeat:me.repeat
                                               keyCode:me.keycode];
                /* FIXME: dispatch to NSDisplay */
                if(e.type == NSKeyDown && me.chars[0] == '\e' )
                    ready = NO;
                break;
            }
            case NSMouseMoved: {
                NSEvent *e = [NSEvent mouseEventWithType:me.code
                                                location:NSMakePoint(me.x, me.y)
                                           modifierFlags:me.mods
                                                  window:nil // FIXME: send real NSWindow here
                                              clickCount:0
                                                  deltaX:me.dx
                                                  deltaY:me.dy];
                /* FIXME: dispatch to NSDisplay */
                fprintf(stdout, "%.1f,%.1f (%.1f,%-1f)          \r", me.x, me.y, me.dx, me.dy);
                fflush(stdout);
                break;
            }
            case NSLeftMouseDown:
            case NSLeftMouseUp: 
            case NSRightMouseDown:
            case NSRightMouseUp: {
                NSEvent *e = [NSEvent mouseEventWithType:me.code
                                                location:NSZeroPoint // FIXME: use saved coords
                                           modifierFlags:me.mods
                                                  window:nil // FIXME: send real NSWindow here
                                              clickCount:1
                                                  deltaX:me.dx
                                                  deltaY:me.dy];
                /* FIXME: dispatch to NSDisplay */
                break;
            }
            default:
                NSLog(@"Unhandled event type %d", me.code);
                return;
        }
    }
}


int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    // Create a port with send/receive rights that WindowServer will use
    // to invoke our menu actions
    mach_port_t task = mach_task_self();
    if(mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &_wsReplyPort) != KERN_SUCCESS ||
        mach_port_insert_right(task, _wsReplyPort, _wsReplyPort, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
        NSLog(@"Failed to allocate mach_port _wsReplyPort");
        exit(1);
    }

    _wsSvcPort = MACH_PORT_NULL;
    NSLog(@"bp=%d, looking up service %s", bootstrap_port, WINDOWSERVER_SVC_NAME);
    if(bootstrap_look_up(bootstrap_port, WINDOWSERVER_SVC_NAME, &_wsSvcPort) != KERN_SUCCESS) {
        NSLog(@"Failed to locate WindowServer port");
        exit(1);
    }
    NSLog(@"found service port %d", _wsSvcPort);

    // register this app with WS
    PortMessage msg = {0};
    msg.header.msgh_remote_port = _wsSvcPort;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, MACH_MSGH_BITS_COMPLEX);
    msg.header.msgh_id = MSG_ID_PORT;
    msg.header.msgh_size = sizeof(msg);
    msg.msgh_descriptor_count = 1;
    msg.descriptor.type = MACH_MSG_PORT_DESCRIPTOR;
    msg.descriptor.name = _wsReplyPort;
    msg.descriptor.disposition = MACH_MSG_TYPE_MAKE_SEND;
    msg.pid = getpid();
    strcpy(msg.bundleID, "com.ravynos.client-example");

    if(mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT, sizeof(msg), 0, MACH_PORT_NULL,
        2000 /* ms timeout */, MACH_PORT_NULL) != MACH_MSG_SUCCESS)
        NSLog(@"Failed to send port message to WS");

    // create a platform window
    struct mach_win_data windat = {
        windowID, 200, 200, 462, 447, 0, "Demo Window"
    };

    Message msgi = {0};
    msgi.header.msgh_remote_port = _wsSvcPort;
    msgi.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msgi.header.msgh_id = MSG_ID_INLINE;
    msgi.header.msgh_size = sizeof(msgi);
    msgi.code = CODE_WINDOW_CREATE;
    msgi.pid = getpid();
    strcpy(msgi.bundleID, "com.ravynos.client-example");
    memcpy(msgi.data, &windat, sizeof(windat));
    msgi.len = sizeof(windat);

    if(mach_msg((mach_msg_header_t *)&msgi, MACH_SEND_MSG|MACH_SEND_TIMEOUT, sizeof(msgi), 0,
                MACH_PORT_NULL, 2000, MACH_PORT_NULL) != MACH_MSG_SUCCESS)
        NSLog(@"Failed to send window message to WS");

    while(!platformCreated)
        receiveMachMessage();

    NSString *shmPath = [NSString stringWithFormat:@"/com.ravynos.client-example/%u/win/%u",
             getpid(), windowID];

    int shmfd = shm_open([shmPath cString], O_RDWR, 0600);
    void *buffer = NULL;
    if(shmfd < 0) {
        NSLog(@"Cannot open shmfd: %s", strerror(errno));
    } else {
        ftruncate(shmfd, 4*447*462); 
        buffer = mmap(NULL, 4*447*462, PROT_WRITE|PROT_READ, MAP_SHARED|MAP_NOCORE, shmfd, 0);
        close(shmfd);
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buffer, 462, 447, 8,
            462*4, cs, kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedLast);

    NSData *d = [NSData dataWithContentsOfFile:@"SystemUIServer/ReleaseLogo.tiff"];
    CGDataProviderRef pngdp = CGDataProviderCreateWithData(NULL, [d bytes], [d length], NULL);
    CGImageRef img = CGImageCreate(462, 447, 8, 32, 4*462, cs, kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst, pngdp, NULL, false, kCGRenderingIntentDefault);

    while(ready == YES) {
        CGContextDrawImage(ctx, (CGRect)NSMakeRect(0,0,462,447), img);
        while(ready == YES)
            receiveMachMessage();
    }

    [pool drain];
    munmap(buffer, 4*447*462); // just to be safe
    shm_unlink([shmPath cString]);
    exit(0);
}

