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

#define WINDOWSERVER

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/NSEvent.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/event.h>
#include <pthread.h>
#include <pwd.h>
#include <grp.h>
#include <login_cap.h>

#import "message.h"
#import "BSDFramebuffer.h"
#import "WSInput.h"

@interface WSAppRecord : NSObject
@property NSString *bundleID;
@property unsigned int pid;
@property mach_port_t port;
@end

@interface WSWindowRecord : NSObject
@property int _number;                // internal window ID
@property void *_surface;             // shared graphics memory
@property enum WindowState state;     // state
@property NSRect geometry;            // position and size
@end

@interface WindowServer : NSObject {
    BOOL ready;
    BOOL stopOnErr;
    char **envp;
    unsigned int nobodyUID;
    unsigned int videoGID;
    unsigned int logLevel;
    enum ShellType curShell;
    BSDFramebuffer *fb;
    NSRect geometry;

    WSInput *input;

    NSMutableDictionary *apps;
    NSMutableDictionary *windowsByApp;
    WSAppRecord *curApp;
    WSWindowRecord *curWindow;

    mach_port_name_t _servicePort;
    int _kq;
}

-init;
-(void)dealloc;
-(BOOL)launchShell;
-(BOOL)isReady;
-(NSRect)geometry;
-(void)draw;
-(O2BitmapContext *)context;
-(BOOL)setUpEnviron:(uid_t)uid;
-(void)freeEnviron;
-(void)dispatchEvent:(struct libinput_event *)event;
-(void)run;
-(void)processKernelQueue;
-(void)receiveMachMessage;
-(BOOL)sendEventToApp:(NSEvent *)event;

@end
