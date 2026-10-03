#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

@interface VMOSPasteReceiver : NSObject <UIPasteConfigurationSupporting>
@property(nonatomic,strong) UIPasteConfiguration *pasteConfiguration;
@end

static void VMOSShowStatus(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
            }
            if (window) break;
        }
        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"VMOS Paste"
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static void CollectWebViews(UIView *view, NSMutableArray<WKWebView *> *out) {
    if ([view isKindOfClass:WKWebView.class]) [out addObject:(WKWebView *)view];
    for (UIView *v in view.subviews) CollectWebViews(v, out);
}

static NSString *JSONStringLiteral(NSString *s) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (json.length >= 2) return [json substringWithRange:NSMakeRange(1, json.length - 2)];
    return @"\"\"";
}

static void SendToVMOSCloudClipboard(NSString *text) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
        if (window) break;
    }
    if (!window) { VMOSShowStatus(@"No active VMOS window found."); return; }

    NSMutableArray<WKWebView *> *webViews = [NSMutableArray array];
    CollectWebViews(window, webViews);
    if (webViews.count == 0) {
        VMOSShowStatus(@"No VMOS WebView found. Open the cloud phone first, then tap Paste.");
        return;
    }

    NSString *literal = JSONStringLiteral(text);
    NSString *js = [NSString stringWithFormat:
        @"(function(){"
         "const txt=%@;"
         "const seen=new Set();"
         "function tryObj(o,depth){"
           "if(!o||depth>3||(typeof o!=='object'&&typeof o!=='function')||seen.has(o))return false;"
           "seen.add(o);"
           "try{if(typeof o.sendInputClipper==='function'){o.sendInputClipper(txt);return true;}}catch(e){}"
           "let keys=[];try{keys=Object.getOwnPropertyNames(o).slice(0,400);}catch(e){}"
           "for(const k of keys){"
             "if(['window','self','top','parent','frames','webkit'].includes(k))continue;"
             "let v;try{v=o[k];}catch(e){continue;}"
             "if(tryObj(v,depth+1))return true;"
           "}"
           "return false;"
         "}"
         "if(tryObj(window,0))return 'VMOS_CLIP_OK';"
         "return 'VMOS_CLIP_ENGINE_NOT_FOUND';"
        "})()", literal];

    __block NSInteger pending = webViews.count;
    __block BOOL sent = NO;
    for (WKWebView *wv in webViews) {
        [wv evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
            if (!sent && [result isKindOfClass:NSString.class] &&
                [(NSString *)result isEqualToString:@"VMOS_CLIP_OK"]) {
                sent = YES;
                VMOSShowStatus(@"Sent to the cloud phone clipboard.");
            }
            pending--;
            if (pending == 0 && !sent) {
                VMOSShowStatus(@"VMOS clipboard engine was not found in the current page. Keep the cloud phone screen open and try again.");
            }
        }];
    }
}

@implementation VMOSPasteReceiver
- (instancetype)init {
    self=[super init];
    if(self) self.pasteConfiguration=[[UIPasteConfiguration alloc] initWithAcceptableTypeIdentifiers:@[@"public.utf8-plain-text",@"public.plain-text",@"public.text"]];
    return self;
}
- (BOOL)canPasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders { return itemProviders.count > 0; }
- (void)pasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders {
    NSItemProvider *p=itemProviders.firstObject;
    NSString *type=[p hasItemConformingToTypeIdentifier:@"public.utf8-plain-text"]?@"public.utf8-plain-text":
                   ([p hasItemConformingToTypeIdentifier:@"public.plain-text"]?@"public.plain-text":@"public.text");
    [p loadItemForTypeIdentifier:type options:nil completionHandler:^(id<NSSecureCoding> item,NSError *error){
        if(error){ VMOSShowStatus(error.localizedDescription); return; }
        id object=(id)item;
        NSString *text=nil;
        if([object isKindOfClass:NSString.class]) text=(NSString *)object;
        else if([object isKindOfClass:NSData.class]) text=[[NSString alloc] initWithData:(NSData *)object encoding:NSUTF8StringEncoding];
        if(text.length) dispatch_async(dispatch_get_main_queue(), ^{ SendToVMOSCloudClipboard(text); });
        else VMOSShowStatus(@"Clipboard item is not text.");
    }];
}
@end

static VMOSPasteReceiver *gReceiver;

static void InstallPasteControl(void) {
    if (@available(iOS 16.0, *)) {
        UIWindow *window=nil;
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
            if(scene.activationState!=UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
            for(UIWindow *w in ((UIWindowScene *)scene).windows) if(w.isKeyWindow){window=w;break;}
            if(window)break;
        }
        if(!window)return;
        if([window viewWithTag:0x564D4F53])return;
        gReceiver=[VMOSPasteReceiver new];
        UIPasteControl *pc=[[UIPasteControl alloc] initWithConfiguration:[UIPasteControlConfiguration new]];
        pc.target=gReceiver;
        pc.tag=0x564D4F53;
        pc.frame=CGRectMake(window.bounds.size.width-86, window.safeAreaInsets.top+58, 70, 44);
        pc.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
        [window addSubview:pc];
    }
}

__attribute__((constructor))
static void VMOSPasteInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ InstallPasteControl(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ InstallPasteControl(); });
    }];
}
