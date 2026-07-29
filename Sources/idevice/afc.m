//
//  afc.m
//  AppFileManager
//
//  Extended AFC implementation with full file management capabilities.
//  Includes: list directory, check directory, push/pull files, delete.
//

#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
@import Foundation;

@implementation JITEnableContext(AFC)

- (BOOL)afcIsPathDirectory:(NSString *)path {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        return NO;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        return NO;
    }
    struct AfcFileInfo info;
    memset(&info, 0, sizeof(info));
    err = afc_get_file_info(client, path.fileSystemRepresentation, &info);
    BOOL is_dir = (info.st_ifmt && !strcmp(info.st_ifmt, "S_IFDIR"));
    afc_file_info_free(&info);
    afc_client_free(client);
    return is_dir;
}

- (NSArray<NSString *> *)afcListDir:(NSString *)path error:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        *error = [self errorWithStr:@"Failed to connect to AFC!" code:err->code];
        return nil;
    }
    char **entries = NULL;
    size_t count = 0;
    NSMutableArray<NSString *>* results = [NSMutableArray array];
    err = afc_list_directory(client, path.fileSystemRepresentation, &entries, &count);
    if (err) {
        *error = [self errorWithStr:[NSString stringWithFormat:@"Failed to list directory: %s", err->message ?: "unknown"] code:err->code];
        afc_client_free(client);
        idevice_error_free(err);
        return nil;
    }
    for (size_t i = 0; i < count; i++) {
        if (entries[i]) {
            [results addObject:@(entries[i])];
            free(entries[i]);
        }
    }
    free(entries);
    afc_client_free(client);
    return results;
}

- (BOOL)afcPushFile:(NSString *)sourcePath toPath:(NSString *)destPath error:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return NO;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        *error = [self errorWithStr:@"Failed to connect to AFC!" code:err->code];
        return NO;
    }
    struct AfcFileHandle *handle = NULL;
    err = afc_file_open(client, destPath.fileSystemRepresentation, AfcWrOnly, &handle);
    if (err) {
        *error = [self errorWithStr:@"Failed to open destination file on device!" code:err->code];
        afc_client_free(client);
        idevice_error_free(err);
        return NO;
    }
    NSData* fileData = [NSData dataWithContentsOfFile:sourcePath];
    if (!fileData) {
        *error = [self errorWithStr:@"Failed to read local file!" code:-2];
        afc_file_close(handle);
        afc_client_free(client);
        return NO;
    }
    err = afc_file_write(handle, (const uint8_t *)fileData.bytes, fileData.length);
    afc_file_close(handle);
    afc_client_free(client);
    if (err) {
        *error = [self errorWithStr:[NSString stringWithFormat:@"Failed to write file: %s", err->message ?: "unknown"] code:err->code];
        idevice_error_free(err);
        return NO;
    }
    return YES;
}

- (BOOL)afcPullFile:(NSString *)devicePath toLocalPath:(NSString *)localPath error:(NSError **)error {
    if (!provider) {
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return NO;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        *error = [self errorWithStr:@"Failed to connect to AFC!" code:err->code];
        return NO;
    }
    
    struct AfcFileHandle *handle = NULL;
    err = afc_file_open(client, devicePath.fileSystemRepresentation, AfcRdOnly, &handle);
    if (err) {
        *error = [self errorWithStr:[NSString stringWithFormat:@"Failed to open device file: %s", err->message ?: "unknown"] code:err->code];
        afc_client_free(client);
        idevice_error_free(err);
        return NO;
    }
    
    NSMutableData *fileData = [NSMutableData data];
    uint8_t *chunk = NULL;
    size_t chunkLen = 0;
    
    while (YES) {
        chunk = NULL;
        chunkLen = 0;
        err = afc_file_read(handle, &chunk, &chunkLen);
        if (err || chunkLen == 0) break;
        if (chunk) {
            [fileData appendBytes:chunk length:chunkLen];
            afc_file_read_data_free(chunk, chunkLen);
        }
    }
    
    afc_file_close(handle);
    afc_client_free(client);
    
    BOOL success = [fileData writeToFile:localPath atomically:YES];
    if (!success) {
        *error = [self errorWithStr:@"Failed to write file locally" code:-2];
    }
    return success;
}

- (BOOL)afcDelete:(NSString *)path error:(NSError **)error {
    if (!provider) {
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return NO;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        *error = [self errorWithStr:@"Failed to connect to AFC!" code:err->code];
        return NO;
    }
    
    err = afc_remove_path_and_contents(client, path.fileSystemRepresentation);
    if (err) {
        *error = [self errorWithStr:[NSString stringWithFormat:@"Failed to delete: %s", err->message ?: "unknown"] code:err->code];
        afc_client_free(client);
        idevice_error_free(err);
        return NO;
    }
    afc_client_free(client);
    return YES;
}

@end
