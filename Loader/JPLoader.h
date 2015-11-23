//
//  JSPatch.h
//  JSPatch
//
//  Created by bang on 15/11/14.
//  Copyright (c) 2015 bang. All rights reserved.
//

#import <Foundation/Foundation.h>

const static NSString *rootUrl = @"http://7xo816.com1.z0.glb.clouddn.com/newHouse";
//static NSString *publicKey = @"-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC+1xcYsEE+ab/Ame1/HHAgfBRh\nD67I9mBYCiOJqC3lJX5RKFvtOTcF5Sf5Bz3NL/2QWPLu40+yt4EvjZ3HOUAHrVgo\n2Fjo4vpaRoEaEtaccOziPH/ASScOfL+uppNGOa0glTCZLKVZI3Go8zoutr8VDw2d\nNT7rDM/4TvPjwMYd3QIDAQAB\n-----END PUBLIC KEY-----";

static NSString *publicKey = @"-----BEGIN PUBLIC KEY-----MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDSs/E0vDEy9JDudWgnbcOyM68gog6r5xir+GVp7mcI4z5EKyKbeQGySPLai5T9K11zcQlaENDTg0qMDn7/SSM2LysJw1Aw7Lc24BZff+FQY+/I/FgyiVosfftVdeg9BnKGLRagkANgD3oqMo9yGJo1/HBiXpbUG5t6MGAOFHwKoQIDAQAB-----END PUBLIC KEY-----";

typedef void (^JPUpdateCallback)(NSError *error);

typedef enum {
    JPUpdateErrorUnzipFailed = -1001,
    JPUpdateErrorVerifyFailed = -1002,
} JPUpdateError;

@interface JPLoader : NSObject
+ (BOOL)run;
+ (void)updateToVersion:(NSInteger)version callback:(JPUpdateCallback)callback;
+ (void)runTestScriptInBundle;
+ (void)setLogger:(void(^)(NSString *log))logger;
+ (NSInteger)currentVersion;
@end