//
//  applist.h
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

#ifndef APPLIST_H
#define APPLIST_H
@import Foundation;
@import UIKit;

NSDictionary<NSString*, NSString*>* list_installed_apps(IdeviceProviderHandle* provider, NSString** error);
NSDictionary<NSString*, NSString*>* list_all_apps(IdeviceProviderHandle* provider, NSString** error);
NSDictionary<NSString*, NSString*>* list_hidden_system_apps(IdeviceProviderHandle* provider, NSString** error);
UIImage* getAppIcon(IdeviceProviderHandle* provider, NSString* bundleID, NSString** error);

NSDictionary *getAllAppsInfo(IdeviceProviderHandle *provider, NSString **error);
id plist_to_objc_object(plist_t plist);

#endif /* APPLIST_H */
