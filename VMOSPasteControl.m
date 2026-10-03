#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Native paste receiver. UIPasteControl grants paste access after an explicit user tap.
@interface VMOSPasteReceiver : NSObject <UIPasteConfigurationSupporting>
@property(nonatomic,strong) UIPasteConfiguration *pasteConfiguration;
@end

@implementation VMOSPasteReceiver
- (instancetype)init {
    if ((self = [super init])) {
        _pasteConfiguration = [[UIPasteConfiguration alloc] initWithAcceptableTypeIdentifiers:@[@"public.utf8-plain-text", @"public.text"]];
    }
    return self;
}
- (BOOL)canPasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders { return itemProviders.count > 0; }
- (void)pasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders {
    NSItemProvider *p = itemProviders.firstObject;
    NSString *type = [p hasItemConformingToTypeIdentifier:@"public.utf8-plain-text"] ? @"public.utf8-plain-text" : @"public.text";
    [p loadItemForTypeIdentifier:type options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
        NSString *text = nil;
        id object = (id)item;

if ([object isKindOfClass:[NSString class]]) {
    text = (NSString *)object;
} else if ([object isKindOfClass:[NSData class]]) {
    text = [[NSString alloc] initWithData:(NSData *)object
                                  encoding:NSUTF8StringEncoding];
}
        if (!text.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Put the user-authorized value into the app's own pasteboard access path.
            // VMOS already contains CLIPBOARD_READ; after this user action its existing Paste action can consume it.
            [UIPasteboard generalPasteboard].string = text;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"VMOSPasteControlDidPaste" object:text];
        });
    }];
}
@end

static VMOSPasteReceiver *receiver;
static UIPasteControl *control;

static UIWindow *ActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void InstallPasteControl(void) {
    if (@available(iOS 16.0, *)) {
        UIWindow *w = ActiveWindow(); if (!w || control) return;
        receiver = [VMOSPasteReceiver new];
        UIPasteControlConfiguration *cfg = [UIPasteControlConfiguration new];
        cfg.displayMode = UIPasteControlDisplayModeIconAndLabel;
        control = [[UIPasteControl alloc] initWithConfiguration:cfg];
        control.target = receiver;
        control.translatesAutoresizingMaskIntoConstraints = NO;
        control.layer.cornerRadius = 12;
        control.clipsToBounds = YES;
        [w addSubview:control];
        [NSLayoutConstraint activateConstraints:@[
            [control.trailingAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.trailingAnchor constant:-12],
            [control.bottomAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.bottomAnchor constant:-20],
            [control.widthAnchor constraintGreaterThanOrEqualToConstant:92],
            [control.heightAnchor constraintEqualToConstant:44]
        ]];
    }
}

__attribute__((constructor)) static void VMOSPasteInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ InstallPasteControl(); });
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ InstallPasteControl(); });
    });
}
