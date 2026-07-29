//
//  JITEnableContext.h
//  StikJIT
//
//  Created by s s on 2025/3/28.
//
@import Foundation;
@import UIKit;
#include "idevice.h"
#include "jit.h"
#include "heartbeat.h"
#include "mount.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^HeartbeatCompletionHandler)(int result, NSString *message);
typedef void (^LogFuncC)(const char* message, ...);
typedef void (^LogFunc)(NSString *message);
typedef void (^SyslogLineHandler)(NSString *line);
typedef void (^SyslogErrorHandler)(NSError *error);

@interface JITEnableContext : NSObject {
    // process
    @protected dispatch_queue_t processInspectorQueue;
    @protected IdeviceProviderHandle* provider;
        
    // syslog
    @protected dispatch_queue_t syslogQueue;
    @protected BOOL syslogStreaming;
    @protected SyslogRelayClientHandle *syslogClient;
    @protected SyslogLineHandler syslogLineHandler;
    @protected SyslogErrorHandler syslogErrorHandler;
    
    // ideviceInfo
    @protected LockdowndClientHandle *   g_client;
}
@property (class, readonly) JITEnableContext* shared;

// Expose TCP provider handle as an instance property (getter provided in .m)
@property (nonatomic, readonly, getter=getTcpProviderHandle) IdeviceProviderHandle * _Nullable tcpProviderHandle;

- (IdevicePairingFile * _Nullable)getPairingFileWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)ensureHeartbeatWithError:(NSError * _Nullable * _Nullable)err;
- (BOOL)startHeartbeat:(NSError * _Nullable * _Nullable)err;


@end

NS_ASSUME_NONNULL_END

@interface JITEnableContext(JIT)
- (BOOL)debugAppWithBundleID:(NSString*)bundleID logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback;
- (BOOL)debugAppWithPID:(int)pid logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback;
- (BOOL)launchAppWithoutDebug:(NSString*)bundleID args:(NSArray<NSString *>*)args logger:(LogFunc)logger;
@end

@interface JITEnableContext(DDI)
 - (NSUInteger)getMountedDeviceCount:(NSError * _Nullable * _Nullable)error __attribute__((swift_error(zero_result)));
 - (NSInteger)mountPersonalDDIWithImagePath:(NSString*)imagePath trustcachePath:(NSString*)trustcachePath manifestPath:(NSString*)manifestPath error:(NSError * _Nullable * _Nullable)error __attribute__((swift_error(nonzero_result)));
@end

@interface JITEnableContext(Profile)
 - (NSArray<NSData*>*)fetchAllProfiles:(NSError * _Nullable * _Nullable)error;
 - (BOOL)removeProfileWithUUID:(NSString*)uuid error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)addProfile:(NSData*)profile error:(NSError * _Nullable * _Nullable)error;
@end

@interface JITEnableContext(Process)
 - (NSArray<NSDictionary*>*)fetchProcessListWithError:(NSError * _Nullable * _Nullable)error;
 - (BOOL)killProcessWithPID:(int)pid signal:(int)signal error:(NSError * _Nullable * _Nullable)error;
@end

@interface JITEnableContext(App)
 - (UIImage*)getAppIconWithBundleId:(NSString*)bundleId error:(NSError * _Nullable * _Nullable)error;
 - (NSDictionary<NSString*, NSString*>*)getAppListWithError:(NSError * _Nullable * _Nullable)error;
 - (NSDictionary<NSString*, NSString*>*)getAllAppsWithError:(NSError * _Nullable * _Nullable)error;
 - (NSDictionary<NSString*, NSString*>*)getHiddenSystemAppsWithError:(NSError * _Nullable * _Nullable)error;
 - (NSDictionary<NSString*, id>*)getAllAppsInfoWithError:(NSError * _Nullable * _Nullable)error;
@end

@interface JITEnableContext(Syslog)
- (void)startSyslogRelayWithHandler:(SyslogLineHandler)lineHandler
                             onError:(SyslogErrorHandler)errorHandler NS_SWIFT_NAME(startSyslogRelay(handler:onError:));
- (void)stopSyslogRelay;
@end

@interface JITEnableContext(DeviceInfo)
 - (LockdowndClientHandle*)ideviceInfoInit:(NSError * _Nullable * _Nullable)error;
 - (char * _Nullable)ideviceInfoGetXMLWithLockdownClient:(LockdowndClientHandle*)lockdownClient error:(NSError * _Nullable * _Nullable)error;
@end

@interface JITEnableContext(AFC)
 - (BOOL)afcIsPathDirectory:(NSString *)path;
 - (NSArray<NSString *> *)afcListDir:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)afcPushFile:(NSString *)sourcePath toPath:(NSString *)destPath error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)afcPullFile:(NSString *)devicePath toLocalPath:(NSString *)localPath error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)afcDelete:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
@end
