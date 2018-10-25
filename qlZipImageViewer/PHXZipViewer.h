
#ifndef PHXZipViewer_h
#define PHXZipViewer_h

#import <Foundation/Foundation.h>
#import "LOZIPFileWrapper.h"

NSString *PHXGetExtractPath(void);

@interface PHXZipManager : NSObject

@property (nonatomic, retain)LOZIPFileWrapper* zipFileWrapper;
@property (nonatomic, retain)NSArray* zipFileNames;
@property (nonatomic, retain)NSString* extractPath;
@property (nonatomic, retain)NSString* firstFilePath;

- (id)initWithURL:(NSURL *)url;
- (NSData *)getFirstImageData;
- (NSArray *)getImagePathList;
@end

#endif /* PHXZipViewer_h */
