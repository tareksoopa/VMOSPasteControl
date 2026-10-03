#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSMutableString *gLog;

static void Trace(NSString *s) {
    if (!s) return;

    if (!gLog)
        gLog = [NSMutableString string];

    NSString *line =
        [NSString stringWithFormat:@"%@  %@\n", [NSDate date], s];

    [gLog appendString:line];
    NSLog(@"[VMOSClipTrace] %@", s);
}

static NSString *SafeDesc(id x) {
    @try {
        return [x description] ?: @"";
    }
    @catch (...) {
        return @"<description failed>";
    }
}

static BOOL Relevant(NSString *s) {
    NSString *x = s.lowercaseString;

    return [x containsString:@"clip"] ||
           [x containsString:@"paste"] ||
           [x containsString:@"input"] ||
           [x containsString:@"cloud"];
}

static NSString *ChannelName(id obj) {
    @try {
        id name = [obj valueForKey:@"name"];

        if ([name isKindOfClass:NSString.class])
            return name;
    }
    @catch (...) {}

    return @"<unknown-channel>";
}

/* ================================
   Flutter outgoing calls
   ================================ */

static void (*origInvoke2)(
    id,
    SEL,
    id,
    id
);

static void hookInvoke2(
    id selfObj,
    SEL cmd,
    id method,
    id args
) {
    NSString *line =
        [NSString stringWithFormat:
         @"OUT channel=%@ method=%@ args=%@",
         ChannelName(selfObj),
         SafeDesc(method),
         SafeDesc(args)];

    if (Relevant(line))
        Trace(line);

    origInvoke2(
        selfObj,
        cmd,
        method,
        args
    );
}

static void (*origInvoke3)(
    id,
    SEL,
    id,
    id,
    id
);

static void hookInvoke3(
    id selfObj,
    SEL cmd,
    id method,
    id args,
    id result
) {
    NSString *line =
        [NSString stringWithFormat:
         @"OUT+RESULT channel=%@ method=%@ args=%@",
         ChannelName(selfObj),
         SafeDesc(method),
         SafeDesc(args)];

    if (Relevant(line))
        Trace(line);

    origInvoke3(
        selfObj,
        cmd,
        method,
        args,
        result
    );
}

/* ================================
   Incoming Flutter calls
   ================================ */

typedef void (^MethodHandler)(
    id call,
    id result
);

static void (*origSetHandler)(
    id,
    SEL,
    MethodHandler
);

static void hookSetHandler(
    id selfObj,
    SEL cmd,
    MethodHandler handler
) {
    NSString *channel =
        ChannelName(selfObj);

    if (Relevant(channel)) {
        Trace(
            [NSString stringWithFormat:
             @"REGISTER channel=%@",
             channel]
        );
    }

    if (!handler) {
        origSetHandler(
            selfObj,
            cmd,
            nil
        );
        return;
    }

    __weak id weakChannel = selfObj;

    MethodHandler wrapped =
    ^(id call, id result) {

        NSString *method = @"";
        id arguments = nil;

        @try {
            method =
                SafeDesc(
                    [call valueForKey:@"method"]
                );
        }
        @catch (...) {}

        @try {
            arguments =
                [call valueForKey:@"arguments"];
        }
        @catch (...) {}

        NSString *line =
            [NSString stringWithFormat:
             @"IN channel=%@ method=%@ args=%@",
             ChannelName(weakChannel),
             method,
             SafeDesc(arguments)];

        if (Relevant(line))
            Trace(line);

        handler(call, result);
    };

    origSetHandler(
        selfObj,
        cmd,
        wrapped
    );
}

/* ================================
   Runtime hook
   ================================ */

static void Swizzle(
    Class cls,
    SEL selector,
    IMP replacement,
    IMP *original
) {
    Method method =
        class_getInstanceMethod(
            cls,
            selector
        );

    if (!method)
        return;

    *original =
        method_getImplementation(method);

    method_setImplementation(
        method,
        replacement
    );

    Trace(
        [NSString stringWithFormat:
         @"HOOKED %@ %@",
         NSStringFromClass(cls),
         NSStringFromSelector(selector)]
    );
}

/* ================================
   LOG window
   ================================ */

@interface VMOSLogController : NSObject
@end

@implementation VMOSLogController

- (void)showLog {

    UIWindow *window = nil;

    for (UIScene *scene
         in UIApplication.sharedApplication.connectedScenes) {

        if (![scene
              isKindOfClass:UIWindowScene.class])
            continue;

        for (UIWindow *w
             in ((UIWindowScene *)scene).windows) {

            if (w.isKeyWindow) {
                window = w;
                break;
            }
        }

        if (window)
            break;
    }

    UIViewController *vc =
        window.rootViewController;

    while (vc.presentedViewController)
        vc = vc.presentedViewController;

    NSString *text =
        gLog.length
        ? gLog
        : @"No clipboard events captured yet.";

    UIAlertController *alert =
        [UIAlertController
         alertControllerWithTitle:@"VMOS Clipboard LOG"
         message:text
         preferredStyle:
         UIAlertControllerStyleAlert];

    [alert addAction:
     [UIAlertAction
      actionWithTitle:@"Copy Log"
      style:UIAlertActionStyleDefault
      handler:^(UIAlertAction *action) {

        UIPasteboard.generalPasteboard.string =
            gLog ?: @"";

     }]];

    [alert addAction:
     [UIAlertAction
      actionWithTitle:@"Clear"
      style:UIAlertActionStyleDestructive
      handler:^(UIAlertAction *action) {

        [gLog setString:@""];

     }]];

    [alert addAction:
     [UIAlertAction
      actionWithTitle:@"Close"
      style:UIAlertActionStyleCancel
      handler:nil]];

    [vc presentViewController:
        alert
        animated:YES
        completion:nil];
}

@end

static VMOSLogController *gController;

/* ================================
   LOG button
   ================================ */

static void AddLogButton(void) {

    UIWindow *window = nil;

    for (UIScene *scene
         in UIApplication.sharedApplication.connectedScenes) {

        if (scene.activationState !=
            UISceneActivationStateForegroundActive)
            continue;

        if (![scene
              isKindOfClass:UIWindowScene.class])
            continue;

        for (UIWindow *w
             in ((UIWindowScene *)scene).windows) {

            if (w.isKeyWindow) {
                window = w;
                break;
            }
        }

        if (window)
            break;
    }

    if (!window)
        return;

    if ([window viewWithTag:987654])
        return;

    gController =
        [VMOSLogController new];

    UIButton *button =
        [UIButton
         buttonWithType:
         UIButtonTypeSystem];

    button.tag = 987654;

    button.frame =
        CGRectMake(
            window.bounds.size.width - 80,
            window.safeAreaInsets.top + 60,
            65,
            42
        );

    button.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleBottomMargin;

    [button setTitle:@"LOG"
            forState:UIControlStateNormal];

    button.backgroundColor =
        [UIColor colorWithWhite:0.1
                          alpha:0.85];

    [button setTitleColor:
        UIColor.whiteColor
        forState:UIControlStateNormal];

    button.layer.cornerRadius = 10;

    [button addTarget:
        gController
        action:@selector(showLog)
        forControlEvents:
        UIControlEventTouchUpInside];

    [window addSubview:button];

    Trace(@"LOG button installed");
}

/* ================================
   Start
   ================================ */

__attribute__((constructor))
static void VMOSDiagnosticInit(void) {

    gLog =
        [NSMutableString string];

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(2 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{

        Class channel =
            NSClassFromString(
                @"FlutterMethodChannel"
            );

        if (channel) {

            Swizzle(
                channel,
                NSSelectorFromString(
                    @"invokeMethod:arguments:"
                ),
                (IMP)hookInvoke2,
                (IMP *)&origInvoke2
            );

            Swizzle(
                channel,
                NSSelectorFromString(
                    @"invokeMethod:arguments:result:"
                ),
                (IMP)hookInvoke3,
                (IMP *)&origInvoke3
            );

            Swizzle(
                channel,
                NSSelectorFromString(
                    @"setMethodCallHandler:"
                ),
                (IMP)hookSetHandler,
                (IMP *)&origSetHandler
            );

            Trace(
                @"Flutter diagnostic active"
            );

        } else {

            Trace(
                @"FlutterMethodChannel not found"
            );
        }

        AddLogButton();
    });
}
