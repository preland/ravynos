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

// this needs to go in AppKit
void receiveMachMessage(void) {
    ReceiveMessage msg = {0};
    mach_msg_return_t result = mach_msg((mach_msg_header_t *)&msg, MACH_RCV_MSG|MACH_RCV_TIMEOUT, 0,
            sizeof(msg), _wsReplyPort, 20, MACH_PORT_NULL);
    
    if(result != MACH_MSG_SUCCESS)
        return;

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
                break;
            }
            case NSMouseMoved: {
                NSEvent *e = [NSEvent mouseEventWithType:me.code
                                                location:NSMakePoint(me.x, me.y)
                                           modifierFlags:0 // FIXME: use saved keyboard state
                                               timestamp:0.0
                                            windowNumber:me.windowID
                                                 context:nil
                                             eventNumber:0 // FIXME: keep track in global state
                                              clickCount:0
                                                pressure:1.0];
                /* FIXME: dispatch to NSDisplay */
                break;
            }
            case NSLeftMouseDown:
            case NSLeftMouseUp: 
            case NSRightMouseDown:
            case NSRightMouseUp: {
                NSEvent *e = [NSEvent mouseEventWithType:me.code
                                                location:NSZeroPoint // FIXME: use saved coords
                                           modifierFlags:0 // FIXME: use saved keyboard state
                                               timestamp:0.0
                                            windowNumber:me.windowID
                                                 context:nil
                                             eventNumber:0 // FIXME: keep track in global state
                                              clickCount:1
                                                pressure:1.0];
                /* FIXME: dispatch to NSDisplay */
                break;
            }
            default:
                NSLog(@"Unhandled event type %d", me.code);
        }
    }
}


int main(int argc, const char *argv[]) {
    BOOL ready = YES;

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

    int shmfd = shm_open("/shm/app/1", O_RDWR | O_CREAT, 0644);
    void *buffer = NULL;
    if(shmfd < 0) {
        NSLog(@"Cannot create shmfd: %s", strerror(errno));
    } else {
        ftruncate(shmfd, 4*1024*768); // 32 bit 1024x768 buffer
        buffer = mmap(NULL, 4*1024*768, PROT_WRITE|PROT_READ, MAP_SHARED, shmfd, 0);
        close(shmfd);
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buffer, 1024, 768, 8,
            1024*4, cs, kCGImageAlphaLast);

    NSImage *png = [[NSImage alloc] initWithContentsOfFile:@"SystemUIServer/ReleaseLogo.tiff"];
    NSData *pngdata = [png TIFFRepresentation];
    CGDataProviderRef pngdp = CGDataProviderCreateWithCFData((__bridge CFDataRef)pngdata);
    CGImageRef img = CGImageCreate([png size].width, [png size].height, 8, 32, 4*[png size].width, cs, kCGImageAlphaPremultipliedLast, pngdp, NULL, false, kCGRenderingIntentDefault);

    while(ready == YES) {
        CGContextSetRGBFillColor(ctx, 160, 160, 80, 1);
        CGContextFillRect(ctx, (CGRect)NSMakeRect(0,0,1024,768));
        CGContextDrawImage(ctx, (CGRect)NSMakeRect(384,256,300,300), img);
        receiveMachMessage();
    }

    [pool drain];
    shm_unlink("/shm/app/1");
    exit(0);
}
