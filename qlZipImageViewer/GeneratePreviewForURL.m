/**
 * The MIT License (MIT)
 *
 * Copyright (c) 2015 QFish <im@QFi.sh>
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

#ifdef __OBJC__
#include <Foundation/Foundation.h>
#include <AppKit/AppKit.h>
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#import "PHXZipViewer.h"

const CFStringRef kQLPreviewPropertyPageElementXPathKey = CFSTR("PageElementXPath");

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options);
void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview);

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file
   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    // inspired by https://github.com/Marginal/QLVideo
    
    @autoreleasepool {
        NSURL *path   = ((__bridge NSURL *)(url));
        NSString *title = [path lastPathComponent];
        NSDictionary *properties;
        
        PHXZipManager *zipManager = [[PHXZipManager alloc] initWithURL:path];
        NSArray *imagePathList = [zipManager getImagePathList];

        NSString *html = @"<!DOCTYPE html>\n<html>\n<body style=\"background-color:black\">\n";
    
        if (imagePathList == nil) {
            return kQLReturnNoError;
        }
        
        NSArray * imageReps = [NSBitmapImageRep imageRepsWithContentsOfFile:zipManager.firstFilePath];
        
        NSInteger width = 0;
        NSInteger height = 0;
        
        for (NSImageRep * imageRep in imageReps) {
            if ([imageRep pixelsWide] > width) width = [imageRep pixelsWide];
            if ([imageRep pixelsHigh] > height) height = [imageRep pixelsHigh];
        }
        

    // file extract method
        for (NSString *imagePath in imagePathList) {
            html = [html stringByAppendingFormat:@"<div><div style=\"background-image:url('file://%@');background-size:contain;background-repeat:no-repeat;background-position:center center;width:%dpx;height:%dpx\"></div></div>\n", imagePath, (int) width, (int) height];
        }
        html = [html stringByAppendingString:@"</body>\n</html>\n"];
        properties = @{
                       (__bridge NSString*) kQLPreviewPropertyDisplayNameKey: title,
                       (__bridge NSString*) kQLPreviewPropertyTextEncodingNameKey: @"UTF-8",
                       (__bridge NSString *) kQLPreviewPropertyPageElementXPathKey: @"/html/body/div",
                       };


        QLPreviewRequestSetDataRepresentation(preview, (__bridge CFDataRef) [html dataUsingEncoding:NSUTF8StringEncoding], kUTTypeHTML,
                                                      (__bridge CFDictionaryRef) properties);
    }
    return noErr;
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview)
{
}
