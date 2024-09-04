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
#import "WindowServer.h"
#import "WSInput.h"

#undef direction // defined in mach.h
#include <linux/input.h>

@implementation WindowServer

-init {
    ready = NO;
    logLevel = WS_INFO;
    envp = NULL;
    curShell = LOGINWINDOW;
    curApp = nil;
    curWindow = nil;
    apps = [NSMutableDictionary new];
    windowsByApp = [NSMutableDictionary new];

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

    fb = [BSDFramebuffer new];
    [fb openFramebuffer:"/dev/console"];
    geometry = [fb geometry];

    [fb clear];
    input = [WSInput new];

    ready = YES;
    return self;
}

-(void)dealloc {
    curShell = NONE;
    //pthread_cancel(curShellThread);
    fb = nil;
}

-(BOOL)isReady {
    return ready;
}

-(O2BitmapContext *)context {
    return [fb context];
}
 
-(NSRect)geometry {
    return geometry;
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

/* called by WSInput. event is destroyed after this function returns */
-(void)dispatchEvent:(struct libinput_event *)event {
    enum libinput_event_type etype = libinput_event_get_type(event);
    if(logLevel >= WS_INFO)
        NSLog(@"input event: device %s type %d",
        libinput_device_get_name(libinput_event_get_device(event)), etype);
    
    switch(etype) {
        case LIBINPUT_EVENT_KEYBOARD_KEY: {
            struct libinput_event_keyboard *ke = libinput_event_get_keyboard_event(event);
            uint32_t keycode = libinput_event_keyboard_get_key(ke);
            enum libinput_key_state state = libinput_event_keyboard_get_key_state(ke);
            if(logLevel >= WS_INFO)
                NSLog(@"Input event: type=KEY key=%u state=%u", keycode, state);
            if(keycode == KEY_ESC && state == LIBINPUT_KEY_STATE_PRESSED) {
                ready = NO;
                break;
            }
        }
        default:
            if(logLevel >= WS_WARNING)
                NSLog(@"Unhandled input event type %u", etype);
    }

    if(curApp != nil) {
        /* send event to app's mach port */
        /* FIXME: should we translate to NSEvent or leave that to AppKit? */
    }
}

-(void)run {
    NSRect wingeom = NSMakeRect(100,100,1024,768);

    /* let's assume AppKit sends the path and buffer size of the window surface over mach */
    int shmfd = shm_open("/shm/app/1", O_RDWR | O_CREAT, 0644);
    void *buffer = NULL;
    if(shmfd < 0) {
        NSLog(@"Cannot create shmfd: %s", strerror(errno));
        ready = NO;
    } else {
        ftruncate(shmfd, 4*1024*768); // 32 bit 1024x768 buffer
        buffer = mmap(NULL, 4*1024*768, PROT_READ, MAP_PRIVATE, shmfd, 0);
        close(shmfd);
    }
    if(buffer == NULL) {
        NSLog(@"buffer is NULL");
        ready = NO;
    }

    O2Surface *_window = [[O2Surface alloc] initWithBytes:buffer width:1024
            height:768 bitsPerComponent:8 bytesPerRow:1024*4 colorSpace:[fb colorSpace]
            bitmapInfo:kCGImageAlphaPremultipliedFirst];

    // FIXME: lock this to vsync of actual display
    int usec = 16949; // max 59 fps
    struct timespec start, end; 
    while(ready == YES) {
        clock_gettime(CLOCK_REALTIME, &start);
        [input run:self];

        O2BitmapContext *ctx = [fb context];
        O2ContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        O2ContextFillRect(ctx, (O2Rect)geometry);
        [ctx drawImage:_window inRect:wingeom];
        [fb draw];

        wingeom.origin.x += 10;
        wingeom.origin.y += 5;
        if(wingeom.origin.x > 1000) wingeom.origin.x = 0;
        if(wingeom.origin.y > 300) wingeom.origin.y = 0;

        clock_gettime(CLOCK_REALTIME, &end);
        long s = start.tv_sec * 1000000000 + start.tv_nsec; 
        long e = end.tv_sec * 1000000000 + end.tv_nsec;
        long diff = (e - s) / 1000; // convert to usec
        if(diff < usec)
            usleep(usec - diff);
    }

    shm_unlink("/shm/app/1");
}

@end
