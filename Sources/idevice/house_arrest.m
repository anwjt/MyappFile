//
//  house_arrest.m
//  AppFileManager
//
//  Implementation of HouseArrest file access via lockdownd → AFC protocol.
//
//  Architecture:
//  1. Use the existing provider (from minimuxer/LocalDevVPN heartbeat)
//  2. Connect to lockdownd to get HouseArrest service port
//  3. Connect to that port via POSIX TCP socket (127.0.0.1 via minimuxer)
//  4. Send HouseArrest plist command via raw socket
//  5. Read response, then use AFC protocol on the same socket
//  6. All file operations use AFC protocol scoped to app container
//
//  This is the same approach used by 3uTools and iMazing on computers,
//  but running entirely on-device via the minimuxer tunnel.
//

#import "house_arrest.h"
#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

// HouseArrest plist command templates
static const char *HA_CMD_VEND_CONTAINER = "<plist version=\"1.0\"><dict><key>Command</key><string>VendContainer</string><key>Identifier</key><string>";
static const char *HA_CMD_VEND_DOCUMENTS = "<plist version=\"1.0\"><dict><key>Command</key><string>VendDocuments</string><key>Identifier</key><string>";
static const char *HA_CMD_SUFFIX = "</string></dict></plist>";

// AFC protocol header types
// AFC packets: [8 bytes header][payload]
// Header: [magic 8 bytes][total_len 8 bytes][this_len 8 bytes][packet_num 8 bytes][opcode 8 bytes]
#define AFC_MAGIC 0x414643324950484EULL  // "AFC2IPHN" in big-endian

// Send raw data on a socket
static ssize_t sendAll(int fd, const void *buf, size_t len) {
    size_t sent = 0;
    const char *ptr = (const char *)buf;
    while (sent < len) {
        ssize_t n = send(fd, ptr + sent, len - sent, 0);
        if (n <= 0) return -1;
        sent += n;
    }
    return sent;
}

// Receive exact amount of data from socket
static ssize_t recvAll(int fd, void *buf, size_t len) {
    size_t received = 0;
    char *ptr = (char *)buf;
    while (received < len) {
        ssize_t n = recv(fd, ptr + received, len - received, 0);
        if (n <= 0) return -1;
        received += n;
    }
    return received;
}

@implementation JITEnableContext(HouseArrest)

// Connect to HouseArrest service and return an opaque AFC client pointer scoped to the app container
- (void *)houseArrestConnectForBundleId:(NSString *)bundleId
                                                                                 command:(HouseArrestCommand)command
                                                                                     error:(NSError * _Nullable * _Nullable)outError {
    if (!provider) {
        if (outError) {
            *outError = [self errorWithStr:@"Provider not initialized! Start heartbeat first." code:-1];
        }
        return NULL;
    }
    
    // Step 1: Connect to lockdownd
    LockdowndClientHandle *lockdown = NULL;
    IdeviceFfiError *err = lockdownd_connect(provider, &lockdown);
    if (err) {
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to connect to lockdownd! Error: %s", err->message ?: "unknown"] code:err->code];
            idevice_error_free(err);
        }
        return NULL;
    }
    
    // Step 2: Start session with pairing file
    NSError *pairingError = nil;
    IdevicePairingFile *pairingFile = [self getPairingFileWithError:&pairingError];
    if (!pairingFile) {
        lockdownd_client_free(lockdown);
        if (outError) {
            *outError = pairingError ?: [self errorWithStr:@"Failed to get pairing file!" code:-2];
        }
        return NULL;
    }
    
    err = lockdownd_start_session(lockdown, pairingFile);
    if (err) {
        lockdownd_client_free(lockdown);
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to start lockdownd session! Error: %s", err->message ?: "unknown"] code:err->code];
            idevice_error_free(err);
        }
        return NULL;
    }
    
    // Step 3: Start HouseArrest service to get the port
    uint16_t port = 0;
    bool ssl = false;
    err = lockdownd_start_service(lockdown, "com.apple.mobile.house_arrest", &port, &ssl);
    if (err) {
        lockdownd_client_free(lockdown);
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to start HouseArrest service! Error: %s", err->message ?: "unknown"] code:err->code];
            idevice_error_free(err);
        }
        return NULL;
    }
    
    lockdownd_client_free(lockdown);
    
    NSLog(@"HouseArrest service port: %d", port);
    
    // Step 4: Connect to HouseArrest port via POSIX TCP socket
    // When using minimuxer/LocalDevVPN, the service port is accessible at 127.0.0.1
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        if (outError) {
            *outError = [self errorWithStr:@"Failed to create socket!" code:-3];
        }
        return NULL;
    }
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to connect to HA port %d on 127.0.0.1! Is LocalDevVPN running?", port] code:-4];
        }
        return NULL;
    }
    
    // Step 5: Send the HouseArrest plist command
    NSString *plistCmd;
    if (command == HouseArrestVendContainer) {
        plistCmd = [NSString stringWithFormat:@"%@%@%@", HA_CMD_VEND_CONTAINER, bundleId, HA_CMD_SUFFIX];
    } else {
        plistCmd = [NSString stringWithFormat:@"%@%@%@", HA_CMD_VEND_DOCUMENTS, bundleId, HA_CMD_SUFFIX];
    }
    
    NSData *plistData = [plistCmd dataUsingEncoding:NSUTF8StringEncoding];
    if (!plistData) {
        close(sock);
        if (outError) {
            *outError = [self errorWithStr:@"Failed to encode plist command" code:-5];
        }
        return NULL;
    }
    
    // Write the plist command to the socket
    if (sendAll(sock, plistData.bytes, plistData.length) < 0) {
        close(sock);
        if (outError) {
            *outError = [self errorWithStr:@"Failed to send HouseArrest command" code:-6];
        }
        return NULL;
    }
    
    // Step 6: Read the response
    uint8_t respBuf[8192];
    ssize_t respLen = recvAll(sock, respBuf, sizeof(respBuf));
    if (respLen < 0) {
        close(sock);
        if (outError) {
            *outError = [self errorWithStr:@"Failed to read HouseArrest response" code:-7];
        }
        return NULL;
    }
    
    NSString *respStr = [[NSString alloc] initWithBytes:respBuf length:respLen encoding:NSUTF8StringEncoding];
    NSLog(@"HouseArrest response: %@", respStr);
    
    // Check if response indicates an error (e.g., app not installed, no documents)
    if (respStr && [respStr containsString:@"<key>Status</key>"] &&
        ![respStr containsString:@"<string>Complete</string>"]) {
        close(sock);
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"HouseArrest returned error for bundle %@: %@", bundleId, respStr ?: @"(empty)"] code:-8];
        }
        return NULL;
    }
    
    // Step 7: Create AFC client from this socket
    // The HouseArrest service, after receiving the vend command, switches the connection
    // to AFC protocol. We can now create an AFC client on this socket.
    // 
    // Since libidevice_ffi doesn't expose raw socket-to-AFC client conversion,
    // we need to use idevice_from_fd which wraps a POSIX socket FD into an IdeviceHandle,
    // then pass it to afc_client_new.
    
    IdeviceHandle *handle = NULL;
    err = idevice_from_fd(sock, "HouseArrest-AFC", &handle);
    if (err) {
        close(sock);
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to wrap socket! Error: %s", err->message ?: "unknown"] code:-9];
            idevice_error_free(err);
        }
        return NULL;
    }
    
    AfcClientHandle *afcClient = NULL;
    err = afc_client_new(handle, &afcClient);
    if (err) {
        idevice_free(handle);
        if (outError) {
            *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to create AFC client! Error: %s", err->message ?: "unknown"] code:-10];
            idevice_error_free(err);
        }
        return NULL;
    }
    
    NSLog(@"HouseArrest + AFC connection successful for bundle: %@, port: %d", bundleId, port);
    return (void*)afcClient;
}

// List directory contents
 - (NSArray<NSString *> *)houseArrestListDir:(void *)client
                                       path:(NSString *)path
                                      error:(NSError * _Nullable * _Nullable)outError {
    if (!client) {
        if (outError) *outError = [self errorWithStr:@"Invalid AFC client!" code:-1];
        return nil;
    }
    
    char **entries = NULL;
    size_t count = 0;
    IdeviceFfiError *err = afc_list_directory((struct AfcClientHandle *)client, path.fileSystemRepresentation, &entries, &count);
    if (err) {
        if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to list directory: %s", err->message ?: "unknown"] code:err->code];
        idevice_error_free(err);
        return nil;
    }
    
    NSMutableArray<NSString *> *results = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        if (entries[i]) {
            [results addObject:@(entries[i])];
            free(entries[i]);
        }
    }
    free(entries);
    return results;
}

// Check if path is directory
- (BOOL)houseArrestIsPathDirectory:(void *)client
                              path:(NSString *)path {
    if (!client) return NO;
    
    struct AfcFileInfo info;
    memset(&info, 0, sizeof(info));
    IdeviceFfiError *err = afc_get_file_info((struct AfcClientHandle *)client, path.fileSystemRepresentation, &info);
    if (err) {
        idevice_error_free(err);
        return NO;
    }
    
    BOOL isDir = (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0);
    afc_file_info_free(&info);
    return isDir;
}

 - (BOOL)houseArrestGetFileInfo:(void *)client
                          path:(NSString *)path
                          size:(uint64_t *)outSize
                         isDir:(BOOL *)outIsDir
                         error:(NSError * _Nullable * _Nullable)outError {
    if (!client) {
        if (outError) *outError = [self errorWithStr:@"Invalid AFC client!" code:-1];
        return NO;
    }
    
    struct AfcFileInfo info;
    memset(&info, 0, sizeof(info));
    IdeviceFfiError *err = afc_get_file_info((struct AfcClientHandle *)client, path.fileSystemRepresentation, &info);
    if (err) {
        if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to get file info: %s", err->message ?: "unknown"] code:err->code];
        idevice_error_free(err);
        return NO;
    }
    
    if (outSize) *outSize = info.size;
    if (outIsDir) *outIsDir = (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0);
    afc_file_info_free(&info);
    return YES;
}

// Pull file from device to local storage
- (BOOL)houseArrestPullFile:(void *)client
               fromDevicePath:(NSString *)devicePath
                    toLocalPath:(NSString *)localPath
                        error:(NSError * _Nullable * _Nullable)outError {
    if (!client) {
        if (outError) *outError = [self errorWithStr:@"Invalid AFC client!" code:-1];
        return NO;
    }
    
    struct AfcFileHandle *handle = NULL;
    IdeviceFfiError *err = afc_file_open((struct AfcClientHandle *)client, devicePath.fileSystemRepresentation, AfcRdOnly, &handle);
    if (err) {
        if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to open device file: %s", err->message ?: "unknown"] code:err->code];
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
    
    BOOL success = [fileData writeToFile:localPath atomically:YES];
    if (!success) {
        if (outError) *outError = [self errorWithStr:@"Failed to write file locally" code:-2];
    }
    return success;
}

// Push file from local storage to device
- (BOOL)houseArrestPushFile:(void *)client
               fromLocalPath:(NSString *)localPath
              toDevicePath:(NSString *)devicePath
                     error:(NSError * _Nullable * _Nullable)outError {
    if (!client) {
        if (outError) *outError = [self errorWithStr:@"Invalid AFC client!" code:-1];
        return NO;
    }
    
    NSData *fileData = [NSData dataWithContentsOfFile:localPath];
    if (!fileData) {
        if (outError) *outError = [self errorWithStr:@"Failed to read local file" code:-2];
        return NO;
    }
    
    struct AfcFileHandle *handle = NULL;
    IdeviceFfiError *err = afc_file_open((struct AfcClientHandle *)client, devicePath.fileSystemRepresentation, AfcWrOnly, &handle);
    if (err) {
        if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to open device file for writing: %s", err->message ?: "unknown"] code:err->code];
        idevice_error_free(err);
        return NO;
    }
    
    // Write in chunks of 1MB
    size_t offset = 0;
    size_t chunkSize = 1024 * 1024;
    while (offset < fileData.length) {
        size_t remaining = fileData.length - offset;
        size_t writeSize = remaining < chunkSize ? remaining : chunkSize;
        const uint8_t *chunk = (const uint8_t *)fileData.bytes + offset;
        err = afc_file_write(handle, chunk, writeSize);
        if (err) {
            afc_file_close(handle);
            if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to write: %s", err->message ?: "unknown"] code:err->code];
            idevice_error_free(err);
            return NO;
        }
        offset += writeSize;
    }
    
    afc_file_close(handle);
    return YES;
}

// Delete file or directory (recursive)
- (BOOL)houseArrestDelete:(void *)client
                     path:(NSString *)path
                    error:(NSError * _Nullable * _Nullable)outError {
    if (!client) {
        if (outError) *outError = [self errorWithStr:@"Invalid AFC client!" code:-1];
        return NO;
    }
    
    IdeviceFfiError *err = afc_remove_path_and_contents((struct AfcClientHandle *)client, path.fileSystemRepresentation);
    if (err) {
        if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to delete: %s", err->message ?: "unknown"] code:err->code];
        idevice_error_free(err);
        return NO;
    }
    return YES;
}

// Create directory
- (BOOL)houseArrestMakeDirectory:(void *)client
                            path:(NSString *)path
                           error:(NSError * _Nullable * _Nullable)outError {
    if (!client) {
        if (outError) *outError = [self errorWithStr:@"Invalid AFC client!" code:-1];
        return NO;
    }
    
    IdeviceFfiError *err = afc_make_directory((struct AfcClientHandle *)client, path.fileSystemRepresentation);
    if (err) {
        if (outError) *outError = [self errorWithStr:[NSString stringWithFormat:@"Failed to create directory: %s", err->message ?: "unknown"] code:err->code];
        idevice_error_free(err);
        return NO;
    }
    return YES;
}

@end
