//
//  AppDelegate.m
//  JSPatch
//
//  Created by bang on 15/4/30.
//  Copyright (c) 2015年 bang. All rights reserved.
//

#import "AppDelegate.h"
#import "JPEngine.h"
#import "JPViewController.h"
#import "JPLoader.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
//    [JPEngine startEngine];
//    NSString *sourcePath = [[NSBundle mainBundle] pathForResource:@"demo" ofType:@"js"];
//    NSString *script = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:nil];
//    [JPEngine evaluateScript:script];

    NSInteger currentVersion = [JPLoader currentVersion];   //当前本地 appVersion 对应的 JSPatchVersion
    BOOL isOpenJSPatch = YES;             //是否需要 fixbug
    
    if (isOpenJSPatch) {
        
        if (currentVersion < 6) {
            
            [JPLoader updateToVersion:6 callback:^(NSError *error) {
                
                if (!error) {
                    
                    [JPLoader run];
                    return;
                }
                NSLog(@"%@", error);
            }];
        } else if (currentVersion > 0) {
            
            [JPLoader run];
        }
    }
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    JPViewController *rootViewController = [[JPViewController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:rootViewController];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
    
    return YES;
}
@end
