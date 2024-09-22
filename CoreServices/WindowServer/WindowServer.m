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

#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2Image.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSWindow.h>
#import "common.h"
#import "WindowServer.h"
#import "WSInput.h"

#undef direction // defined in mach.h
#include <linux/input.h>

#include <poll.h>
#include <kvm.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/user.h>


@implementation WSAppRecord
-init {
    _windows = [NSMutableArray new];
    return self;
}

-(void)addWindow:(WSWindowRecord *)window {
    [_windows addObject:window];
}

-(void)removeWindowWithID:(int)number {
    for(int i = 0; i < [_windows count]; i++) {
        WSWindowRecord *r = [_windows objectAtIndex:i];
        if(r.number == number) {
            [_windows removeObjectAtIndex:i];
            return;
        }
    }
}

-(WSWindowRecord *)windowWithID:(int)number {
    for(int i = 0; i < [_windows count]; i++) {
        WSWindowRecord *r = [_windows objectAtIndex:i];
        if(r.number == number) {
            return r;
        }
    }
    return nil;
}

-(NSArray *)windows {
    return [NSArray arrayWithArray:_windows];
}

@end

@implementation WSWindowRecord
-(void)dealloc {
    if(_surfaceBuf != NULL)
        munmap(_surfaceBuf, _bufSize);
    shm_unlink([_shmPath cString]);
}

-(void)setOrigin:(NSPoint)pos {
    _geometry.origin = pos;
}

-(void)drawFrame:(O2Context *)_context {
    if((_styleMask & 0x0FFF) == NSBorderlessWindowMask)
        return;
    
    O2ContextSetGrayStrokeColor(_context, 0.8, 1);
    O2ContextSetGrayFillColor(_context, 0.8, 1);

    NSRect _frame = _geometry;
    _frame.size.height += 27;
    _frame.size.width += 6;
    _frame.origin.x -= 6;
    _frame.origin.y -= 6;

    // let's round these corners
    float radius = 12;
    O2ContextBeginPath(_context);
    O2ContextMoveToPoint(_context, _frame.origin.x+radius, NSMaxY(_frame));
    O2ContextAddArc(_context, _frame.origin.x + _frame.size.width - radius,
        _frame.origin.y + _frame.size.height - radius, radius, 1.5708 /*radians*/,
        0 /*radians*/, YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x + _frame.size.width,
        _frame.origin.y);
    O2ContextAddArc(_context, _frame.origin.x + _frame.size.width - radius,
        _frame.origin.y + radius, radius, 6.28319 /*radians*/, 4.71239 /*radians*/,
        YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x, _frame.origin.y);
    O2ContextAddArc(_context, _frame.origin.x + radius, _frame.origin.y + radius,
        radius, 4.71239, 3.14159, YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x,
        _frame.origin.y + _frame.size.height);
    O2ContextAddArc(_context, _frame.origin.x + radius, _frame.origin.y +
        _frame.size.height - radius, radius, 3.14159, 1.5708, YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x, NSMaxY(_frame));
    O2ContextClosePath(_context);
    O2ContextFillPath(_context);

    // window controls
    int diameter = 12;
    CGRect button = NSMakeRect(_frame.origin.x + 10, _frame.origin.y + _frame.size.height - 21,
            diameter, diameter);
    //_closeButtonRect = button;
    O2ContextSetRGBFillColor(_context, 1, 0, 0, 1);
    O2ContextFillEllipseInRect(_context, button);
    O2ContextSetRGBFillColor(_context, 1, 0.9, 0, 1);
    button.origin.x += 22;
    //_miniButtonRect = button;
    O2ContextFillEllipseInRect(_context, button);
    O2ContextSetRGBFillColor(_context, 0, 1, 0, 1);
    button.origin.x += 22;
    //_zoomButtonRect = button;
    O2ContextFillEllipseInRect(_context, button);

    // title
    if(_title) {
        NSDictionary *attrs = @{
            NSFontAttributeName : [NSFont systemFontOfSize:15.0], // FIXME: should be titleBarFontOfSize
            NSForegroundColorAttributeName : [NSColor whiteColor],
            NSBackgroundColorAttributeName : [NSColor redColor]
        };
        NSAttributedString *title = [[NSAttributedString alloc] initWithString:_title attributes:attrs];
        NSSize size = [title size];
        NSRect titleRect = NSMakeRect(
            _frame.origin.x + (_frame.size.width / 2 - size.width / 2),
            _frame.origin.y + (_frame.size.height - 30 + size.height / 2),
            size.width,
            size.height + 4);
        [title drawInRect:titleRect];
    }
}
@end

@implementation WindowServer

-init {
    ready = NO;
    logLevel = WS_ERROR;
    envp = NULL;
    curShell = LOGINWINDOW;
    curApp = nil;
    curWindow = nil;

    kern_return_t kr;
    if((kr = bootstrap_check_in(bootstrap_port, WINDOWSERVER_SVC_NAME, &_servicePort)) != KERN_SUCCESS) {
        NSLog(@"Failed to check-in service: %d", kr);
        return nil;
    }

    _kq = kqueue();
    if(_kq < 0) {
        perror("kqueue");
        return nil;
    }

    kvm = kvm_open(NULL, "/dev/null", NULL, O_RDONLY, "WindowServer(kvm): ");

    apps = [NSMutableDictionary new];

    input = [WSInput new];
    [input setLogLevel:logLevel];

    stopOnErr = NO;
    NSString *s_stopOnErr = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"DebugExitOnError"];
    if(s_stopOnErr && [s_stopOnErr isEqualToString:@"YES"])
        stopOnErr = YES;

    struct passwd *passwd = getpwnam("nobody");
    if(!passwd) {
        perror("getpwnam(nobody)");
        return nil;
    }
    nobodyUID = passwd->pw_uid;

    struct group *group = getgrnam("video");
    if(!group) {
        perror("getgrnam(video)");
        return nil;
    }
    videoGID = group->gr_gid;

    // FIXME: try drm/kms first then fall back
    fb = [BSDFramebuffer new];
    if([fb openFramebuffer:"/dev/console"] < 0)
        return nil;
    _geometry = [fb geometry];

    [fb clear];

    // this is to keep our X,Y from leaving the screen bounds and eventually can be used to find
    // edges when there are multiple screens
    [input setGeometry:_geometry];
    [input setPointerPos:NSMakePoint(_geometry.size.width / 2, _geometry.size.height / 2)];

    ready = YES;
    return self;
}

-(void)dealloc {
    curShell = NONE;
    //pthread_cancel(curShellThread);
    fb = nil;
    input = nil;
    if(kvm)
        kvm_close(kvm);
}

-(void)setLogLevel:(int)level {
    logLevel = level;
}

-(BOOL)isReady {
    return ready;
}

-(O2BitmapContext *)context {
    return [fb context];
}
 
-(NSRect)geometry {
    return _geometry;
}

-(void)draw {
    return [fb draw];
}

-(BOOL)setUpEnviron:(uid_t)uid {
    struct passwd *pw = getpwuid(uid);
    if(!pw)
        return NO;
    int entries = 7;
    envp = malloc(sizeof(char *) * entries);
    asprintf(&envp[0], "HOME=%s", pw->pw_dir);
    asprintf(&envp[1], "SHELL=%s", pw->pw_shell);
    asprintf(&envp[2], "USER=%s", pw->pw_name);
    asprintf(&envp[3], "LOGNAME=%s", pw->pw_name);
    asprintf(&envp[4], "PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin");
    asprintf(&envp[6], "TERM=xterm");
    envp[entries - 1] = NULL;
    return YES;
}

-(void)freeEnviron {
    if(envp == NULL)
        return;

    while(*envp != NULL)
        free(*envp++);
    free(envp);
}

-(void *)launchShell {
    int status;
    NSString *lwPath = nil;

    while(curShell != NONE) {
        if(ready == NO) {
            sleep(1);
            continue;
        }

        switch(curShell) {
            case LOGINWINDOW:
                if(seteuid(0) != 0) { // re-assert privileges
                    perror("seteuid");
                    exit(-1);
                }

                if(setresgid(videoGID, videoGID, 0) != 0) {
                    perror("setresgid");
                    exit(-1);
                }
                if(setresuid(nobodyUID, nobodyUID, 0) != 0) {
                    perror("setresuid");
                    exit(-1);
                }

                int uid = nobodyUID;
                int gid = videoGID;

                int fds[2];
                if(pipe(fds) != 0) {
                    perror("pipe");
                    exit(-1);
                }
                char fdbuf[8];
                sprintf(fdbuf, "%d", fds[1]);
                int status = -1;

                lwPath = [[NSBundle mainBundle] pathForResource:@"LoginWindow" ofType:@"app"];
                if(!lwPath) {
                    NSLog(@"missing LoginWindow.app!");
                    break;
                }
                lwPath = [[NSBundle bundleWithPath:lwPath] executablePath];
                if(!lwPath) {
                    NSLog(@"missing LoginWindow.app!");
                    break;
                }
                
                if([self setUpEnviron:nobodyUID] == NO) {
                    NSLog(@"Unable to set up environment for LoginWindow!");
                    return NO;
                }

                pid_t pid = fork();
                if(!pid) { // child
                    close(fds[0]);
                    seteuid(0);
                    execle([lwPath UTF8String], [[lwPath lastPathComponent] UTF8String], fdbuf, NULL, envp);
                    exit(-1);
                } else {
                    close(fds[1]);
                    read(fds[0], &uid, sizeof(int));
                    waitpid(pid, &status, 0);
                }
                [self freeEnviron];
                close(fds[0]);
                NSLog(@"received uid %d", uid);

                if(uid < 500) {
                    NSLog(@"UID below minimum");
                    break;
                }
                    
                struct passwd *pw = getpwuid(uid);
                if(!pw || pw->pw_uid != uid) {
                    NSLog(@"no such uid %d", uid);
                    break;
                }
                gid = pw->pw_gid;

                if(seteuid(0) != 0) { // re-assert privileges
                    perror("seteuid");
                    return NO;
                }

                // ensure our helper is owned correctly
                {
                    NSString *path = [[NSBundle mainBundle] pathForResource:@"SystemUIServer" ofType:@"app"];
                    if(path)
                        path = [[NSBundle bundleWithPath:path] pathForResource:@"shutdown" ofType:@""];
                    if(path) {
                        chown([path UTF8String], 0, videoGID);
                        chmod([path UTF8String], 04550);
                    }
                }

                curShell = DESKTOP;
                break;
            case DESKTOP: {
                [self setUpEnviron:uid];
                pid_t pid = fork();
                if(pid == 0) {
                    setlogin(pw->pw_name);
                    chdir(pw->pw_dir);

                    login_cap_t *lc = login_getpwclass(pw);
                    if (setusercontext(lc, pw, pw->pw_uid,
                        LOGIN_SETALL & ~(LOGIN_SETLOGIN)) != 0) {
                            perror("setusercontext");
                            exit(-1);
                    }
                    login_close(lc);

                    NSString *path = [[NSBundle mainBundle] pathForResource:@"SystemUIServer" ofType:@"app"];
                    if(path)
                        path = [[NSBundle bundleWithPath:path] executablePath];
                    
                    if(path)
                        execle([path UTF8String], [[path lastPathComponent] UTF8String], NULL, envp);

                    perror("execl");
                    exit(-1);
                } else if(pid < 0) {
                    perror("fork");
                    sleep(3);
                    curShell = LOGINWINDOW;
                    break;
                }
                [self freeEnviron];
                waitpid(pid, &status, 0);
                curShell = LOGINWINDOW;
                // safety valve for debugging
                if(stopOnErr)
                    execl("/bin/launchctl", "launchctl", "remove", "com.ravynos.WindowServer", NULL);
                break;
            }
        }
    }
    pthread_exit(NULL);
}

-(uint32_t)windowCreate:(struct mach_win_data *)data forApp:(WSAppRecord *)app {
    struct kinfo_proc *kp;

    if(data->state < 0 || data->state >= WIN_STATE_MAX) {
        NSLog(@"windowCreate called with invalid state");
        data->state = NORMAL;
    }

    WSWindowRecord *winrec = [WSWindowRecord new];
    winrec.number = data->windowID;
    winrec.state = data->state;
    winrec.styleMask = data->style;
    winrec.geometry = NSMakeRect(data->x, data->y, data->w, data->h); // FIXME: bounds check?
    int len = 0;
    while(data->title[len] != '\0' && len < sizeof(data->title)) ++len;
    winrec.title = [NSString stringWithCString:data->title length:len];
    winrec.icon = nil;

    winrec.shmPath = [NSString stringWithFormat:@"/%@/%u/win/%u", [app bundleID],
        [app pid], winrec.number];
    winrec.bufSize = ([fb getDepth]/8) * data->w * data->h;

    int shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT, 0600);
    if(shmfd < 0) {
        NSLog(@"Cannot open shm fd: %s", strerror(errno));
        return 0;
    }

    if(ftruncate(shmfd, winrec.bufSize) < 0)
        NSLog(@"shmfd ftruncate failed: %s", strerror(errno));

    int count = 0;
    kp = kvm_getprocs(kvm, KERN_PROC_PID, [app pid], &count);
    if(count != 1 || kp->ki_pid != [app pid]) {
        NSLog(@"Cannot get client task info! pid %u", [app pid]);
        return 0;
    }

    if(fchown(shmfd, kp->ki_uid, kp->ki_rgid) < 0)
        NSLog(@"shmfd fchown failed: %s", strerror(errno));

    winrec.surfaceBuf = mmap(NULL, winrec.bufSize, PROT_WRITE|PROT_READ, MAP_SHARED|MAP_NOCORE, shmfd, 0);
    close(shmfd);

    if(winrec.surfaceBuf == NULL) {
        winrec.bufSize = 0;
        NSLog(@"Cannot alloc surface memory! %s", strerror(errno));
        return 0;
    }

    winrec.surface = [[O2Surface alloc] initWithBytes:winrec.surfaceBuf width:data->w
            height:data->h bitsPerComponent:8 bytesPerRow:4*(data->w)
            colorSpace:[fb colorSpace]
            bitmapInfo:kCGBitmapByteOrderDefault|kCGImageAlphaPremultipliedFirst];

    [app addWindow:winrec];
    return winrec.number;
}

-(void)run {
    // FIXME: lock this to vsync of actual display
    O2BitmapContext *ctx = [fb context];

    struct pollfd fds;
    fds.fd = [input fileDescriptor];
    fds.events = POLLIN;

    while(ready == YES) {
        if(poll(&fds, 1, 50) > 0)
            [input run:self];

        O2ContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        O2ContextFillRect(ctx, (O2Rect)_geometry);
        NSEnumerator *appEnum = [apps objectEnumerator];
        WSAppRecord *app;
        while((app = [appEnum nextObject]) != nil) {
            NSArray *wins = [app windows];
            int count = [wins count];
            for(int i = 0; i < count; ++i) {
                WSWindowRecord *win = [wins objectAtIndex:i];
                [win drawFrame:ctx];
                [ctx drawImage:win.surface inRect:win.geometry];
                curWindow = win;
            }
        }

        [fb draw];
    }

}

- (void)receiveMachMessage {
    ReceiveMessage msg = {0};
    mach_msg_return_t result = mach_msg((mach_msg_header_t *)&msg, MACH_RCV_MSG, 0, sizeof(msg),
        _servicePort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if(result != MACH_MSG_SUCCESS)
        NSLog(@"mach_msg receive error 0x%x", result);
    else {
        switch(msg.msg.header.msgh_id) {
            case MSG_ID_PORT:
            {
                mach_port_t port = msg.portMsg.descriptor.name;
                pid_t pid = msg.portMsg.pid;
                NSString *bundleID = [NSString stringWithCString:msg.portMsg.bundleID];
                NSLog(@"Port registration received from %@ pid %u for port %u", bundleID, pid, port);
                WSAppRecord *rec = [apps objectForKey:bundleID];
                if(!rec) {
                    rec = [WSAppRecord new];
                    rec.bundleID = bundleID;
                    rec.port = port;
                }
                rec.pid = pid;
                if(port != rec.port)
                    NSLog(@"Port registration received for %@ pid %u when already registered (%u -> %u)",
                            rec.bundleID, pid, rec.port, port);
                [apps setObject:rec forKey:bundleID];
                [self watchForProcessExit:pid];
                curApp = [apps objectForKey:bundleID]; // FIXME: manage this with task switcher

                // inform the new app about the display
                struct mach_display_info info = {
                    1, _geometry.size.width, _geometry.size.height, [fb getDepth]
                };
                [self sendInlineData:&info
                          length:sizeof(struct mach_display_info)
                        withCode:CODE_DISPLAY_INFO
                           toApp:rec];
                break;
            }
            case MSG_ID_INLINE:
                switch(msg.msg.code) {
                    case CODE_ADD_RECENT_ITEM:
                        // FIXME: pass to SystemUIServer
                        break;
                    case CODE_APP_BECAME_ACTIVE:
                    {
                        pid_t pid;
                        memcpy(&pid, msg.msg.data, msg.msg.len);
                        //NSLog(@"CODE_APP_BECAME_ACTIVE: pid = %d", pid);
                        // FIXME: pass to SystemUIServer
                        break;
                    }
                    case CODE_APP_BECAME_INACTIVE:
                    {
                        pid_t pid;
                        memcpy(&pid, msg.msg.data, msg.msg.len);
                        //NSLog(@"CODE_APP_BECAME_INACTIVE: pid = %d", pid);
                        //FIXME: pass to SystemUIServer
                        break;
                    }
                    case CODE_APP_ACTIVATE:
                    {
                        pid_t pid;
                        memcpy(&pid, msg.msg.data, sizeof(int));
                        NSLog(@"CODE_APP_ACTIVATE: pid = %d", pid);
                        // FIXME: pass to SystemUIServer
                        mach_port_t port = 0; // FIXME: get from active app
                        if(port != MACH_PORT_NULL) {
                            Message activate = {0};
                            activate.header.msgh_remote_port = port;
                            activate.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                            activate.header.msgh_id = MSG_ID_INLINE;
                            activate.header.msgh_size = sizeof(activate) - sizeof(mach_msg_trailer_t);
                            activate.code = msg.msg.code;
                            memcpy(activate.data, msg.msg.data+sizeof(int), sizeof(int)); // window ID
                            activate.len = sizeof(int);
                            mach_msg((mach_msg_header_t *)&activate, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                sizeof(activate) - sizeof(mach_msg_trailer_t),
                                0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        }
                        break;
                    }
                    case CODE_APP_HIDE:
                    {
                        pid_t pid;
                        memcpy(&pid, msg.msg.data, sizeof(int));
                        NSLog(@"CODE_APP_HIDE: pid = %d", pid);
                        // FIXME: pass to SystemUIServer
                        mach_port_t port = 0; // FIXME: get from active app
                        if(port != MACH_PORT_NULL) {
                            Message activate = {0};
                            activate.header.msgh_remote_port = port;
                            activate.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                            activate.header.msgh_id = MSG_ID_INLINE;
                            activate.header.msgh_size = sizeof(activate) - sizeof(mach_msg_trailer_t);
                            activate.code = msg.msg.code;
                            activate.len = 0;
                            mach_msg((mach_msg_header_t *)&activate, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                sizeof(activate) - sizeof(mach_msg_trailer_t),
                                0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        }
                        break;
                    }
		    case CODE_ADD_STATUS_ITEM:
		    {
			NSData *data = [NSData
			    dataWithBytes:msg.msg.data length:msg.msg.len];
			NSObject *o = nil;
			@try {
			    o = [NSKeyedUnarchiver unarchiveObjectWithData:data];
			}
			@catch(NSException *localException) {
			    NSLog(@"%@",localException);
			}

			if(o == nil || [o isKindOfClass:[NSDictionary class]] == NO ||
			    [(NSDictionary *)o objectForKey:@"StatusItem"] == nil ||
			    [(NSDictionary *)o objectForKey:@"ProcessID"] == nil) {
			    fprintf(stderr, "archiver: bad input\n");
			    break;
			}

#if 0 // I don't think we need this anymore since we set up NOTE_EXIT in MSG_ID_PORT
			NSDictionary *dict = (NSDictionary *)o;
			unsigned int pid = [[dict objectForKey:@"ProcessID"] unsignedIntValue];
                        [self watchForProcessExit:pid];
#endif

                        // FIXME: send to SystemUIServer
			break;
		    }
                }
                case CODE_WINDOW_CREATE: {
                    if(msg.msg.len != sizeof(struct mach_win_data)) {
                        NSLog(@"Incorrect data size for WINDOW_CREATE");
                        break;
                    }
                    struct mach_win_data *data = (struct mach_win_data *)msg.msg.data;
                    NSLog(@"CODE_WINDOW_CREATE bundle %s pid %u ID %u", msg.msg.bundleID, msg.msg.pid, data->windowID);
                    NSEnumerator *appEnum = [apps objectEnumerator];
                    WSAppRecord *app;
                    while((app = [appEnum nextObject]) != nil) {
                        if(app.pid == msg.msg.pid) {
                            struct mach_win_data reply;
                            memcpy(&reply, data, sizeof(reply));
                            reply.windowID = [self windowCreate:data forApp:app];
                            [self sendInlineData:&reply
                                          length:sizeof(struct mach_win_data)
                                        withCode:CODE_WINDOW_CREATED
                                           toApp:app];
                            return;
                        }
                    }
                    NSLog(@"No matching PID for WINDOW_CREATE! %u", msg.msg.pid);
                    break;
                }
                break;
        }
    }
}

// called from our kq watcher thread
- (void)processKernelQueue {
    struct kevent out[128];
    int count = kevent(_kq, NULL, 0, out, 128, NULL);

    for(int i = 0; i < count; ++i) {
        switch(out[i].filter) {
            case EVFILT_PROC:
                if((out[i].fflags & NOTE_EXIT)) {
                    //NSLog(@"PID %lu exited", out[i].ident);
                    WSAppRecord *app = [self findAppByPID:out[i].ident];
                    if(app == nil)
                        NSLog(@"PID %u exited, but no matching app record", out[i].ident);
                    else
                        [apps removeObjectForKey:app.bundleID];
                    // FIXME: send to SystemUIServer and Dock.app
                }
                break;
            default:
                NSLog(@"unknown filter");
        }
    }
}

- (BOOL)sendEventToApp:(struct mach_event *)event {
    event->windowID = curWindow.number; // fill in since WSInput doesn't have this info
    return [self sendInlineData:event
                         length:sizeof(struct mach_event)
                       withCode:CODE_INPUT_EVENT
                          toApp:curApp];
}

- (BOOL)sendInlineData:(void *)data length:(int)length withCode:(int)code toApp:(WSAppRecord *)app {
    mach_port_t port = [app port];

    Message msg = {0};
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = code;
    msg.pid = getpid();
    strncpy(msg.bundleID, WINDOWSERVER_SVC_NAME, sizeof(msg.bundleID)-1);

    memcpy(msg.data, data, length);
    msg.len = length;

    int ret;
    if((ret = mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
        sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL, 50 /* ms timeout */,
        MACH_PORT_NULL)) != MACH_MSG_SUCCESS) {
        NSLog(@"Failed to send message to PID %d on port %d: 0x%x", [app pid], port, ret);
        return NO;
    }
    return YES;
}

- (void)watchForProcessExit:(unsigned int)pid {
    struct kevent kev[1];
    EV_SET(kev, pid, EVFILT_PROC, EV_ADD|EV_ONESHOT, NOTE_EXIT, 0, NULL);
    kevent(_kq, kev, 1, NULL, 0, NULL);
}

- (WSAppRecord *)findAppByPID:(unsigned int)pid {
    NSEnumerator *apprecs = [apps objectEnumerator];
    WSAppRecord *app;
    while((app = [apprecs nextObject]) != nil) {
        if(app.pid == pid)
            return app;
    }
    return nil;
}

-(void)signalQuit { ready = NO; }

@end

