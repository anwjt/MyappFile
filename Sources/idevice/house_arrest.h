//
//  house_arrest.h
//  AppFileManager
//
//  HouseArrest protocol access for on-device app sandbox file management.
//
//  Architecture:
//  1. lockdownd_connect() → get LockdowndClient
//  2. lockdownd_start_session() → authenticate with pairing file
//  3. lockdownd_start_service("com.apple.mobile.house_arrest") → get port
//  4. POSIX socket connect to 127.0.0.1:port (via minimuxer tunnel)
//  5. Send plist vend command via raw socket
//  6. idevice_from_fd() → afc_client_new() → AFC client scoped to app container
//  7. afc_list_directory / afc_file_read / afc_file_write → file operations
//

#import "idevice.h"
#import "JITEnableContext.h"

// HouseArrest request types sent as plist to the service
typedef NS_ENUM(NSInteger, HouseArrestCommand) {
    HouseArrestVendContainer  = 0,  // Access full app container (Documents, Library, tmp)
    HouseArrestVendDocuments  = 1,  // Access Documents directory only (requires UIFileSharingEnabled)
};

@interface JITEnableContext(HouseArrest)

/// Connect to HouseArrest for a specific app and return an AFC client handle
/// that is scoped to that app's container.
/// @param bundleId The bundle identifier of the target app
/// @param command Whether to access the full container or just Documents
/// @param outError On failure, contains error description
/// @return AFC client opaque pointer on success, NULL on failure
- (void *)houseArrestConnectForBundleId:(NSString *)bundleId
                                                                                 command:(HouseArrestCommand)command
                                                                                     error:(NSError * _Nullable * _Nullable)outError;

/// List files in a directory within the app's sandbox via HouseArrest
/// @param client The AFC client handle obtained from houseArrestConnect
/// @param path Path relative to the sandbox root
 - (NSArray<NSString *> *)houseArrestListDir:(void *)client
                                       path:(NSString *)path
                                      error:(NSError * _Nullable * _Nullable)error;

/// Check if a path is a directory
 - (BOOL)houseArrestIsPathDirectory:(void *)client
                              path:(NSString *)path;

/// Get file info (size, type, etc.)
 - (BOOL)houseArrestGetFileInfo:(void *)client
                          path:(NSString *)path
                          size:(uint64_t *)outSize
                         isDir:(BOOL *)outIsDir
                         error:(NSError * _Nullable * _Nullable)outError;

/// Pull (download) a file from the app sandbox to local storage
 - (BOOL)houseArrestPullFile:(void *)client
               fromDevicePath:(NSString *)devicePath
                    toLocalPath:(NSString *)localPath
                        error:(NSError * _Nullable * _Nullable)error;

/// Push (upload) a file from local storage to the app sandbox
 - (BOOL)houseArrestPushFile:(void *)client
               fromLocalPath:(NSString *)localPath
              toDevicePath:(NSString *)devicePath
            error:(NSError * _Nullable * _Nullable)error;

/// Delete a file or directory in the app sandbox (recursive)
 - (BOOL)houseArrestDelete:(void *)client
                      path:(NSString *)path
                     error:(NSError * _Nullable * _Nullable)error;

/// Create a directory in the app sandbox
 - (BOOL)houseArrestMakeDirectory:(void *)client
                            path:(NSString *)path
                           error:(NSError * _Nullable * _Nullable)error;

@end
