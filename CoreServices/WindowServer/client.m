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
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>

int main(int argc, const char *argv[]) {
    static uint8_t red = 0;
    static int fadeDirection = 1;
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

    CGContextRef ctx = CGBitmapContextCreate(buffer, 1024, 768, 8,
            1024*4, CGColorSpaceCreateDeviceRGB(), kCGImageAlphaPremultipliedFirst);

    while(ready == YES) {
        CGContextSetRGBFillColor(ctx, red/255.0, 0, 0, 1);
        CGContextFillRect(ctx, (CGRect)NSMakeRect(0,0,1024,768));

        if(fadeDirection > 0)
            if(red == 255)
                fadeDirection = -1;
            else
                ++red;
        else
            if(red == 0)
                fadeDirection = 1;
            else
                --red;
    }

    [pool drain];
    shm_unlink("/shm/app/1");
    exit(0);
}
