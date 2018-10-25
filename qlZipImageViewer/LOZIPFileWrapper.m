//
//  LOZIPFileWrapper.m
//  
//
//  Created by Christopher Atlan on 13/08/15.
//
//

#import "LOZIPFileWrapper.h"

#include "zip.h"
#include "unzip.h"
#include "ioapi_mem.h"
#include "minishared.h"

#include <sys/stat.h>
#include <sys/xattr.h>

#import <AssertMacros.h>


#define NSERROR_GO_TO_FIRST_FILE(error, err) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzGoToFirstFile", err]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorInternal userInfo:userInfo];  \
    }
#define NSERROR_GET_CURRENT_FILE_INFO(error, err) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzGetCurrentFileInfo", err]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorInternal userInfo:userInfo];  \
    }
#define NSERROR_OPEN_CURRENT_FILE_PASSWORD(error, err) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzOpenCurrentFilePassword", err]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorInternal userInfo:userInfo];  \
    }
#define NSERROR_MALLOC(error, err) if (error) { \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"Error allocating memory"}; \
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:userInfo]; \
    }
#define NSERROR_READ_CURRENT_FILE(error, err) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzReadCurrentFile", err]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorPrematureDocumentEnd userInfo:userInfo];  \
    }
#define NSERROR_CLOSE_CURRENT_FILE(error, err) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzCloseCurrentFile", err]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        if (*error) { \
            NSError *underlyingError = *error; \
            userInfo = @{ NSUnderlyingErrorKey : underlyingError, NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        } \
        *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorInternal userInfo:userInfo];  \
    }
#define NSERROR_GO_TO_NEXT_FILE(error, err) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzGoToNextFile", err]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)}; \
        *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorInternal userInfo:userInfo];  \
    }
#define NSERROR_CREATE_FILE(error, err, writeFilename) if (error) { \
        NSString *desc = [NSString stringWithFormat:@"error %d in opening %@", err, writeFilename]; \
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc}; \
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:userInfo]; \
    }


#define CHUNK 16384

#define WRITEBUFFERSIZE (8192)
#define MAXFILENAME     (256)


NSString *const LOZIPFileWrapperCompressedSize = @"LOZIPFileWrapperCompressedSize";
NSString *const LOZIPFileWrapperCompresseRation = @"LOZIPFileWrapperCompresseRation";
NSString *const LOZIPFileWrapperEncrypted = @"LOZIPFileWrapperEncrypted";
NSString *const LOZIPFileWrapperErrorDomain = @"LOZIPFileWrapperErrorDomain";
NSString *const LOZIPFileWrapperMinizipErrorCode = @"LOZIPFileWrapperErrorDomain";

@interface LOZIPFileWrapper () {
    zipFile zip;
    ourmemory_t *unzmem;
    NSDictionary<NSString *, NSDictionary *> *_contentAttributes;
    NSArray<NSString *> *_appleDoubleFiles;
}

// For reading
@property (copy) NSURL *URL;
@property (copy) NSData *ZIPData;
@property (copy) NSString *password;

@end

@implementation LOZIPFileWrapper

- (instancetype)initWithURL:(NSURL *)URL password:(NSString *)password error:(NSError **)error
{
    self = [super init];
    if (self)
    {
        self.URL = URL;
        self.password = password;
        
        zip = unzOpen((const char*)[[URL path] UTF8String]);
        if (zip == NULL)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"error in unzOpen" };
            if (error)
            {
                *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorDocumentStart userInfo:userInfo];
            }
            return nil;
        }
        
        if (![self openWithError:error])
        {
            return nil;
        }
        
        _contentAttributes = [self _contentAttributesOfZIPFileIncludingFolders:NO error:error];
        _appleDoubleFiles = [self _filterAppleDouble];
    }
    return self;
}

- (instancetype)initWithZIPData:(NSData *)data password:(NSString *)password error:(NSError **)error
{
    self = [super init];
    if (self)
    {
        self.ZIPData = data;
        self.password = password;
        
        zlib_filefunc_def filefunc32 = {0};
        unzmem = malloc(sizeof(ourmemory_t));
        
        unzmem->grow = 1;
        
        unzmem->size = (uint32_t)[data length];
        unzmem->base = (char *)malloc(unzmem->size);
        memcpy(unzmem->base, [data bytes], unzmem->size);
        
        fill_memory_filefunc(&filefunc32, unzmem);
        
        zip = unzOpen2("__notused__", &filefunc32);
        if (zip == NULL)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"error in unzOpen2" };
            if (error)
            {
                *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorDocumentStart userInfo:userInfo];
            }
            return nil;
        }
        
        if (![self openWithError:error])
        {
            return nil;
        }
        
        _contentAttributes = [self _contentAttributesOfZIPFileIncludingFolders:NO error:error];
        _appleDoubleFiles = [self _filterAppleDouble];
    }
    return self;
}

- (void)dealloc
{
    if (zip)
    {
        unzClose(zip);
    }
    if (unzmem)
    {
        if (unzmem->base)
        {
            free(unzmem->base);
        }
        free(unzmem);
    }
}

- (BOOL)openWithError:(NSError **)error
{
    unz_file_info64 file_info = {0};
    void* buf = NULL;
    uInt size_buf = 256; // use smaller buffer here
    int err = UNZ_OK;
    int errclose = UNZ_OK;
    
    err = unzGoToFirstFile(zip);
    if (err != UNZ_OK)
    {
        NSERROR_GO_TO_FIRST_FILE(error, err);
        return NO;
    }
    
    err = unzGetCurrentFileInfo64(zip, &file_info, NULL, 0, NULL, 0, NULL, 0);
    if (err != UNZ_OK)
    {
        NSERROR_GET_CURRENT_FILE_INFO(error, err);
        return NO;
    }
    
    err = unzOpenCurrentFilePassword(zip, [self.password UTF8String]);
    if (err != UNZ_OK)
    {
        NSERROR_OPEN_CURRENT_FILE_PASSWORD(error, err);
        return NO;
    }
    
    buf = (void*)malloc(size_buf);
    if (buf == NULL)
    {
        NSERROR_MALLOC(error, errno);
        return NO;
    }
    
    /* Read from the zip, unzip to buffer */
    int byteCopied = unzReadCurrentFile(zip, buf, size_buf);
    if (byteCopied < 0)
    {
        BOOL encrypted = ((file_info.flag & 1) != 0);
        // encrypted and -3 is our hint that the password is wrong
        if (encrypted && byteCopied == -3)
        {
            if (error)
            {
                NSString *desc = [NSString stringWithFormat:@"error %d with zipfile in unzReadCurrentFile", err];
                NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc, LOZIPFileWrapperErrorDomain : @(err)};
                *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorWrongPassword userInfo:userInfo];
            }
        }
        else
        {
            NSERROR_READ_CURRENT_FILE(error, byteCopied);
        }
    }
    
    free(buf);
    
    errclose = unzCloseCurrentFile(zip);
    if (errclose != UNZ_OK)
    {
        NSERROR_CLOSE_CURRENT_FILE(error, errclose);
    }
    
    // If we where able to read bytes without an error
    return (byteCopied >= 0);
}

#pragma mark - Reading ZIP Archives

- (BOOL)writeContentOfZIPFileToURL:(NSURL *)URL options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)error
{
    return [self _writeContentToURL:URL options:writeOptionsMask error:error];
}

- (NSArray *)contentOfZIPFileIncludingFolders:(BOOL)includeFolders error:(NSError **)error
{
    NSDictionary *contentsOfArchive = nil;
    contentsOfArchive = [self contentAttributesOfZIPFileIncludingFolders:includeFolders error:error];
    if (contentsOfArchive)
    {
        return [[contentsOfArchive keyEnumerator] allObjects];
    }
    return nil;
}

- (NSDictionary *)contentAttributesOfZIPFileIncludingFolders:(BOOL)includeFolders error:(NSError **)error
{
    NSMutableDictionary *contentsOfArchive = [_contentAttributes mutableCopy];
    [contentsOfArchive removeObjectsForKeys:_appleDoubleFiles];
    if (includeFolders)
    {
        NSMutableDictionary *contentsOfArchiveIncludingFolders = [contentsOfArchive mutableCopy];
        for (NSString *path in contentsOfArchive)
        {
            NSString *basePath = [path stringByDeletingLastPathComponent];
            while (![basePath isEqual:@""])
            {
                NSDictionary *base = contentsOfArchiveIncludingFolders[basePath];
                if (base)
                {
                    // In case the zip archive added a empty file as directory
                    if (![base[NSFileType] isEqual:NSFileTypeDirectory])
                    {
                        contentsOfArchiveIncludingFolders[basePath] = @{ NSFileType : NSFileTypeDirectory };
                    }
                }
                contentsOfArchiveIncludingFolders[basePath] = @{ NSFileType : NSFileTypeDirectory };
                
                basePath = [basePath stringByDeletingLastPathComponent];
            }
            
        }
        contentsOfArchive = contentsOfArchiveIncludingFolders;
    }
    return contentsOfArchive;
}

- (NSDictionary *)_contentAttributesOfZIPFileIncludingFolders:(BOOL)includeFolders error:(NSError **)error
{
    NSMutableDictionary *contentsOfArchive = [NSMutableDictionary dictionary];
    
    int err = unzGoToFirstFile(zip);
    if (err != UNZ_OK)
    {
        NSERROR_GO_TO_FIRST_FILE(error, err);
        return nil;
    }
    
    do
    {
        char filename_inzip[MAXFILENAME] = {0};
        unz_file_info64 file_info = {0};
        uLong ratio = 0;
        BOOL encrypted = NO;
#ifdef MORE_DETAILS_IMPL
        const char *string_method = NULL;
#endif
        
        err = unzGetCurrentFileInfo64(zip, &file_info, filename_inzip, sizeof(filename_inzip), NULL, 0, NULL, 0);
        if (err != UNZ_OK)
        {
            NSLog(@"LOZIPFileWrapper: error %d with zipfile in unzGetCurrentFileInfo", err);
            break;
        }
        
        if (file_info.uncompressed_size > 0)
            ratio = (uLong)((file_info.compressed_size*100) / file_info.uncompressed_size);
        
        /* Display a '*' if the file is encrypted */
        if ((file_info.flag & 1) != 0)
            encrypted = YES;
        
#ifdef MORE_DETAILS_IMPL
        if (file_info.compression_method == 0)
            string_method = "Stored";
        else if (file_info.compression_method == Z_DEFLATED)
        {
            uInt iLevel = (uInt)((file_info.flag & 0x6) / 2);
            if (iLevel == 0)
                string_method = "Defl:N";
            else if (iLevel == 1)
                string_method = "Defl:X";
            else if ((iLevel == 2) || (iLevel == 3))
                string_method = "Defl:F"; /* 2:fast , 3 : extra fast*/
        }
        else if (file_info.compression_method == Z_BZIP2ED)
        {
            string_method = "BZip2 ";
        }
        else
            string_method = "Unkn. ";
#endif
        
        // NSZipFileArchive seems to impl the encoding like this.
        // But not sure where NSZipFileArchive is used, BOM seems the go to impl.
        NSString *filename = [[NSString alloc] initWithBytes:filename_inzip
                                                      length:file_info.size_filename
                                                    encoding:NSUTF8StringEncoding];
        if (!filename)
        {
            filename = [[NSString alloc] initWithBytes:filename_inzip
                                                length:file_info.size_filename
                                              encoding:NSWindowsCP1252StringEncoding];
        }
        if (!filename)
        {
            filename = @"Untitled Document";
        }
        
        // Contains a path
        if ([filename rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]].location != NSNotFound)
        {
            filename = [filename stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        }
        
        
        NSDate *fileDate = nil;
        struct tm tmu_date = { 0 };
        if (dosdate_to_tm(file_info.dos_date, &tmu_date) == 0)
        {
            fileDate = [[self class] dateFromTM:&tmu_date];
        }
        
        NSMutableDictionary *itemAttributes = [NSMutableDictionary dictionary]; // Used in our delegates, includes compressed and uncompressed size.
        itemAttributes[NSFileCreationDate] = fileDate;
        itemAttributes[NSFileModificationDate] = fileDate;
        itemAttributes[NSFileSize] = @(file_info.uncompressed_size);
        itemAttributes[LOZIPFileWrapperCompressedSize] = @(file_info.compressed_size);
        itemAttributes[LOZIPFileWrapperCompresseRation] = @(ratio);
        itemAttributes[LOZIPFileWrapperEncrypted] = @(encrypted);
        
        
        if (contentsOfArchive)
        {
            contentsOfArchive[filename] = [itemAttributes copy];
        }
        
        err = unzGoToNextFile(zip);
    }
    while (err == UNZ_OK);
    
    if (err != UNZ_END_OF_LIST_OF_FILE && err != UNZ_OK)
    {
        NSERROR_GO_TO_NEXT_FILE(error, err);
        return nil;
    }
    
    return [NSDictionary dictionaryWithDictionary:contentsOfArchive];
}

- (NSData *)contentsAtPath:(NSString *)path error:(NSError **)error
{
    int ret = unzLocateFile(zip, [path UTF8String], NULL);
    if (ret == UNZ_END_OF_LIST_OF_FILE)
    {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"file not found" };
        if (error)
        {
            *error = [NSError errorWithDomain:LOZIPFileWrapperErrorDomain code:LOZIPFileWrapperErrorFileNotFound userInfo:userInfo];
        }
        return nil;
    }
    
    unz_file_info64 file_info = {0};
    void* buf = NULL;
    uInt size_buf = WRITEBUFFERSIZE;
    int err = UNZ_OK;
    int errclose = UNZ_OK;
    
    err = unzGetCurrentFileInfo64(zip, &file_info, NULL, 0, NULL, 0, NULL, 0);
    if (err != UNZ_OK)
    {
        NSERROR_GET_CURRENT_FILE_INFO(error, err);
        return nil;
    }
    
    NSMutableData *data = [NSMutableData dataWithCapacity:(NSUInteger)file_info.uncompressed_size];
    
    buf = (void*)malloc(size_buf);
    if (buf == NULL)
    {
        NSERROR_MALLOC(error, errno);
        return nil;
    }
    
    err = unzOpenCurrentFilePassword(zip, [self.password UTF8String]);
    __Require_Action_Quiet(err == UNZ_OK, _out, NSERROR_OPEN_CURRENT_FILE_PASSWORD(error, err));
    
    /* Read from the zip, unzip to buffer, and write to data */
    int byteCopied = 0;
    do
    {
        byteCopied = unzReadCurrentFile(zip, buf, size_buf);
        if (byteCopied < 0)
        {
            NSLog(@"LOZIPFileWrapper: error %d with zipfile in unzReadCurrentFile", err);
            break;
        }
        if (byteCopied == 0)
            break;
        
        [data appendBytes:buf length:byteCopied];
    }
    while (byteCopied > 0);
    
    __Require_Action_Quiet(byteCopied >= 0, _out, NSERROR_READ_CURRENT_FILE(error, byteCopied));
    
    errclose = unzCloseCurrentFile(zip);
    __Require_Action_Quiet(errclose == UNZ_OK, _out, NSERROR_CLOSE_CURRENT_FILE(error, errclose));
    
    free(buf);
    
    return [NSData dataWithData:data];
    
_out:
    free(buf);
    return nil;
}

- (BOOL)_writeContentToURL:(NSURL *)URL
                   options:(NSDataWritingOptions)writeOptionsMask
                     error:(NSError **)error
{
    NSMutableDictionary<NSString *, NSData *> *appleDoubleDataMapping = [NSMutableDictionary dictionaryWithCapacity:[_appleDoubleFiles count]];
    for (NSString *appleDoublePath in _appleDoubleFiles)
    {
        NSDictionary<NSFileAttributeKey, id> *attributes = [_contentAttributes objectForKey:appleDoublePath];
        if ([attributes fileSize] > 0)
        {
            NSData *data = [self contentsAtPath:appleDoublePath error:NULL];
            if (data)
            {
                NSString *path = [[self class] pathFromAppleDoublePath:appleDoublePath];
                if (path)
                {
                    [appleDoubleDataMapping setObject:data forKey:path];
                }
            }
        }
    }
    
    int err = unzGoToFirstFile(zip);
    if (err != UNZ_OK)
    {
        NSERROR_GO_TO_FIRST_FILE(error, err);
        return NO;
    }
    
    if ([self.delegate respondsToSelector:@selector(zipFileWrapper:willUnzipArchiveAtURL:)])
    {
        [self.delegate zipFileWrapper:self willUnzipArchiveAtURL:URL];
    }
    
    do
    {
        BOOL rtn = [self _writeCurrentFileToURL:URL appleDoubles:appleDoubleDataMapping options:writeOptionsMask error:error];
        if (!rtn)
        {
            return NO;
        }
        
        err = unzGoToNextFile(zip);
    }
    while (err == UNZ_OK);
    
    if ([self.delegate respondsToSelector:@selector(zipFileWrapper:didUnzipArchiveAtURL:)])
    {
        [self.delegate zipFileWrapper:self didUnzipArchiveAtURL:URL];
    }
    
    if (err != UNZ_END_OF_LIST_OF_FILE)
    {
        NSERROR_GO_TO_NEXT_FILE(error, err);
        return NO;
    }
    
    return YES;
}



- (BOOL)_writeCurrentFileToURL:(NSURL *)URL
                  appleDoubles:(NSDictionary<NSString *, NSData *> *)appleDoubleDataMapping
                       options:(NSDataWritingOptions)writeOptionsMask
                         error:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    unz_file_info64 file_info = {0};
    FILE* fout = NULL;
    void* buf = NULL;
    uInt size_buf = WRITEBUFFERSIZE;
    int err = UNZ_OK;
    int errclose = UNZ_OK;
    char filename_inzip[256] = {0};
    uLong ratio = 0;
    BOOL encrypted = NO;
    BOOL skip = NO;
    
    
    err = unzGetCurrentFileInfo64(zip, &file_info, filename_inzip, sizeof(filename_inzip), NULL, 0, NULL, 0);
    if (err != UNZ_OK)
    {
        NSERROR_GET_CURRENT_FILE_INFO(error, err);
        return NO;
    }
    
    if (file_info.uncompressed_size > 0)
        ratio = (uLong)((file_info.compressed_size*100) / file_info.uncompressed_size);
    
    /* Display a '*' if the file is encrypted */
    if ((file_info.flag & 1) != 0)
        encrypted = YES;
    
    // NSZipFileArchive seems to impl the encoding like this.
    // But not sure where NSZipFileArchive is used, BOM seems the go to impl.
    NSString *filename = [[NSString alloc] initWithBytes:filename_inzip
                                                  length:file_info.size_filename
                                                encoding:NSUTF8StringEncoding];
    if (!filename)
    {
        filename = [[NSString alloc] initWithBytes:filename_inzip
                                            length:file_info.size_filename
                                          encoding:NSWindowsCP1252StringEncoding];
    }
    if (!filename)
    {
        filename = @"Untitled Document";
    }
    
    // Contains a path
    if ([filename rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]].location != NSNotFound)
    {
        filename = [filename stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    }
    
    if ([_appleDoubleFiles containsObject:filename])
    {
        return YES;
    }
    
    NSData *appleDoubleData = [appleDoubleDataMapping objectForKey:filename];
    if (!appleDoubleData && [filename hasSuffix:@"/"])
    {
        NSInteger index = [filename length] - 1;
        NSString *dirname = [filename substringToIndex:index];
        appleDoubleData = [appleDoubleDataMapping objectForKey:dirname];
    }
    
    NSString *writeFilename = [[URL path] stringByAppendingPathComponent:filename];
    
    NSDate *fileDate = nil;
    struct tm tmu_date = { 0 };
    if (dosdate_to_tm(file_info.dos_date, &tmu_date))
    {
        fileDate = [[self class] dateFromTM:&tmu_date];
    }
    
    // Used for the NSFileManager APIs
    NSMutableDictionary *fileAttributes = [NSMutableDictionary dictionary];
    fileAttributes[NSFileCreationDate] = fileDate;
    fileAttributes[NSFileModificationDate] = fileDate;
    
    // Used in our delegates, includes compressed and uncompressed size.
    NSDictionary *itemAttributes = ({
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[NSFileCreationDate] = fileDate;
        dict[NSFileModificationDate] = fileDate;
        dict[NSFileSize] = @(file_info.uncompressed_size);
        dict[LOZIPFileWrapperCompressedSize] = @(file_info.compressed_size);
        dict[LOZIPFileWrapperCompresseRation] = @(ratio);
        dict[LOZIPFileWrapperEncrypted] = @(encrypted);
        [dict copy];
    });

    
    // Check if it contains directory
    BOOL isDirectory = NO;
    if (filename_inzip[file_info.size_filename-1] == '/' || filename_inzip[file_info.size_filename-1] == '\\')
    {
        isDirectory = YES;
    }
    
    buf = (void*)malloc(size_buf);
    if (buf == NULL)
    {
        NSERROR_MALLOC(error, errno);
        return NO;
    }
    
    err = unzOpenCurrentFilePassword(zip, [self.password UTF8String]);
    __Require_Action_Quiet(err == UNZ_OK, _out, NSERROR_OPEN_CURRENT_FILE_PASSWORD(error, err));
    
    /* Determine if the file should be overwritten or not and ask the user if needed */
    if ([fileManager fileExistsAtPath:writeFilename] && !isDirectory && (writeOptionsMask & NSDataWritingWithoutOverwriting))
    {
        skip = YES;
    }
    
    if (!skip && [self.delegate respondsToSelector:@selector(zipFileWrapper:shouldUnzipFileWithName:attributes:)])
    {
        if (![self.delegate zipFileWrapper:self shouldUnzipFileWithName:filename attributes:itemAttributes])
        {
            skip = YES;
        }
    }
    
    if (!skip && [self.delegate respondsToSelector:@selector(zipFileWrapper:willUnzipFileWithName:attributes:)])
    {
        [self.delegate zipFileWrapper:self willUnzipFileWithName:filename attributes:itemAttributes];
    }
    
    if (!skip)
    {
        NSString *directoryPath = writeFilename;
        if (!isDirectory)
        {
            directoryPath = [writeFilename stringByDeletingLastPathComponent];
        }
        
        NSError *createDirectoryError = nil;
        if ([fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:fileAttributes error:&createDirectoryError])
        {
            if (isDirectory && appleDoubleData)
            {
                NSDictionary *extendedAttributes = [[self class] extendedAttributesFormAppleDoubleData:appleDoubleData];
                for (NSString *extendedAttributeKey in extendedAttributes)
                {
                    NSData *extendedAttributeData = [extendedAttributes objectForKey:extendedAttributeKey];
                    if (setxattr([writeFilename UTF8String], [extendedAttributeKey UTF8String], [extendedAttributeData bytes], [extendedAttributeData length], 0, 0) == -1)
                    {
                        NSLog(@"LOZIPFileWrapper: error %d in set '%@' attribute failed: %@", errno, extendedAttributeKey, writeFilename);
                    }
                }
            }
        }
        else
        {
            NSLog(@"LOZIPFileWrapper: error createDirectoryAtPath %@", createDirectoryError);
        }
    }
    
    /* Create the file on disk so we can unzip to it */
    if (!skip && !isDirectory && (err == UNZ_OK))
    {
        fout = fopen([writeFilename UTF8String], "wb");
        __Require_Action_Quiet(fout != NULL, _out, NSERROR_CREATE_FILE(error, errno, writeFilename));
    }
    
    /* Read from the zip, unzip to buffer, and write to disk */
    if (fout != NULL)
    {
        do
        {
            err = unzReadCurrentFile(zip, buf, size_buf);
            if (err < 0)
            {
                NSLog(@"LOZIPFileWrapper: error %d with zipfile in unzReadCurrentFile", err);
                break;
            }
            if (err == 0)
                break;
            if (fwrite(buf, err, 1, fout) != 1)
            {
                NSLog(@"LOZIPFileWrapper: error %d in writing extracted file", errno);
                err = UNZ_ERRNO;
                break;
            }
        }
        while (err > 0);
        
        if (fout)
            fclose(fout);
        
        if (appleDoubleData)
        {
            NSDictionary *extendedAttributes = [[self class] extendedAttributesFormAppleDoubleData:appleDoubleData];
            for (NSString *extendedAttributeKey in extendedAttributes)
            {
                NSData *extendedAttributeData = [extendedAttributes objectForKey:extendedAttributeKey];
                if (setxattr([writeFilename UTF8String], [extendedAttributeKey UTF8String], [extendedAttributeData bytes], [extendedAttributeData length], 0, 0) == -1)
                {
                    NSLog(@"LOZIPFileWrapper: error %d in set '%@' attribute failed: %@", errno, extendedAttributeKey, writeFilename);
                }
            }
        }
        
        /* Set the time of the file that has been unzipped */
        if (err == 0)
        {
            NSError *attributesError = nil;
            if (![fileManager setAttributes:fileAttributes ofItemAtPath:writeFilename error:&attributesError])
            {
                NSLog(@"LOZIPFileWrapper: Set attributes failed: %@.", attributesError);
            }
        }
    }
    
    // Don't like reusing the err var for bytesRead count of unzReadCurrentFile.
    __Require_Action_Quiet(err == 0, _out, NSERROR_READ_CURRENT_FILE(error, err));
    
    errclose = unzCloseCurrentFile(zip);
    __Require_Action_Quiet(errclose == UNZ_OK, _out, NSERROR_CLOSE_CURRENT_FILE(error, errclose));
    
    free(buf);
    
    if ((skip == 0) && [self.delegate respondsToSelector:@selector(zipFileWrapper:didUnzipFileWithName:attributes:)])
    {
        [self.delegate zipFileWrapper:self didUnzipFileWithName:filename attributes:itemAttributes];
    }
    
    return (err == UNZ_OK);
    
_out:
    free(buf);
    return NO;
}


#pragma mark - Writing ZIP Archives





#pragma mark - Helper

+ (NSDate *)dateFromTM:(struct tm *)tmu_date
{
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    
    [c setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [c setYear:tmu_date->tm_year];
    [c setMonth:tmu_date->tm_mon + 1];
    [c setDay:tmu_date->tm_mday];
    [c setHour:tmu_date->tm_hour];
    [c setMinute:tmu_date->tm_min];
    [c setSecond:tmu_date->tm_sec];
    
    return [gregorian dateFromComponents:c];
}

#pragma mark - Apple Double

- (NSArray<NSString *> *)_filterAppleDouble
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *path in _contentAttributes)
    {
        if ([[self class] isAppleDoublePath:path])
        {
            [result addObject:path];
        }
    }
    return [result copy];
}

+ (BOOL)isAppleDoublePath:(NSString *)path
{
    return [path hasPrefix:@"__MACOSX"];
}

+ (NSString *)pathFromAppleDoublePath:(NSString *)appleDoublePath
{
    NSString *dirname = [appleDoublePath stringByDeletingLastPathComponent];
    if ([dirname hasPrefix:@"__MACOSX"])
    {
        dirname = [appleDoublePath substringFromIndex:9];
    }
    NSString *filename = [appleDoublePath lastPathComponent];
    if ([filename hasPrefix:@"._"])
    {
        filename = [filename substringFromIndex:2];
    }
    return [dirname stringByAppendingPathComponent:filename];
}

//
// Table 2-1 AppleSingle file header
// Field                               Length
// Magic number                        4 bytes
// Version number                      4 bytes
// Filler                              16 bytes
// Number of entries                   2 bytes
// Entry descriptor for each entry:
//     Entry ID                        4 bytes
//     Offset                          4 bytes
//     Length                          4 bytes
//

#define LONG_AT_OFFSET(data, offset) *((uint32_t *)((unsigned char *)&data[offset]))
#define WORD_AT_OFFSET(data, offset) *((uint16_t *)((unsigned char *)&data[offset]))

#define APPLEDOUBLE_MAGIC_NUMBER 0x00051607
#define APPLEDOUBLE_VERSION_NUMBER 0x00020000

#define APPLEDOUBLE_RESOURCEFORK_ENTRYID 2
#define APPLEDOUBLE_FINDERINFO_ENTRYID 9

+ (NSDictionary *)extendedAttributesFormAppleDoubleData:(NSData *)data
{
    NSUInteger lenght = [data length];
    unsigned char *bytes = (unsigned char *)[data bytes];
    if (lenght < 26)
        return nil;
    
    int offset = 0;
    uint32_t magicNumber = CFSwapInt32BigToHost( LONG_AT_OFFSET(bytes, offset) ); offset += 4;
    uint32_t versionNumber = CFSwapInt32BigToHost( LONG_AT_OFFSET(bytes, offset) ); offset += 4;
    if (magicNumber == APPLEDOUBLE_MAGIC_NUMBER
        && versionNumber == APPLEDOUBLE_VERSION_NUMBER)
    {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        
        // filler
        offset += 16;
        
        uint16_t numberOfEntries = CFSwapInt16BigToHost( WORD_AT_OFFSET(bytes, offset) );  offset += 2;
        for (int index = 0; index < numberOfEntries; index++)
        {
            if (offset + 12 > lenght)
                break;
            
            uint32_t entryID = CFSwapInt32BigToHost( LONG_AT_OFFSET(bytes, offset) ); offset += 4;
            uint32_t entryOffset = CFSwapInt32BigToHost( LONG_AT_OFFSET(bytes, offset) ); offset += 4;
            uint32_t entryLength = CFSwapInt32BigToHost( LONG_AT_OFFSET(bytes, offset) ); offset += 4;
            
            NSString *entryName = nil;
            if (entryID == APPLEDOUBLE_RESOURCEFORK_ENTRYID)
            {
                entryName = @XATTR_RESOURCEFORK_NAME;
            }
            else if (entryID == APPLEDOUBLE_FINDERINFO_ENTRYID)
            {
                entryName = @XATTR_FINDERINFO_NAME;
                // From man SETXATTR(2):
                // Due to historical reasons, the XATTR_FINDERINFO_NAME (defined to be
                // ``com.apple.FinderInfo'') extended attribute must be 32 bytes;
                //
                // Note (catlan): extra attributes (i.e. ``com.apple.lastuseddate#PS'')
                // are stored after the first 32 bytes.
                if (entryLength > 32)
                    entryLength = 32;
            }
            if (entryName)
            {
                NSRange entryRange = NSMakeRange(entryOffset, entryLength);
                if (lenght >= NSMaxRange(entryRange))
                {
                    NSData *entry = [data subdataWithRange:entryRange];
                    [attributes setObject:entry forKey:entryName];
                }
            }
        }
        return [attributes copy];
    }
    
    return nil;
}

@end
