#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void Trace(NSString *s) {
    if (!s) return;
    NSLog(@"[VMOSClipTrace] %@", s);
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (!dirs.count) return;
    NSString *p = [dirs[0] stringByAppendingPathComponent:@"vmos_clipboard_trace.txt"];
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], s];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!h) {
        [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    }
}

static NSString *SafeDesc(id x) {
    @try { return [x description] ?: @""; } @catch (...) { return @"<description failed>"; }
}

static BOOL Relevant(NSString *s) {
    NSString *x = s.lowercaseString;
    return [x containsString:@"clip"] || [x containsString:@"paste"] ||
           [x containsString:@"input"] || [x containsString:@"cloud"];
}

static NSString *ChannelName(id selfObj) {
    @try {
        id n = [selfObj valueForKey:@"name"];
        if ([n isKindOfClass:NSString.class]) return n;
    } @catch (...) {}
    return @"<unknown-channel>";
}

static void (*origInvoke2)(id,SEL,id,id);
static void hookInvoke2(id selfObj, SEL _cmd, id method, id args) {
    NSString *ch = ChannelName(selfObj);
    NSString *m = SafeDesc(method);
    NSString *a = SafeDesc(args);
    NSString *line = [NSString stringWithFormat:@"OUT channel=%@ method=%@ args=%@",ch,m,a];
    if (Relevant(line)) Trace(line);
    origInvoke2(selfObj,_cmd,method,args);
}

static void (*origInvoke3)(id,SEL,id,id,id);
static void hookInvoke3(id selfObj, SEL _cmd, id method, id args, id result) {
    NSString *ch = ChannelName(selfObj);
    NSString *m = SafeDesc(method);
    NSString *a = SafeDesc(args);
    NSString *line = [NSString stringWithFormat:@"OUT+RESULT channel=%@ method=%@ args=%@",ch,m,a];
    if (Relevant(line)) Trace(line);
    origInvoke3(selfObj,_cmd,method,args,result);
}

typedef void (^MethodHandler)(id call, id result);
static void (*origSetHandler)(id,SEL,MethodHandler);

static void hookSetHandler(id selfObj, SEL _cmd, MethodHandler handler) {
    NSString *ch = ChannelName(selfObj);
    if (Relevant(ch)) Trace([NSString stringWithFormat:@"REGISTER channel=%@",ch]);
    if (!handler) { origSetHandler(selfObj,_cmd,nil); return; }

    __weak id weakChannel = selfObj;
    MethodHandler wrapped = ^(id call, id result) {
        NSString *channel = ChannelName(weakChannel);
        NSString *method = @"";
        id arguments = nil;
        @try { method = SafeDesc([call valueForKey:@"method"]); } @catch (...) {}
        @try { arguments = [call valueForKey:@"arguments"]; } @catch (...) {}
        NSString *line = [NSString stringWithFormat:@"IN channel=%@ method=%@ args=%@",
                          channel, method, SafeDesc(arguments)];
        if (Relevant(line)) Trace(line);
        handler(call,result);
    };
    origSetHandler(selfObj,_cmd,wrapped);
}

static void Swizzle(Class cls, SEL sel, IMP replacement, IMP *old) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *old = method_getImplementation(m);
    method_setImplementation(m,replacement);
    Trace([NSString stringWithFormat:@"HOOKED %@ %@",NSStringFromClass(cls),NSStringFromSelector(sel)]);
}

__attribute__((constructor))
static void VMOSClipTraceInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        Class c = NSClassFromString(@"FlutterMethodChannel");
        if (!c) { Trace(@"FlutterMethodChannel class not found"); return; }
        Swizzle(c, NSSelectorFromString(@"invokeMethod:arguments:"), (IMP)hookInvoke2, (IMP *)&origInvoke2);
        Swizzle(c, NSSelectorFromString(@"invokeMethod:arguments:result:"), (IMP)hookInvoke3, (IMP *)&origInvoke3);
        Swizzle(c, NSSelectorFromString(@"setMethodCallHandler:"), (IMP)hookSetHandler, (IMP *)&origSetHandler);
        Trace(@"VMOS clipboard diagnostic active");
    });
}
