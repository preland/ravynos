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
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>

int main(int argc, const char *argv[]) {
    BOOL ready = YES;

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
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
            1024*4, cs, kCGImageAlphaPremultipliedFirst);

    NSImage *png = [[NSImage alloc] initWithContentsOfFile:@"/usr/src/Logo_Assets/ravynos_white_black_256.png"];
    NSData *pngdata = [png TIFFRepresentation];
    CGDataProviderRef pngdp = CGDataProviderCreateWithCFData((__bridge CFDataRef)pngdata);
    CGImageRef img = CGImageCreate([png size].width, [png size].height, 8, 32, 4*[png size].width, cs, kCGImageAlphaLast, pngdp, NULL, false, kCGRenderingIntentDefault);

    while(ready == YES) {
        CGContextSetRGBFillColor(ctx, 160, 160, 80, 1);
        CGContextFillRect(ctx, (CGRect)NSMakeRect(0,0,1024,768));
        CGContextDrawImage(ctx, (CGRect)NSMakeRect(384,256,300,300), img);
        sleep(1);
    }

    [pool drain];
    shm_unlink("/shm/app/1");
    exit(0);
}
