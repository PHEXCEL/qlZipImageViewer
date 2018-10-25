//
//  LOZIPFileWrapper.h
//  LOZIPFileWrapper
//
//  Created by Christopher Atlan on 13/08/15.
//  Copyright (c) 2015 Christopher Atlan. All rights reserved.
//

#import <Foundation/Foundation.h>


FOUNDATION_EXTERN NSString *const LOZIPFileWrapperCompressedSize;
FOUNDATION_EXTERN NSString *const LOZIPFileWrapperCompresseRation;
FOUNDATION_EXTERN NSString *const LOZIPFileWrapperEncrypted;

FOUNDATION_EXTERN NSString *const LOZIPFileWrapperErrorDomain;
FOUNDATION_EXTERN NSString *const LOZIPFileWrapperMinizipErrorCode;

typedef NS_ENUM (NSInteger, LOZIPFileWrapperError) {
    LOZIPFileWrapperErrorInternal = 1,
    LOZIPFileWrapperErrorDocumentStart,
    LOZIPFileWrapperErrorWrongPassword,
    LOZIPFileWrapperErrorPrematureDocumentEnd,
    LOZIPFileWrapperErrorFileNotFound,
};


@protocol LOZIPFileWrapperDelegate;

@interface LOZIPFileWrapper : NSObject

@property (weak) id<LOZIPFileWrapperDelegate> delegate;

// Reading ZIP Archives

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithURL:(NSURL *)URL password:(NSString *)password error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithZIPData:(NSData *)data password:(NSString *)password error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (BOOL)writeContentOfZIPFileToURL:(NSURL *)URL options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)error;

- (NSArray *)contentOfZIPFileIncludingFolders:(BOOL)includeFolders error:(NSError **)error;
- (NSDictionary *)contentAttributesOfZIPFileIncludingFolders:(BOOL)includeFolders error:(NSError **)error;

- (NSData *)contentsAtPath:(NSString *)path error:(NSError **)error;

@end


@protocol LOZIPFileWrapperDelegate <NSObject>

@optional
- (void)zipFileWrapper:(LOZIPFileWrapper *)zipFileWrapper willUnzipArchiveAtURL:(NSURL *)URL;
- (void)zipFileWrapper:(LOZIPFileWrapper *)zipFileWrapper didUnzipArchiveAtURL:(NSURL *)URL;

- (BOOL)zipFileWrapper:(LOZIPFileWrapper *)zipFileWrapper shouldUnzipFileWithName:(NSString *)fileanme attributes:(NSDictionary *)attributes;
- (void)zipFileWrapper:(LOZIPFileWrapper *)zipFileWrapper willUnzipFileWithName:(NSString *)fileanme attributes:(NSDictionary *)attributes;
- (void)zipFileWrapper:(LOZIPFileWrapper *)zipFileWrapper didUnzipFileWithName:(NSString *)fileanme attributes:(NSDictionary *)attributes;

@end
