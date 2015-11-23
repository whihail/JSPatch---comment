//  JPEngine.m
//  JSPatch
//
//  Created by bang on 15/4/30.
//  Copyright (c) 2015 bang. All rights reserved.
//

#import "JPEngine.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIApplication.h>

@interface JPBoxing : NSObject
@property (nonatomic) id obj;
@property (nonatomic) void *pointer;
@property (nonatomic) Class cls;
@property (nonatomic, weak) id weakObj;
- (id)unbox;
- (void *)unboxPointer;
- (Class)unboxClass;
@end

@implementation JPBoxing

#define JPBOXING_GEN(_name, _prop, _type) \
+ (instancetype)_name:(_type)obj  \
{   \
    JPBoxing *boxing = [[JPBoxing alloc] init]; \
    boxing._prop = obj;   \
    return boxing;  \
}

JPBOXING_GEN(boxObj, obj, id)
JPBOXING_GEN(boxPointer, pointer, void *)
JPBOXING_GEN(boxClass, cls, Class)
JPBOXING_GEN(boxWeakObj, weakObj, id)

/**
 *  打开被包装对象
 *
 *  @return 被包装的对象
 */
- (id)unbox
{
    if (self.obj) return self.obj;
    if (self.weakObj) return self.weakObj;
    return self;
}

/**
 *  获取被包装对象的指针
 *
 *  @return 被包装对象的指针
 */
- (void *)unboxPointer
{
    return self.pointer;
}

/**
 *  获得被包装对象的类对象
 *
 *  @return 被包装对象的类对象
 */
- (Class)unboxClass
{
    return self.cls;
}
@end



@implementation JPEngine

static JSContext *_context;
static NSString *_regexStr = @"(?<!\\\\)\\.\\s*(\\w+)\\s*\\(";
static NSString *_replaceStr = @".__c(\"$1\")(";
static NSRegularExpression* _regex;
static NSObject *_nullObj;
static NSObject *_nilObj;
static NSMutableDictionary *registeredStruct;

#pragma mark - APIS

+ (void)startEngine
{
    if (![JSContext class] || _context) {
        return;
    }
    
    JSContext *context = [[JSContext alloc] init];
    
    /**
     *  在context的执行环境下，为js增加_OC_defineClass方法对象，此js方法可以传参调用OC中的block，下面几个同理
     */
    context[@"_OC_defineClass"] = ^(NSString *classDeclaration, JSValue *instanceMethods, JSValue *classMethods) {
        return defineClass(classDeclaration, instanceMethods, classMethods);
    };
    
    context[@"_OC_callI"] = ^id(JSValue *obj, NSString *selectorName, JSValue *arguments, BOOL isSuper) {
        return callSelector(nil, selectorName, arguments, obj, isSuper);
    };
    context[@"_OC_callC"] = ^id(NSString *className, NSString *selectorName, JSValue *arguments) {
        return callSelector(className, selectorName, arguments, nil, NO);
    };
    context[@"_OC_formatJSToOC"] = ^id(JSValue *obj) {
        return formatJSToOC(obj);
    };
    
    context[@"_OC_formatOCToJS"] = ^id(JSValue *obj) {
        return formatOCToJS([obj toObject]);
    };
    
    context[@"__weak"] = ^id(JSValue *jsval) {
        id obj = formatJSToOC(jsval);
        return [[JSContext currentContext][@"_formatOCToJS"] callWithArguments:@[formatOCToJS([JPBoxing boxWeakObj:obj])]];
    };

    context[@"__strong"] = ^id(JSValue *jsval) {
        id obj = formatJSToOC(jsval);
        return [[JSContext currentContext][@"_formatOCToJS"] callWithArguments:@[formatOCToJS(obj)]];
    };

    __weak JSContext *weakCtx = context;
    context[@"dispatch_after"] = ^(double time, JSValue *func) {
        id currSelf = formatJSToOC(weakCtx[@"self"]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(time * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            JSValue *prevSelf = weakCtx[@"self"];
            weakCtx[@"self"] = formatOCToJS([JPBoxing boxWeakObj:currSelf]);
            [func callWithArguments:nil];
            weakCtx[@"self"] = prevSelf;
        });
    };
    
    context[@"dispatch_async_main"] = ^(JSValue *func) {
        id currSelf = formatJSToOC(weakCtx[@"self"]);
        dispatch_async(dispatch_get_main_queue(), ^{
            JSValue *prevSelf = weakCtx[@"self"];
            weakCtx[@"self"] = formatOCToJS([JPBoxing boxWeakObj:currSelf]);
            [func callWithArguments:nil];
            weakCtx[@"self"] = prevSelf;
        });
    };
    
    context[@"dispatch_sync_main"] = ^(JSValue *func) {
        if ([NSThread currentThread].isMainThread) {
            [func callWithArguments:nil];
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [func callWithArguments:nil];
            });
        }
    };
    
    context[@"dispatch_async_global_queue"] = ^(JSValue *func) {
        id currSelf = formatJSToOC(weakCtx[@"self"]);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            JSValue *prevSelf = weakCtx[@"self"];
            weakCtx[@"self"] = formatOCToJS([JPBoxing boxWeakObj:currSelf]);
            [func callWithArguments:nil];
            weakCtx[@"self"] = prevSelf;
        });
    };
    
    context[@"releaseTmpObj"] = ^void(JSValue *jsVal) {
        if ([[jsVal toObject] isKindOfClass:[NSDictionary class]]) {
            void *pointer =  [(JPBoxing *)([jsVal toObject][@"__obj"]) unboxPointer];
            id obj = *((__unsafe_unretained id *)pointer);
            @synchronized(_TMPMemoryPool) {
                [_TMPMemoryPool removeObjectForKey:[NSNumber numberWithInteger:[obj hash]]];
            }
        }
    };

    context[@"_OC_log"] = ^() {
        NSArray *args = [JSContext currentArguments];
        for (JSValue *jsVal in args) {
            NSLog(@"JSPatch.log: %@", formatJSToOC(jsVal));
        }
    };
    
    context[@"_OC_catch"] = ^(JSValue *msg, JSValue *stack) {
        NSAssert(NO, @"js exception, \nmsg: %@, \nstack: \n %@", [msg toObject], [stack toObject]);
    };
    
    context.exceptionHandler = ^(JSContext *con, JSValue *exception) {
        NSLog(@"%@", exception);
        NSAssert(NO, @"js exception: %@", exception);
    };
    
    _nullObj = [[NSObject alloc] init];
    context[@"_OC_null"] = formatOCToJS(_nullObj);
    
    _context = context;
    
    _nilObj = [[NSObject alloc] init];
    _JSMethodSignatureLock = [[NSLock alloc] init];
    _JSMethodForwardCallLock = [[NSRecursiveLock alloc] init];
    registeredStruct = [[NSMutableDictionary alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"JSPatch" ofType:@"js"];
    NSAssert(path, @"can't find JSPatch.js");
    NSString *jsCore = [[NSString alloc] initWithData:[[NSFileManager defaultManager] contentsAtPath:path] encoding:NSUTF8StringEncoding];
    
    if ([_context respondsToSelector:@selector(evaluateScript:withSourceURL:)]) {
        [_context evaluateScript:jsCore withSourceURL:[NSURL URLWithString:@"JSPatch.js"]];   // withSourceURL指定的JSPatch.js是指jsCore在js调试器下的文件名
    } else {
        [_context evaluateScript:jsCore];
    }
}

+ (JSValue *)evaluateScript:(NSString *)script
{
    return [self evaluateScript:script withSourceURL:[NSURL URLWithString:@"main.js"]];
}

+ (JSValue *)evaluateScriptWithPath:(NSString *)filePath
{
    NSArray *components = [filePath componentsSeparatedByString:@"/"];
    NSString *fileName = [components lastObject];
    NSString *script = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    return [self evaluateScript:script withSourceURL:[NSURL URLWithString:fileName]];
}

/**
 *  用正则将 js 脚本 format 成类似 __c(methodName) 的形式。
 *  如本来是 UIView.alloc().init() ,format 之后变成 UIView.__c(alloc)().__c(init).()
 *
 *  @param script      js脚本文件字符串
 *  @param resourceURL 设置js调试时的文件名
 *
 *  @return JSValue
 */
+ (JSValue *)evaluateScript:(NSString *)script withSourceURL:(NSURL *)resourceURL
{
    if (!script || ![JSContext class]) {
        NSAssert(script, @"script is nil");
        return nil;
    }
    
    if (!_regex) {
        _regex = [NSRegularExpression regularExpressionWithPattern:_regexStr options:0 error:nil];
    }
    NSString *formatedScript = [NSString stringWithFormat:@"try{%@}catch(e){_OC_catch(e.message, e.stack)}", [_regex stringByReplacingMatchesInString:script options:0 range:NSMakeRange(0, script.length) withTemplate:_replaceStr]];
    @try {
        if ([_context respondsToSelector:@selector(evaluateScript:withSourceURL:)]) {
            return [_context evaluateScript:formatedScript withSourceURL:resourceURL];
        } else {
            return [_context evaluateScript:formatedScript];
        }
    }
    @catch (NSException *exception) {
        NSAssert(NO, @"%@", exception);
    }
    return nil;
}

+ (JSContext *)context
{
    return _context;
}

+ (void)addExtensions:(NSArray *)extensions
{
    if (![JSContext class]) {
        return;
    }
    NSAssert(_context, @"please call [JPEngine startEngine]");
    for (NSString *className in extensions) {
        Class extCls = NSClassFromString(className);
        [extCls main:_context];
    }
}

+ (void)defineStruct:(NSDictionary *)defineDict
{
    @synchronized (_context) {
        [registeredStruct setObject:defineDict forKey:defineDict[@"name"]];
    }
}

+ (NSMutableDictionary *)registeredStruct
{
    return registeredStruct;
}

+ (void)handleMemoryWarning {
    [_JSMethodSignatureLock lock];
    _JSMethodSignatureCache = nil;
    [_JSMethodSignatureLock unlock];
}

#pragma mark - Implements

static NSMutableDictionary *_JSOverideMethods;
static NSMutableDictionary *_TMPMemoryPool;
static NSRegularExpression *countArgRegex;
static NSMutableDictionary *_propKeys;
static NSMutableDictionary *_JSMethodSignatureCache;
static NSLock              *_JSMethodSignatureLock;
static NSRecursiveLock     *_JSMethodForwardCallLock;

static const void *propKey(NSString *propName) {
    if (!_propKeys) _propKeys = [[NSMutableDictionary alloc] init];
    id key = _propKeys[propName];
    if (!key) {
        key = [propName copy];
        [_propKeys setObject:key forKey:propName];
    }
    return (__bridge const void *)(key);
}

/**
 *  获取添加（添加）的成员变量
 *
 *  @param slf      发消息的对象
 *  @param selector 发消息的选择器
 *  @param propName 获取的成员变量名称
 *
 *  @return 成员变量（空）
 */
static id getPropIMP(id slf, SEL selector, NSString *propName) {
    return objc_getAssociatedObject(slf, propKey(propName));
}
static void setPropIMP(id slf, SEL selector, id val, NSString *propName) {
    objc_setAssociatedObject(slf, propKey(propName), val, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/**
 *  判断某个协议中是否包含某个（实例或对象）方法
 *
 *  @param protocolName     协议名
 *  @param selectorName     选择器名
 *  @param isInstanceMethod 是否是实例方法
 *  @param isRequired       是否是必须实现的方法
 *
 *  @return 如果协议中没有此方法，放回NULL，如果协议中有此方法，返回此方法参数的类型编码
 */
static char *methodTypesInProtocol(NSString *protocolName, NSString *selectorName, BOOL isInstanceMethod, BOOL isRequired)
{
    Protocol *protocol = objc_getProtocol([trim(protocolName) cStringUsingEncoding:NSUTF8StringEncoding]);
    unsigned int selCount = 0;
    struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocol, isRequired, isInstanceMethod, &selCount); //得到协议的（实例或类）方法数组
    for (int i = 0; i < selCount; i ++) {     //遍历协议的方法数组，如果在数组中找到和selectorName相等的selector，则返回此selector的返回值参数列表的类型编码
        if ([selectorName isEqualToString:NSStringFromSelector(methods[i].name)]) {
            char *types = malloc(strlen(methods[i].types) + 1);
            strcpy(types, methods[i].types);
            free(methods);
            return types;
        }
    }
    free(methods);
    return NULL;
}

/**
 *  用js方法替换OC类中的实例方法和类方法
 *
 *  @param classDeclaration 类名:父类名<协议名,协议名...>   这种格式的字符串
 *  @param instanceMethods  需要替换的实例方法名以及js方法实现的字典
 *  @param classMethods     需要替换的类方法名以及js方法实现的字典
 *
 *  @return @{@"cls": className} 格式的字典，className表示需要替换方法的类名
 */
static NSDictionary *defineClass(NSString *classDeclaration, JSValue *instanceMethods, JSValue *classMethods)
{
    NSString *className;    //需要替换或者新增的类名
    NSString *superClassName;    //父类名
    NSString *protocolNames;     //遵守的协议名，多个以“,”分隔
    
    /**
     *  通过NSScanner扫描字符classDeclaration，分别给className，superClassName，protocolNames赋值
     */
    NSScanner *scanner = [NSScanner scannerWithString:classDeclaration];
    [scanner scanUpToString:@":" intoString:&className];
    if (!scanner.isAtEnd) {
        scanner.scanLocation = scanner.scanLocation + 1;
        [scanner scanUpToString:@"<" intoString:&superClassName];
        if (!scanner.isAtEnd) {
            scanner.scanLocation = scanner.scanLocation + 1;
            [scanner scanUpToString:@">" intoString:&protocolNames];
        }
    }
    
    /**
     *  将遵守的协议解析用数组protocols保存
     */
    NSArray *protocols = [protocolNames componentsSeparatedByString:@","];
    if (!superClassName) superClassName = @"NSObject";
    className = trim(className);
    superClassName = trim(superClassName);
    
    
    /**
     *  通过className在runtime获得类对象，如cls在内存中不存在，则根据className，superClassName通过runtime创建这个类对象并在内存中注册一个新的类
     */
    Class cls = NSClassFromString(className);
    if (!cls) {
        Class superCls = NSClassFromString(superClassName);
        cls = objc_allocateClassPair(superCls, className.UTF8String, 0);
        objc_registerClassPair(cls);
    }
    
    /**
     *  如果 i = 0，遍历需要替换的实例方法字典；如果 i = 1，遍历需要替换的类方法字典
     */
    for (int i = 0; i < 2; i ++) {
        BOOL isInstance = i == 0;      //如果 i == 0 则isInstace为YES
        JSValue *jsMethods = isInstance ? instanceMethods: classMethods;   //如果isInstance为YES，则jsMethod为实例方法组,否则为类方法组
        
        Class currCls = isInstance ? cls: objc_getMetaClass(className.UTF8String);    //如果isInstance为YES，则currCls为cls，否则currCls为cls类的元类
        NSDictionary *methodDict = [jsMethods toDictionary];   //将JSValue类型的jsMethods转化为OC中的字典类型的methodDict
        
        /**
         *  遍历js方法对象字典
         */
        for (NSString *jsMethodName in methodDict.allKeys) {
            JSValue *jsMethodArr = [jsMethods valueForProperty:jsMethodName];
            int numberOfArg = [jsMethodArr[0] toInt32];   //获取jsMethodName的参数个数
            
            /**
             *  将jsMethodName的js方法名转化为OC方法名 类似js方法名是sdf_sfsdf_fsadg_fsag_fasd，转化之后变成sdf:sfsdf:fsadg:fsag:fasd
             */
            NSString *tmpJSMethodName = [jsMethodName stringByReplacingOccurrencesOfString:@"__" withString:@"-"];
            NSString *selectorName = [tmpJSMethodName stringByReplacingOccurrencesOfString:@"_" withString:@":"];
            selectorName = [selectorName stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
            
            /**
             *  完善OC方法名selectorName，多参数情况下补齐“：”号
             */
            if (!countArgRegex) {
                countArgRegex = [NSRegularExpression regularExpressionWithPattern:@":" options:NSRegularExpressionCaseInsensitive error:nil];
            }
            NSUInteger numberOfMatches = [countArgRegex numberOfMatchesInString:selectorName options:0 range:NSMakeRange(0, [selectorName length])];
            if (numberOfMatches < numberOfArg) {
                selectorName = [selectorName stringByAppendingString:@":"];
            }
            
            
            JSValue *jsMethod = jsMethodArr[1];   //取出js方法对象
            if (class_respondsToSelector(currCls, NSSelectorFromString(selectorName))) {   //判断currCls的实例对象是否能响应selectorName
                overrideMethod(currCls, selectorName, jsMethod, !isInstance, NULL);    //用js方法替换OC方法的实现(其实调用js方法是在forwardInvocation方法中进行的)，这里不太好描述，具体看overrideMethod函数和JPForwardInvocation函数。
            } else {                   //如果currCls的实例对象不能响应selectorName
                BOOL overrided = NO;
                for (NSString *protocolName in protocols) {                 //遍历遵守的协议名数组
                    char *types = methodTypesInProtocol(protocolName, selectorName, isInstance, YES);   //判断某个协议中是否包含某个（实例或对象）必须实现的方法,如果包含，则得到方法参数列表的类型编码
                    if (!types) types = methodTypesInProtocol(protocolName, selectorName, isInstance, NO);  //判断某个协议中是否包含某个（实例或对象）可选实现的方法,如果包含，则得到方法参数列表的类型编码
                    if (types) {   //如果在协议中找到此方法，用js方法替换OC方法的实现
                        overrideMethod(currCls, selectorName, jsMethod, !isInstance, types);
                        free(types);
                        overrided = YES;
                        break;
                    }
                }
                if (!overrided) {   //如果currCls的实例对象不能响应此SEL，遵守的协议中也没有此方法，那么直接在类中添加此方法，方法实现为空，然后用js方法替换此空实现OC方法
                    NSMutableString *typeDescStr = [@"@@:" mutableCopy];  //此处表示此方法的返回值为对象，第二个和第三个是默认的执行对象和执行的SEL
                    for (int i = 0; i < numberOfArg; i ++) {
                        [typeDescStr appendString:@"@"];
                    }
                    overrideMethod(currCls, selectorName, jsMethod, !isInstance, [typeDescStr cStringUsingEncoding:NSUTF8StringEncoding]);
                }
            }
        }
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    class_addMethod(cls, @selector(getProp:), (IMP)getPropIMP, "@@:@");    //为cls添加找到关联的成员变量的方法
    class_addMethod(cls, @selector(setProp:forKey:), (IMP)setPropIMP, "v@:@@");   //为cls添加关联成员变量的方法
#pragma clang diagnostic pop

    return @{@"cls": className};
}

/**
 *  通过类和selectorName得到存储在_JSOverideMethods字典中的js方法的JSValue值
 *
 *  @param slf          The object you want to inspect.
 *  @param selectorName 需要替换的selectorName
 *
 *  @return js方法对象的JSValue值
 */
static JSValue* getJSFunctionInObjectHierachy(id slf, NSString *selectorName)
{
    Class cls = object_getClass(slf);
    JSValue *func = _JSOverideMethods[cls][selectorName];
    while (!func) {
        cls = class_getSuperclass(cls);
        if (!cls) {
            NSCAssert(NO, @"warning can not find selector %@", selectorName);
            return nil;
        }
        func = _JSOverideMethods[cls][selectorName];
    }
    return func;
}

/**
 *  自定义所有需要替换方法的对象的forwardInvocation:方法的IMP函数指针实现
 */
#pragma clang diagnostic pop
static void JPForwardInvocation(id slf, SEL selector, NSInvocation *invocation)
{
    NSMethodSignature *methodSignature = [invocation methodSignature];
    NSInteger numberOfArguments = [methodSignature numberOfArguments];
    
    NSString *selectorName = NSStringFromSelector(invocation.selector);
    NSString *JPSelectorName = [NSString stringWithFormat:@"_JP%@", selectorName];
    SEL JPSelector = NSSelectorFromString(JPSelectorName);
    
    //如果sef对象不能响应JPSelector消息，则使用NSInvocation执行老方法也就是ORIGforwardInvocation:方法
    if (!class_respondsToSelector(object_getClass(slf), JPSelector)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
        SEL origForwardSelector = @selector(ORIGforwardInvocation:);
        NSMethodSignature *methodSignature = [slf methodSignatureForSelector:origForwardSelector];
        NSInvocation *forwardInv= [NSInvocation invocationWithMethodSignature:methodSignature];
        [forwardInv setTarget:slf];
        [forwardInv setSelector:origForwardSelector];
        [forwardInv setArgument:&invocation atIndex:2];
        [forwardInv invoke];
        return;
#pragma clang diagnostic pop
    }

    NSMutableArray *argList = [[NSMutableArray alloc] init];    //保存js方法需要的参数列表
    if ([slf class] == slf) {         //如果sef是类对象
        [argList addObject:[JSValue valueWithObject:@{@"__clsName": NSStringFromClass([slf class])} inContext:_context]];  //invocation参数0，也就是target作为js方法的第一个参数
    } else {                         //否则sef是实例对象，用JPBoxing包装弱引用对象
        [argList addObject:[JPBoxing boxWeakObj:slf]];
    }
    
    for (NSUInteger i = 2; i < numberOfArguments; i++) {
        const char *argumentType = [methodSignature getArgumentTypeAtIndex:i];
        switch(argumentType[0] == 'r' ? argumentType[1] : argumentType[0]) {      //如果参数的类型编码的第一个字符是‘r’,则取第二个字符，r表示const，详情请见 Apple 文档
        
            #define JP_FWD_ARG_CASE(_typeChar, _type) \
            case _typeChar: {   \
                _type arg;  \
                [invocation getArgument:&arg atIndex:i];    \
                [argList addObject:@(arg)]; \
                break;  \
            }                            //此宏的作用是通过参数类型编码字符得到参数的类型，并用此类型的实例对象地址设置invocation的第i个参数
            
            /**
             *  若果是各种基本类型，转化成NSNuber类型传给js
             */
            JP_FWD_ARG_CASE('c', char)
            JP_FWD_ARG_CASE('C', unsigned char)
            JP_FWD_ARG_CASE('s', short)
            JP_FWD_ARG_CASE('S', unsigned short)
            JP_FWD_ARG_CASE('i', int)
            JP_FWD_ARG_CASE('I', unsigned int)
            JP_FWD_ARG_CASE('l', long)
            JP_FWD_ARG_CASE('L', unsigned long)
            JP_FWD_ARG_CASE('q', long long)
            JP_FWD_ARG_CASE('Q', unsigned long long)
            JP_FWD_ARG_CASE('f', float)
            JP_FWD_ARG_CASE('d', double)
            JP_FWD_ARG_CASE('B', BOOL)
            case '@': {               //如果是实例对象类型，直接传__unsafe_unretained id 类型
                __unsafe_unretained id arg;
                [invocation getArgument:&arg atIndex:i];
                if ([arg isKindOfClass:NSClassFromString(@"NSBlock")]) {
                    [argList addObject:(arg ? [arg copy]: _nilObj)];
                } else {
                    [argList addObject:(arg ? arg: _nilObj)];
                }
                break;
            }
            case '{': {              //如果是结构体
                NSString *typeString = extractStructName([NSString stringWithUTF8String:argumentType]);
                #define JP_FWD_ARG_STRUCT(_type, _transFunc) \
                if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
                    _type arg; \
                    [invocation getArgument:&arg atIndex:i];    \
                    [argList addObject:[JSValue _transFunc:arg inContext:_context]];  \
                    break; \
                }
                JP_FWD_ARG_STRUCT(CGRect, valueWithRect)
                JP_FWD_ARG_STRUCT(CGPoint, valueWithPoint)
                JP_FWD_ARG_STRUCT(CGSize, valueWithSize)
                JP_FWD_ARG_STRUCT(NSRange, valueWithRange)
                
                @synchronized (_context) {
                    NSDictionary *structDefine = registeredStruct[typeString];
                    if (structDefine) {
                        size_t size = sizeOfStructTypes(structDefine[@"types"]);
                        if (size) {
                            void *ret = malloc(size);
                            [invocation getArgument:ret atIndex:i];
                            NSDictionary *dict = getDictOfStruct(ret, structDefine);
                            [argList addObject:[JSValue valueWithObject:dict inContext:_context]];
                            free(ret);
                            break;
                        }
                    }
                }
                
                break;
            }
            case ':': {            //如果是选择器类型，直接传字符串给js
                SEL selector;
                [invocation getArgument:&selector atIndex:i];
                NSString *selectorName = NSStringFromSelector(selector);
                [argList addObject:(selectorName ? selectorName: _nilObj)];
                break;
            }
            case '^':             //指针类型
            case '*': {           //C语言字符串类型，用JPBoxing包装指针传递给js
                void *arg;
                [invocation getArgument:&arg atIndex:i];
                [argList addObject:[JPBoxing boxPointer:arg]];
                break;
            }
            case '#': {          //类类型，用JPBoxing包装类传递给js
                Class arg;
                [invocation getArgument:&arg atIndex:i];
                [argList addObject:[JPBoxing boxClass:arg]];
                break;
            }
            default: {          //不能识别的类型
                NSLog(@"error type %s", argumentType);
                break;
            }
        }
    }
    
    
    NSArray *params = _formatOCToJSList(argList);   //将参数列表中的OC类型转化成JS类型
    const char *returnType = [methodSignature methodReturnType];   //获得方法返回值的类型编码

    switch (returnType[0] == 'r' ? returnType[1] : returnType[0]) {   //如果方法返回值的类型编码的第一个字符是‘r’,则取第二个字符
        #define JP_FWD_RET_CALL_JS \
            JSValue *fun = getJSFunctionInObjectHierachy(slf, JPSelectorName); \
            JSValue *jsval; \
            [_JSMethodForwardCallLock lock];   \
            jsval = [fun callWithArguments:params]; \
            [_JSMethodForwardCallLock unlock]; \
            while (![jsval isNull] && ![jsval isUndefined] && [jsval hasProperty:@"__isPerformInOC"]) { \
                NSArray *args = nil;  \
                JSValue *cb = jsval[@"cb"]; \
                if ([jsval hasProperty:@"sel"]) {   \
                    id callRet = callSelector(![jsval[@"clsName"] isUndefined] ? [jsval[@"clsName"] toString] : nil, [jsval[@"sel"] toString], jsval[@"args"], ![jsval[@"obj"] isUndefined] ? jsval[@"obj"] : nil, NO);  \
                    args = @[[_context[@"_formatOCToJS"] callWithArguments:callRet ? @[callRet] : _formatOCToJSList(@[_nilObj])]];  \
                }   \
                [_JSMethodForwardCallLock lock];    \
                jsval = [cb callWithArguments:args];  \
                [_JSMethodForwardCallLock unlock];  \
            }                                            //此宏的作用是传参转发消息给js方法，其实就是调用js方法

        #define JP_FWD_RET_CASE_RET(_typeChar, _type, _retCode)   \
            case _typeChar : { \
                JP_FWD_RET_CALL_JS \
                _retCode \
                [invocation setReturnValue:&ret];\
                break;  \
            }            //此宏的作用执行js方法并根据invocation的返回的值类型编码字符设置的js方法的返回值类型，因为js方法的返回值类型都是JSValue需要转换，用于返回值是id,指针，类，选择器类型

            /**
             *  此宏的作用执行js方法并根据invocation的返回的值类型编码字符设置的js方法的返回值类型，因为js方法的返回值类型都是JSValue需要转换，用于返回值是C语言基本类型
             */
        #define JP_FWD_RET_CASE(_typeChar, _type, _typeSelector)   \
            JP_FWD_RET_CASE_RET(_typeChar, _type, _type ret = [[jsval toObject] _typeSelector];) \

        #define JP_FWD_RET_CODE_ID \
            id ret = formatJSToOC(jsval); \
            if (ret == _nilObj ||   \
                ([ret isKindOfClass:[NSNumber class]] && strcmp([ret objCType], "c") == 0 && ![ret boolValue])) ret = nil;  \

        #define JP_FWD_RET_CODE_POINTER    \
            void *ret; \
            id obj = formatJSToOC(jsval); \
            if ([obj isKindOfClass:[JPBoxing class]]) { \
                ret = [((JPBoxing *)obj) unboxPointer]; \
            }

        #define JP_FWD_RET_CODE_CLASS    \
            Class ret;   \
            id obj = formatJSToOC(jsval); \
            if ([obj isKindOfClass:[JPBoxing class]]) { \
                ret = [((JPBoxing *)obj) unboxClass]; \
            }

        #define JP_FWD_RET_CODE_SEL    \
            SEL ret;   \
            id obj = formatJSToOC(jsval); \
            if ([obj isKindOfClass:[NSString class]]) { \
                ret = NSSelectorFromString(obj); \
            }

        JP_FWD_RET_CASE_RET('@', id, JP_FWD_RET_CODE_ID)
        JP_FWD_RET_CASE_RET('^', void*, JP_FWD_RET_CODE_POINTER)
        JP_FWD_RET_CASE_RET('*', void*, JP_FWD_RET_CODE_POINTER)
        JP_FWD_RET_CASE_RET('#', Class, JP_FWD_RET_CODE_CLASS)
        JP_FWD_RET_CASE_RET(':', SEL, JP_FWD_RET_CODE_SEL)

        JP_FWD_RET_CASE('c', char, charValue)
        JP_FWD_RET_CASE('C', unsigned char, unsignedCharValue)
        JP_FWD_RET_CASE('s', short, shortValue)
        JP_FWD_RET_CASE('S', unsigned short, unsignedShortValue)
        JP_FWD_RET_CASE('i', int, intValue)
        JP_FWD_RET_CASE('I', unsigned int, unsignedIntValue)
        JP_FWD_RET_CASE('l', long, longValue)
        JP_FWD_RET_CASE('L', unsigned long, unsignedLongValue)
        JP_FWD_RET_CASE('q', long long, longLongValue)
        JP_FWD_RET_CASE('Q', unsigned long long, unsignedLongLongValue)
        JP_FWD_RET_CASE('f', float, floatValue)
        JP_FWD_RET_CASE('d', double, doubleValue)
        JP_FWD_RET_CASE('B', BOOL, boolValue)

        case 'v': {      //方法返回值类型为void，直接执行js方法
            JP_FWD_RET_CALL_JS
            break;
        }
        
        case '{': {          //如果返回值为结构体，JavaScriptCore原生支持toRect，toPoint，toSize，toRange类型
            NSString *typeString = extractStructName([NSString stringWithUTF8String:returnType]);
            #define JP_FWD_RET_STRUCT(_type, _funcSuffix) \
            if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
                JP_FWD_RET_CALL_JS \
                _type ret = [jsval _funcSuffix]; \
                [invocation setReturnValue:&ret];\
                break;  \
            }
            JP_FWD_RET_STRUCT(CGRect, toRect)
            JP_FWD_RET_STRUCT(CGPoint, toPoint)
            JP_FWD_RET_STRUCT(CGSize, toSize)
            JP_FWD_RET_STRUCT(NSRange, toRange)
            
            @synchronized (_context) {               //如果不是原生支持的结构体类型，尝试结构体类型扩展中的结构体
                NSDictionary *structDefine = registeredStruct[typeString];
                if (structDefine) {
                    size_t size = sizeOfStructTypes(structDefine[@"types"]);
                    JP_FWD_RET_CALL_JS
                    void *ret = malloc(size);
                    NSDictionary *dict = formatJSToOC(jsval);
                    getStructDataWithDict(ret, dict, structDefine);
                    [invocation setReturnValue:ret];
                }
            }
            break;
        }
        default: {
            break;
        }
    }
}

// 初始化_JSOVrideMethods字典，key为cls的Value为一个字典
static void _initJPOverideMethods(Class cls) {
    if (!_JSOverideMethods) {
        _JSOverideMethods = [[NSMutableDictionary alloc] init];
    }
    if (!_JSOverideMethods[cls]) {
        _JSOverideMethods[(id<NSCopying>)cls] = [[NSMutableDictionary alloc] init];
    }
}

/**
 *  用js新方法替换原有方法的实现
 *
 *  @param cls             实例对象的类
 *  @param selectorName    方法名
 *  @param function        js方法对象
 *  @param isClassMethod   是否是类方法
 *  @param typeDescription 类型编码
 */
static void overrideMethod(Class cls, NSString *selectorName, JSValue *function, BOOL isClassMethod, const char *typeDescription)
{
    SEL selector = NSSelectorFromString(selectorName);
    
    if (!typeDescription) {
        Method method = class_getInstanceMethod(cls, selector);    //通过类和selector得到method
        typeDescription = (char *)method_getTypeEncoding(method);  // 获取描述方法参数和返回值类型的字符串，类型编码
    }
    
    IMP originalImp = class_respondsToSelector(cls, selector) ? class_getMethodImplementation(cls, selector) : NULL;  //通过类和selector得到原方法的IMP指针
    
    /**
     *  _objc_msgForward解释: OC底层负责转发的函数,调用这个，就会转发去到这个类的 forwardInvocation:方法
     */
    IMP msgForwardIMP = _objc_msgForward;                                     //将msgForwardIMP函数指向_objc_msgForward
    #if !defined(__arm64__)
        if (typeDescription[0] == '{') {
            //In some cases that returns struct, we should use the '_stret' API:
            //http://sealiesoftware.com/blog/archive/2008/10/30/objc_explain_objc_msgSend_stret.html
            //NSMethodSignature knows the detail but has no API to return, we can only get the info from debugDescription.
            NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:typeDescription];
            if ([methodSignature.debugDescription rangeOfString:@"is special struct return? YES"].location != NSNotFound) {
                msgForwardIMP = (IMP)_objc_msgForward_stret;
            }
        }
    #endif

    /**
     *  用msgForwardIMP函数指针替换cls和selector所确定的老方法的IMP函数指针实现
     */
    class_replaceMethod(cls, selector, msgForwardIMP, typeDescription);
    
    /**
     *  将cls的forwardInvocation:方法的IMP函数指针实现替换成(IMP)JPForwardInvocation)，
     *并为cls新增一个selector名为ORIGforwardInvocation:方法的IMP函数指针实现为原方法forwardInvocation:的IMP函数指针实现
     */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if (class_getMethodImplementation(cls, @selector(forwardInvocation:)) != (IMP)JPForwardInvocation) {
        IMP originalForwardImp = class_replaceMethod(cls, @selector(forwardInvocation:), (IMP)JPForwardInvocation, "v@:@");  //forwardInvocation 的 param type encoding
        class_addMethod(cls, @selector(ORIGforwardInvocation:), originalForwardImp, "v@:@");     //第一个v表示返回值类型为void，由于方法参数签名的第一和第二哥参数分别是调用对象的类型和调用的SEL的类型，所以第二个是@和第三个是:，第四个@表示方法有一个参数为对象类型
    }
#pragma clang diagnostic pop

    /**
     *  为cls增加selector名为ORIG开头加原selector名，方法的IMP函数指针实现为原方法的IMP函数指针实现的方法
     */
    if (class_respondsToSelector(cls, selector)) {
        NSString *originalSelectorName = [NSString stringWithFormat:@"ORIG%@", selectorName];
        SEL originalSelector = NSSelectorFromString(originalSelectorName);
        if(!class_respondsToSelector(cls, originalSelector)) {
            class_addMethod(cls, originalSelector, originalImp, typeDescription);
        }
    }
    
    /**
     *  为cls增加selector名为_JP开头加原selector名，方法实现为任意IMP
     */
    NSString *JPSelectorName = [NSString stringWithFormat:@"_JP%@", selectorName];
    SEL JPSelector = NSSelectorFromString(JPSelectorName);

    _initJPOverideMethods(cls);
    _JSOverideMethods[cls][JPSelectorName] = function;   //将js的function存储到_JSOverideMethods字典中
    
    /**
     *  让JSSelector的IMP设置成msgForwardIMP的原因只是让它具有响应的能力，在forwardInvocation的IMP中我们会让JSSelector直接执行JSFunction
     */
    class_addMethod(cls, JPSelector, msgForwardIMP, typeDescription);
}

#pragma mark -

/**
 *  给对象发消息（调用某个方法）
 *
 *  @param className    类名   //类方法是需要传，实例方法不需要
 *  @param selectorName 必须
 *  @param arguments    方法参数列表
 *  @param instance     被JSValue保存的实例对象指针  //类方法不需要传，实例方法需要传
 *  @param isSuper      是否是调用父类的方法，      //类方法不需要传，实例方法需要传
 *
 *  @return 方法返回值
 */
static id callSelector(NSString *className, NSString *selectorName, JSValue *arguments, JSValue *instance, BOOL isSuper)
{
    if (instance) {
        instance = formatJSToOC(instance);
        if (!instance || instance == _nilObj) return @{@"__isNil": @(YES)};
    }
    id argumentsObj = formatJSToOC(arguments);
    
    if (instance && [selectorName isEqualToString:@"toJS"]) {   //如果是toJS方法，则包装直接传OC的数组，字典，字符串，js不保存地址，直接转成相应js的数组，字典，字符串
        if ([instance isKindOfClass:[NSString class]] || [instance isKindOfClass:[NSDictionary class]] || [instance isKindOfClass:[NSArray class]]) {
            return _unboxOCObjectToJS(instance);
        }
    }

    Class cls = instance ? [instance class] : NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    
    if (isSuper) {   //如果是父类的方法，替换父类的方法。
        NSString *superSelectorName = [NSString stringWithFormat:@"SUPER_%@", selectorName];
        SEL superSelector = NSSelectorFromString(superSelectorName);
        
        Class superCls = [cls superclass];
        Method superMethod = class_getInstanceMethod(superCls, selector);
        IMP superIMP = method_getImplementation(superMethod);
        
        class_addMethod(cls, superSelector, superIMP, method_getTypeEncoding(superMethod));
        
        NSString *JPSelectorName = [NSString stringWithFormat:@"_JP%@", selectorName];
        JSValue *overideFunction = _JSOverideMethods[superCls][JPSelectorName];
        if (overideFunction) {
            overrideMethod(cls, superSelectorName, overideFunction, NO, NULL);
        }
        
        selector = superSelector;
    }
    
    
    NSMutableArray *_markArray;
    
    NSInvocation *invocation;
    NSMethodSignature *methodSignature;
    if (!_JSMethodSignatureCache) {     //使用_JSMethodSignatureCache保存方法的签名，起到缓存的作用，在反复调用统一SEL时减少资源开销
        _JSMethodSignatureCache = [[NSMutableDictionary alloc]init];
    }
    if (instance) {
        [_JSMethodSignatureLock lock];
        if (!_JSMethodSignatureCache[cls]) {
            _JSMethodSignatureCache[(id<NSCopying>)cls] = [[NSMutableDictionary alloc]init];
        }
        methodSignature = _JSMethodSignatureCache[cls][selectorName];
        if (!methodSignature) {
            methodSignature = [cls instanceMethodSignatureForSelector:selector];
            _JSMethodSignatureCache[cls][selectorName] = methodSignature;
        }
        [_JSMethodSignatureLock unlock];
        NSCAssert(methodSignature, @"unrecognized selector %@ for instance %@", selectorName, instance);
        invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [invocation setTarget:instance];
    } else {
        methodSignature = [cls methodSignatureForSelector:selector];
        NSCAssert(methodSignature, @"unrecognized selector %@ for class %@", selectorName, className);
        invocation= [NSInvocation invocationWithMethodSignature:methodSignature];
        [invocation setTarget:cls];
    }
    [invocation setSelector:selector];
    
    NSUInteger numberOfArguments = methodSignature.numberOfArguments;
    for (NSUInteger i = 2; i < numberOfArguments; i++) {    //invocation的第0个argument是target,第1个是SEL，所以从第2个开始取参数的类型编码
        const char *argumentType = [methodSignature getArgumentTypeAtIndex:i];
        id valObj = argumentsObj[i-2];
        switch (argumentType[0] == 'r' ? argumentType[1] : argumentType[0]) {
                
                #define JP_CALL_ARG_CASE(_typeString, _type, _selector) \
                case _typeString: {                              \
                    _type value = [valObj _selector];                     \
                    [invocation setArgument:&value atIndex:i];\
                    break; \
                }     //当参数是以下基础类型数据的取值方法
                
                /**
                 *  以下主要都是根据参数的类型编码做相应的取值操作，然后为invocation设置参数，关于类型编码在overrideMethod函数中已有很多注释，不在赘述
                 *  类型编码官方有说明，不解的同学可以去查看：https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
                 */
                
                JP_CALL_ARG_CASE('c', char, charValue)
                JP_CALL_ARG_CASE('C', unsigned char, unsignedCharValue)
                JP_CALL_ARG_CASE('s', short, shortValue)
                JP_CALL_ARG_CASE('S', unsigned short, unsignedShortValue)
                JP_CALL_ARG_CASE('i', int, intValue)
                JP_CALL_ARG_CASE('I', unsigned int, unsignedIntValue)
                JP_CALL_ARG_CASE('l', long, longValue)
                JP_CALL_ARG_CASE('L', unsigned long, unsignedLongValue)
                JP_CALL_ARG_CASE('q', long long, longLongValue)
                JP_CALL_ARG_CASE('Q', unsigned long long, unsignedLongLongValue)
                JP_CALL_ARG_CASE('f', float, floatValue)
                JP_CALL_ARG_CASE('d', double, doubleValue)
                JP_CALL_ARG_CASE('B', BOOL, boolValue)
                
            case ':': {
                SEL value = nil;
                if (valObj != _nilObj) {
                    value = NSSelectorFromString(valObj);
                }
                [invocation setArgument:&value atIndex:i];
                break;
            }
            case '{': {
                NSString *typeString = extractStructName([NSString stringWithUTF8String:argumentType]);
                JSValue *val = arguments[i-2];
                #define JP_CALL_ARG_STRUCT(_type, _methodName) \
                if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
                    _type value = [val _methodName];  \
                    [invocation setArgument:&value atIndex:i];  \
                    break; \
                }
                JP_CALL_ARG_STRUCT(CGRect, toRect)
                JP_CALL_ARG_STRUCT(CGPoint, toPoint)
                JP_CALL_ARG_STRUCT(CGSize, toSize)
                JP_CALL_ARG_STRUCT(NSRange, toRange)
                @synchronized (_context) {
                    NSDictionary *structDefine = registeredStruct[typeString];
                    if (structDefine) {
                        size_t size = sizeOfStructTypes(structDefine[@"types"]);
                        void *ret = malloc(size);
                        getStructDataWithDict(ret, valObj, structDefine);
                        [invocation setArgument:ret atIndex:i];
                        free(ret);
                        break;
                    }
                }
                
                break;
            }
            case '*':
            case '^': {
                if ([valObj isKindOfClass:[JPBoxing class]]) {
                    void *value = [((JPBoxing *)valObj) unboxPointer];
                    
                    if (argumentType[1] == '@') {
                        if (!_TMPMemoryPool) {
                            _TMPMemoryPool = [[NSMutableDictionary alloc] init];
                        }
                        if (!_markArray) {
                            _markArray = [[NSMutableArray alloc] init];
                        }
                        memset(value, 0, sizeof(id));
                        [_markArray addObject:valObj];
                    }
                    
                    [invocation setArgument:&value atIndex:i];
                    break;
                }
            }
            case '#': {
                if ([valObj isKindOfClass:[JPBoxing class]]) {
                    Class value = [((JPBoxing *)valObj) unboxClass];
                    [invocation setArgument:&value atIndex:i];
                    break;
                }
            }
            default: {
                if (valObj == _nullObj) {
                    valObj = [NSNull null];
                    [invocation setArgument:&valObj atIndex:i];
                    break;
                }
                if (valObj == _nilObj ||
                    ([valObj isKindOfClass:[NSNumber class]] && strcmp([valObj objCType], "c") == 0 && ![valObj boolValue])) {
                    valObj = nil;
                    [invocation setArgument:&valObj atIndex:i];
                    break;
                }
                if ([(JSValue *)arguments[i-2] hasProperty:@"__isBlock"]) {
                    __autoreleasing id cb = genCallbackBlock(arguments[i-2]);
                    [invocation setArgument:&cb atIndex:i];
                } else {
                    [invocation setArgument:&valObj atIndex:i];
                }
            }
        }
    }
    
    [invocation invoke];    //使用invoke执行方法
    if ([_markArray count] > 0) {
        for (JPBoxing *box in _markArray) {
            void *pointer = [box unboxPointer];
            id obj = *((__unsafe_unretained id *)pointer);
            if (obj) {
                @synchronized(_TMPMemoryPool) {
                    [_TMPMemoryPool setObject:obj forKey:[NSNumber numberWithInteger:[obj hash]]];
                }
            }
        }
    }
    const char *returnType = [methodSignature methodReturnType];
    id returnValue;
    if (strncmp(returnType, "v", 1) != 0) {
        if (strncmp(returnType, "@", 1) == 0) {
            void *result;
            [invocation getReturnValue:&result];
            
            //For performance, ignore the other methods prefix with alloc/new/copy/mutableCopy
            if ([selectorName isEqualToString:@"alloc"] || [selectorName isEqualToString:@"new"] ||
                [selectorName isEqualToString:@"copy"] || [selectorName isEqualToString:@"mutableCopy"]) {
                returnValue = (__bridge_transfer id)result;
            } else {
                returnValue = (__bridge id)result;
            }
            return formatOCToJS(returnValue);
            
        } else {
            switch (returnType[0] == 'r' ? returnType[1] : returnType[0]) {
                    
                #define JP_CALL_RET_CASE(_typeString, _type) \
                case _typeString: {                              \
                    _type tempResultSet; \
                    [invocation getReturnValue:&tempResultSet];\
                    returnValue = @(tempResultSet); \
                    break; \
                }
                    
                /**
                 *  以下主要都是根据参数的类型编码做相应的取值操作，取的值是执行invoke之后的返回值，关于类型编码在overrideMethod函数中已有很多注释，不在赘述
                 *  类型编码官方有说明，不解的同学可以去查看：https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
                 */
                    
                JP_CALL_RET_CASE('c', char)
                JP_CALL_RET_CASE('C', unsigned char)
                JP_CALL_RET_CASE('s', short)
                JP_CALL_RET_CASE('S', unsigned short)
                JP_CALL_RET_CASE('i', int)
                JP_CALL_RET_CASE('I', unsigned int)
                JP_CALL_RET_CASE('l', long)
                JP_CALL_RET_CASE('L', unsigned long)
                JP_CALL_RET_CASE('q', long long)
                JP_CALL_RET_CASE('Q', unsigned long long)
                JP_CALL_RET_CASE('f', float)
                JP_CALL_RET_CASE('d', double)
                JP_CALL_RET_CASE('B', BOOL)

                case '{': {
                    NSString *typeString = extractStructName([NSString stringWithUTF8String:returnType]);
                    #define JP_CALL_RET_STRUCT(_type, _methodName) \
                    if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
                        _type result;   \
                        [invocation getReturnValue:&result];    \
                        return [JSValue _methodName:result inContext:_context];    \
                    }
                    JP_CALL_RET_STRUCT(CGRect, valueWithRect)
                    JP_CALL_RET_STRUCT(CGPoint, valueWithPoint)
                    JP_CALL_RET_STRUCT(CGSize, valueWithSize)
                    JP_CALL_RET_STRUCT(NSRange, valueWithRange)
                    @synchronized (_context) {
                        NSDictionary *structDefine = registeredStruct[typeString];
                        if (structDefine) {
                            size_t size = sizeOfStructTypes(structDefine[@"types"]);
                            void *ret = malloc(size);
                            [invocation getReturnValue:ret];
                            NSDictionary *dict = getDictOfStruct(ret, structDefine);
                            free(ret);
                            return dict;
                        }
                    }
                    break;
                }
                case '*':
                case '^': {
                    void *result;
                    [invocation getReturnValue:&result];
                    returnValue = formatOCToJS([JPBoxing boxPointer:result]);
                    break;
                }
                case '#': {
                    Class result;
                    [invocation getReturnValue:&result];
                    returnValue = formatOCToJS([JPBoxing boxClass:result]);
                    break;
                }
            }
            return returnValue;
        }
    }
    return nil;
}

#pragma mark -

/**
 *  block支持，目前支持block参数最多为4个
 *
 *  @param jsVal js传过来的一些参数
 *
 *  @return id对象
 */
static id genCallbackBlock(JSValue *jsVal)
{
#define BLK_DEFINE_1 cb = ^id(void *p0) {
#define BLK_DEFINE_2 cb = ^id(void *p0, void *p1) {
#define BLK_DEFINE_3 cb = ^id(void *p0, void *p1, void *p2) {
#define BLK_DEFINE_4 cb = ^id(void *p0, void *p1, void *p2, void *p3) {
#define BLK_INIT_PARAMETERS NSMutableArray *list = [[NSMutableArray alloc] init];
    
#define BLK_ADD_OBJ(_paramName) [list addObject:formatOCToJS((__bridge id)_paramName)];
#define BLK_ADD_INT(_paramName) [list addObject:formatOCToJS([NSNumber numberWithLongLong:(long long)_paramName])];

#define BLK_TRAITS_ARG(_idx, _paramName) \
    if (blockTypeIsObject(trim(argTypes[_idx]))) {  \
        BLK_ADD_OBJ(_paramName) \
    } else {  \
        BLK_ADD_INT(_paramName) \
    }   \

#define BLK_END \
    JSValue *ret = [jsVal[@"cb"] callWithArguments:list];    \
    return formatJSToOC(ret); \
};

    NSArray *argTypes = [[jsVal[@"args"] toString] componentsSeparatedByString:@","];
    NSInteger count = argTypes.count;
    id cb;
    if (count == 1) {
        BLK_DEFINE_1
        BLK_INIT_PARAMETERS
        BLK_TRAITS_ARG(0, p0)
        BLK_END
    }
    if (count == 2) {
        BLK_DEFINE_2
        BLK_INIT_PARAMETERS
        BLK_TRAITS_ARG(0, p0)
        BLK_TRAITS_ARG(1, p1)
        BLK_END
    }
    if (count == 3) {
        BLK_DEFINE_3
        BLK_INIT_PARAMETERS
        BLK_TRAITS_ARG(0, p0)
        BLK_TRAITS_ARG(1, p1)
        BLK_TRAITS_ARG(2, p2)
        BLK_END
    }
    if (count == 4) {
        BLK_DEFINE_4
        BLK_INIT_PARAMETERS
        BLK_TRAITS_ARG(0, p0)
        BLK_TRAITS_ARG(1, p1)
        BLK_TRAITS_ARG(2, p2)
        BLK_TRAITS_ARG(3, p3)
        BLK_END
    }
    return cb;
}

#pragma mark - Struct

static int sizeOfStructTypes(NSString *structTypes)
{
    const char *types = [structTypes cStringUsingEncoding:NSUTF8StringEncoding];
    int index = 0;
    int size = 0;
    while (types[index]) {
        switch (types[index]) {
            #define JP_STRUCT_SIZE_CASE(_typeChar, _type)   \
            case _typeChar: \
                size += sizeof(_type);  \
                break;
                
            JP_STRUCT_SIZE_CASE('c', char)
            JP_STRUCT_SIZE_CASE('C', unsigned char)
            JP_STRUCT_SIZE_CASE('s', short)
            JP_STRUCT_SIZE_CASE('S', unsigned short)
            JP_STRUCT_SIZE_CASE('i', int)
            JP_STRUCT_SIZE_CASE('I', unsigned int)
            JP_STRUCT_SIZE_CASE('l', long)
            JP_STRUCT_SIZE_CASE('L', unsigned long)
            JP_STRUCT_SIZE_CASE('q', long long)
            JP_STRUCT_SIZE_CASE('Q', unsigned long long)
            JP_STRUCT_SIZE_CASE('f', float)
            JP_STRUCT_SIZE_CASE('F', CGFloat)
            JP_STRUCT_SIZE_CASE('N', NSInteger)
            JP_STRUCT_SIZE_CASE('U', NSUInteger)
            JP_STRUCT_SIZE_CASE('d', double)
            JP_STRUCT_SIZE_CASE('B', BOOL)
            JP_STRUCT_SIZE_CASE('*', void *)
            JP_STRUCT_SIZE_CASE('^', void *)
            
            default:
                break;
        }
        index ++;
    }
    return size;
}

static void getStructDataWithDict(void *structData, NSDictionary *dict, NSDictionary *structDefine)
{
    NSArray *itemKeys = structDefine[@"keys"];
    const char *structTypes = [structDefine[@"types"] cStringUsingEncoding:NSUTF8StringEncoding];
    int position = 0;
    for (int i = 0; i < itemKeys.count; i ++) {
        switch(structTypes[i]) {
            #define JP_STRUCT_DATA_CASE(_typeStr, _type, _transMethod) \
            case _typeStr: { \
                int size = sizeof(_type);    \
                _type val = [dict[itemKeys[i]] _transMethod];   \
                memcpy(structData + position, &val, size);  \
                position += size;    \
                break;  \
            }
                
            JP_STRUCT_DATA_CASE('c', char, charValue)
            JP_STRUCT_DATA_CASE('C', unsigned char, unsignedCharValue)
            JP_STRUCT_DATA_CASE('s', short, shortValue)
            JP_STRUCT_DATA_CASE('S', unsigned short, unsignedShortValue)
            JP_STRUCT_DATA_CASE('i', int, intValue)
            JP_STRUCT_DATA_CASE('I', unsigned int, unsignedIntValue)
            JP_STRUCT_DATA_CASE('l', long, longValue)
            JP_STRUCT_DATA_CASE('L', unsigned long, unsignedLongValue)
            JP_STRUCT_DATA_CASE('q', long long, longLongValue)
            JP_STRUCT_DATA_CASE('Q', unsigned long long, unsignedLongLongValue)
            JP_STRUCT_DATA_CASE('f', float, floatValue)
            JP_STRUCT_DATA_CASE('d', double, doubleValue)
            JP_STRUCT_DATA_CASE('B', BOOL, boolValue)
            JP_STRUCT_DATA_CASE('N', NSInteger, integerValue)
            JP_STRUCT_DATA_CASE('U', NSUInteger, unsignedIntegerValue)
            
            case 'F': {
                int size = sizeof(CGFloat);
                CGFloat val;
                if (size == sizeof(double)) {
                    val = [dict[itemKeys[i]] doubleValue];
                } else {
                    val = [dict[itemKeys[i]] floatValue];
                }
                memcpy(structData + position, &val, size);
                position += size;
                break;
            }
            
            case '*':
            case '^': {
                int size = sizeof(void *);
                void *val = [(JPBoxing *)dict[itemKeys[i]] unboxPointer];
                memcpy(structData + position, &val, size);
                break;
            }
            
        }
    }
}

static NSDictionary *getDictOfStruct(void *structData, NSDictionary *structDefine)
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    NSArray *itemKeys = structDefine[@"keys"];
    const char *structTypes = [structDefine[@"types"] cStringUsingEncoding:NSUTF8StringEncoding];
    int position = 0;
    
    for (int i = 0; i < itemKeys.count; i ++) {
        switch(structTypes[i]) {
            #define JP_STRUCT_DICT_CASE(_typeName, _type)   \
            case _typeName: { \
                size_t size = sizeof(_type); \
                _type *val = malloc(size);   \
                memcpy(val, structData + position, size);   \
                [dict setObject:@(*val) forKey:itemKeys[i]];    \
                free(val);  \
                position += size;   \
                break;  \
            }
            JP_STRUCT_DICT_CASE('c', char)
            JP_STRUCT_DICT_CASE('C', unsigned char)
            JP_STRUCT_DICT_CASE('s', short)
            JP_STRUCT_DICT_CASE('S', unsigned short)
            JP_STRUCT_DICT_CASE('i', int)
            JP_STRUCT_DICT_CASE('I', unsigned int)
            JP_STRUCT_DICT_CASE('l', long)
            JP_STRUCT_DICT_CASE('L', unsigned long)
            JP_STRUCT_DICT_CASE('q', long long)
            JP_STRUCT_DICT_CASE('Q', unsigned long long)
            JP_STRUCT_DICT_CASE('f', float)
            JP_STRUCT_DICT_CASE('F', CGFloat)
            JP_STRUCT_DICT_CASE('N', NSInteger)
            JP_STRUCT_DICT_CASE('U', NSUInteger)
            JP_STRUCT_DICT_CASE('d', double)
            JP_STRUCT_DICT_CASE('B', BOOL)
            
            case '*':
            case '^': {
                size_t size = sizeof(void *);
                void *val = malloc(size);
                memcpy(val, structData + position, size);
                [dict setObject:[JPBoxing boxPointer:val] forKey:itemKeys[i]];
                position += size;
                break;
            }
            
        }
    }
    return dict;
}

/**
 *  根据结构体类型编码字符串得到结构体类型的类名字符串
 *
 *  @param typeEncodeString 类型编码字符串
 *
 *  @return  结构体类型的类名字符串
 */
static NSString *extractStructName(NSString *typeEncodeString)
{
    NSArray *array = [typeEncodeString componentsSeparatedByString:@"="];
    NSString *typeString = array[0];
    int firstValidIndex = 0;
    for (int i = 0; i< typeString.length; i++) {
        char c = [typeString characterAtIndex:i];
        if (c == '{' || c=='_') {
            firstValidIndex++;
        }else {
            break;
        }
    }
    return [typeString substringFromIndex:firstValidIndex];
}

#pragma mark - Utils

static NSString *trim(NSString *string)
{
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL blockTypeIsObject(NSString *typeString)
{
    return [typeString rangeOfString:@"*"].location != NSNotFound || [typeString isEqualToString:@"id"];
}

#pragma mark - Object format

/**
 *  将经过JPBoxing初步包装的OC对象转化成经JPBoxing包装的对象
 *
 *  @param obj 经过JPBoxing初步包装的OC对象
 *
 *  @return 最终需要包装成的模样 假设源OC对象obj  基本数据NSBumber.obj
 */
static id formatOCToJS(id obj)
{
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
        return _wrapObj([JPBoxing boxObj:obj]);
    }
    if ([obj isKindOfClass:[NSNumber class]] || [obj isKindOfClass:NSClassFromString(@"NSBlock")] || [obj isKindOfClass:[JSValue class]]) {
        return obj;
    }
    return _wrapObj(obj);
}

/**
 *  将JSValue转化成id类型OC对象，
 *
 *  @param jsval JSValue对象
 *
 *  @return id类型OC对象
 */
static id formatJSToOC(JSValue *jsval)
{
    id obj = [jsval toObject];
    if (!obj || [obj isKindOfClass:[NSNull class]]) return _nilObj;
    
    if ([obj isKindOfClass:[JPBoxing class]]) return [obj unbox];
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *newArr = [[NSMutableArray alloc] init];
        for (int i = 0; i < [obj count]; i ++) {
            [newArr addObject:formatJSToOC(jsval[i])];
        }
        return newArr;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        if (obj[@"__obj"]) {
            id ocObj = [obj objectForKey:@"__obj"];
            if ([ocObj isKindOfClass:[JPBoxing class]]) return [ocObj unbox];
            return ocObj;
        }
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] init];
        for (NSString *key in [obj allKeys]) {
            [newDict setObject:formatJSToOC(jsval[key]) forKey:key];
        }
        return newDict;
    }
    return obj;
}

/**
 *  将OC对象（也可是经过JPBoxing包装的OC对象）数组转化为js对象数组
 *
 *  @param list OC对象数组
 *
 *  @return JS对象数组
 */
static id _formatOCToJSList(NSArray *list)
{
    NSMutableArray *arr = [NSMutableArray new];
    for (id obj in list) {
        [arr addObject:formatOCToJS(obj)];
    }
    return arr;
}

/**
 *  通过字典包装标记OC对象
 *
 *  @param obj OC对象
 *
 *  @return 字典包装标识后的对象
 */
static NSDictionary *_wrapObj(id obj)
{
    if (!obj || obj == _nilObj) {
        return @{@"__isNil": @(YES)};
    }
    return @{@"__obj": obj};
}

/**
 *  拆开箱子后标识为OC对象
 *
 *  @param OC对象
 *
 *  @return 标识为OC对象
 */
static id _unboxOCObjectToJS(id obj)
{
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *newArr = [[NSMutableArray alloc] init];
        for (int i = 0; i < [obj count]; i ++) {
            [newArr addObject:_unboxOCObjectToJS(obj[i])];
        }
        return newArr;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] init];
        for (NSString *key in [obj allKeys]) {
            [newDict setObject:_unboxOCObjectToJS(obj[key]) forKey:key];
        }
        return newDict;
    }
    if ([obj isKindOfClass:[NSString class]] ||[obj isKindOfClass:[NSNumber class]] || [obj isKindOfClass:NSClassFromString(@"NSBlock")]) {
        return obj;
    }
    return _wrapObj(obj);
}
@end


@implementation JPExtension

+ (void)main:(JSContext *)context{}

+ (void *)formatPointerJSToOC:(JSValue *)val
{
    id obj = [val toObject];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        if (obj[@"__obj"] && [obj[@"__obj"] isKindOfClass:[JPBoxing class]]) {
            return [(JPBoxing *)(obj[@"__obj"]) unboxPointer];
        } else {
            return NULL;
        }
    } else if (![val toBool]) {
        return NULL;
    } else{
        return [((JPBoxing *)[val toObject]) unboxPointer];
    }
}

+ (id)formatPointerOCToJS:(void *)pointer
{
    return formatOCToJS([JPBoxing boxPointer:pointer]);
}

+ (id)formatJSToOC:(JSValue *)val
{
    if (![val toBool]) {
        return nil;
    }
    return formatJSToOC(val);
}

+ (id)formatOCToJS:(id)obj
{
    return [[JSContext currentContext][@"_formatOCToJS"] callWithArguments:@[formatOCToJS(obj)]];
}

+ (int)sizeOfStructTypes:(NSString *)structTypes
{
    return sizeOfStructTypes(structTypes);
}

+ (void)getStructDataWidthDict:(void *)structData dict:(NSDictionary *)dict structDefine:(NSDictionary *)structDefine
{
    return getStructDataWithDict(structData, dict, structDefine);
}

+ (NSDictionary *)getDictOfStruct:(void *)structData structDefine:(NSDictionary *)structDefine
{
    return getDictOfStruct(structData, structDefine);
}
@end
