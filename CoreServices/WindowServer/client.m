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

#import <AppKit/AppKit.h>

@interface Delegate : NSObject {
    NSWindow *win;
}
@end

@implementation Delegate
-init {
    if(self = [super init]) {
        win = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 462, 447)
                                          styleMask:NSTitledWindowMask
                                            backing:NSBackingStoreRetained
                                              defer:NO];
    }
    return self;
}

-(void)applicationWillFinishLaunching:(NSNotification *)note {
#if 0
        NSImage *img = [[NSImage alloc]
            initWithContentsOfFile:@"/usr/src/CoreServices/WindowServer/SystemUIServer/ReleaseLogo.tiff"];
        NSImageView *imgview = [NSImageView new];
        [imgview setImage:img];
        NSView *v = [win contentView];
        [v addSubview:imgview];
        [win makeKeyAndOrderFront:self];
#endif
}

@end

int main(int argc, const char *argv[]) {
    __NSInitializeProcess(argc, argv);
    
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        Delegate *del = [Delegate new];
        [NSApp setDelegate:del];
        [NSApp run];
    }

    exit(0);
}

