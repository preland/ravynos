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
#include <pthread.h>
#include <pwd.h>
#include <grp.h>
#include <login_cap.h>

#import "BSDFramebuffer.h"
#import "WSInput.h"

#define SA_RESTART      0x0002  /* restart system call on signal return */

enum {
    WS_ERROR, WS_WARNING, WS_INFO
};

enum ShellType {
    NONE, LOGINWINDOW, DESKTOP
};

/* Application dictionary entry keys */
#define APPNAME		"AppName"	 /* NSString */
#define APPICON		"AppIcon"	 /* NSImage */
#define PID 		"AppPID"	 /* pid_t */
#define WINDOWS		"AppWindowList"	 /* NSMutableArray */
#define INPUTPORT	"AppInputPort"   /* mach_port_t */

/* Window dictionary entry keys */
#define WINSTATE	"WindowState"	 /* enum */
#define WINGEOM		"WindowGeometry" /* NSRect */
#define WINTITLE	"WindowTitle"	 /* NSString */
#define WINICON		"WindowIcon"	 /* NSImage */
#define WINWIN		"WindowWindow"	 /* NSWindow shared mem */

/* this must be in sync with actual NSWindow state */
enum WindowState {
    NORMAL, MAXVERT, MAXHORIZ, MAXIMIZED, MINIMIZED, HIDDEN
};

@interface WindowServer : NSObject {
    BOOL ready;
    BOOL stopOnErr;
    char **envp;
    unsigned int nobodyUID;
    unsigned int videoGID;
    unsigned int logLevel;
    enum ShellType curShell;
    BSDFramebuffer *fb;
    O2BitmapContext *ctx;
    NSRect geometry;
    WSInput *input;

    NSMutableDictionary *apps;
    NSMutableDictionary *windowsByApp;
    NSDictionary *curApp;
    NSDictionary *curWindow;
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

@end
