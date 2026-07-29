//
//  AppFileManager-Bridging-Header.h
//  AppFileManager
//
//  Import all Objective-C/C headers that need to be exposed to Swift.
//

@import UIKit;

// Core idevice library bindings
#import "idevice.h"

// App list management
#import "applist.h"

// Profile management
#import "profiles.h"

// JITEnableContext - main context for device operations
#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"

// HouseArrest file access
#import "house_arrest.h"

// Private API for launching apps
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)arg1;
@end
LSApplicationWorkspace *LSApplicationWorkspaceDefaultWorkspace(void);

@interface UIDevice(Private)
@property(nonatomic, strong, readonly) NSString *buildVersion;
+ (BOOL)_hasHomeButton;
@end
