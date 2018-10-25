
#import "PHXZipViewer.h"
#import "LOZIPFileWrapper.h"

NSString *PHXGetExtractPath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = [paths objectAtIndex:0];
    return [NSString stringWithFormat:@"%@/%@", path, @"work.phexcel.qlZipImageViewer"];
}

@implementation PHXZipManager

- (id)initWithURL:(NSURL *)url {
    self = [super init];
    if(self) {
        _zipFileWrapper = [[LOZIPFileWrapper alloc] initWithURL:url password:nil error:NULL];
        _zipFileNames = [_zipFileWrapper contentOfZIPFileIncludingFolders:YES error:NULL];
        // sort
        _zipFileNames = [_zipFileNames sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            if ([obj1 integerValue] > [obj2 integerValue]) {
                return (NSComparisonResult)NSOrderedDescending;
            }
            
            if ([obj1 integerValue] < [obj2 integerValue]) {
                return (NSComparisonResult)NSOrderedAscending;
            }
            return (NSComparisonResult)NSOrderedSame;
        }];
        _extractPath = PHXGetExtractPath();
        NSLog(@"%@", _extractPath);
        if (_zipFileNames > 0) {
            _firstFilePath = [NSString stringWithFormat:@"%@/%@", _extractPath, _zipFileNames[0]];
        }
    }
    return self;
}

- (NSArray *)getImagePathList {
    if (_zipFileNames.count > 0) {
        if ([_zipFileNames[0] hasSuffix:@".jpg"] ||
            [_zipFileNames[0] hasSuffix:@".png"] ||
            [_zipFileNames[0] hasSuffix:@".jpeg"]) {
            NSMutableArray *pathItems = [NSMutableArray new];
            // file extract method
            [self deleteItems];
            [_zipFileWrapper writeContentOfZIPFileToURL:[NSURL URLWithString:_extractPath] options:0 error:nil];

            for (NSString *filename in _zipFileNames) {
                [pathItems addObject:
                 [NSString stringWithFormat:@"%@/%@", _extractPath, filename]
                ];
            }
            return pathItems;
        }
    }
    return nil;
}

- (NSData *)getFirstImageData {
    if (_zipFileNames.count > 0) {
        if ([_zipFileNames[0] hasSuffix:@".jpg"] ||
            [_zipFileNames[0] hasSuffix:@".png"] ||
            [_zipFileNames[0] hasSuffix:@".jpeg"]) {
            return [_zipFileWrapper contentsAtPath:_zipFileNames[0] error:NULL];
        }
    }
    return nil;
}

- (void)deleteItems {
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    [fileMgr removeItemAtPath:_extractPath error:nil];
}

- (void)dealloc {
    NSLog(@"dealloc");
}


@end
