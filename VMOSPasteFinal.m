#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface VMOSPasteTarget : NSObject <UIPasteConfigurationSupporting>
@property(nonatomic,strong) UIPasteConfiguration *pasteConfiguration;
@end

static UIWindow *VMOSKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

static void VMOSFindWebViews(UIView *v, NSMutableArray<WKWebView *> *out) {
    if ([v isKindOfClass:WKWebView.class]) [out addObject:(WKWebView *)v];
    for (UIView *x in v.subviews) VMOSFindWebViews(x, out);
}

static NSString *VMOSJSONString(NSString *s) {
    NSData *d=[NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *j=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return j.length>=2 ? [j substringWithRange:NSMakeRange(1,j.length-2)] : @"\"\"";
}

static void VMOSAlert(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w=VMOSKeyWindow();
        UIViewController *vc=w.rootViewController;
        while (vc.presentedViewController) vc=vc.presentedViewController;
        if (!vc) return;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"VMOS Paste" message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static void VMOSSendText(NSString *text) {
    UIWindow *w=VMOSKeyWindow();
    if (!w) { VMOSAlert(@"No active VMOS window."); return; }

    NSMutableArray<WKWebView *> *views=[NSMutableArray array];
    VMOSFindWebViews(w,views);
    if (!views.count) { VMOSAlert(@"VMOS WebView not found."); return; }

    NSString *literal=VMOSJSONString(text);
    NSString *js=[NSString stringWithFormat:
      @"(function(){"
        "const txt=%@;"
        "const ta=document.querySelector('textarea.play-text-input')||"
                 "document.querySelector('textarea[id$=\"_inputEle\"]')||"
                 "document.querySelector('.tcg-fake-input');"
        "if(!ta)return 'NO_INPUT';"
        "try{ta.focus();}catch(e){}"
        "try{"
          "const proto=ta.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;"
          "const setter=Object.getOwnPropertyDescriptor(proto,'value').set;"
          "setter.call(ta,txt);"
        "}catch(e){try{ta.value=txt}catch(_){} }"
        "try{ta.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertText',data:txt}));}catch(e){}"
        "try{ta.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:txt}));}"
        "catch(e){ta.dispatchEvent(new Event('input',{bubbles:true}));}"
        "ta.dispatchEvent(new Event('change',{bubbles:true}));"
        "try{ta.dispatchEvent(new KeyboardEvent('keyup',{bubbles:true,key:'Unidentified'}));}catch(e){}"
        "return 'SENT:'+ta.id+':'+ta.className;"
      "})()",literal];

    __block NSInteger left=views.count;
    __block BOOL ok=NO;
    for (WKWebView *wv in views) {
        [wv evaluateJavaScript:js completionHandler:^(id result,NSError *error){
            if (!ok && [result isKindOfClass:NSString.class] && [(NSString *)result hasPrefix:@"SENT:"]) {
                ok=YES;
                VMOSAlert([NSString stringWithFormat:@"Text sent through VMOS input.\n%@",result]);
            }
            left--;
            if(left==0 && !ok) VMOSAlert(error ? error.localizedDescription : @"VMOS input element was not found.");
        }];
    }
}

@implementation VMOSPasteTarget
- (instancetype)init {
    self=[super init];
    if(self) self.pasteConfiguration=[[UIPasteConfiguration alloc] initWithAcceptableTypeIdentifiers:@[@"public.utf8-plain-text",@"public.plain-text",@"public.text"]];
    return self;
}
- (BOOL)canPasteItemProviders:(NSArray<NSItemProvider *> *)providers { return providers.count>0; }
- (void)pasteItemProviders:(NSArray<NSItemProvider *> *)providers {
    NSItemProvider *p=providers.firstObject;
    NSString *type=[p hasItemConformingToTypeIdentifier:@"public.utf8-plain-text"]?@"public.utf8-plain-text":
                   ([p hasItemConformingToTypeIdentifier:@"public.plain-text"]?@"public.plain-text":@"public.text");
    [p loadItemForTypeIdentifier:type options:nil completionHandler:^(id<NSSecureCoding> item,NSError *error){
        if(error){VMOSAlert(error.localizedDescription);return;}
        id obj=(id)item;
        NSString *s=nil;
        if([obj isKindOfClass:NSString.class]) s=(NSString *)obj;
        else if([obj isKindOfClass:NSData.class]) s=[[NSString alloc] initWithData:(NSData *)obj encoding:NSUTF8StringEncoding];
        if(s.length) dispatch_async(dispatch_get_main_queue(),^{VMOSSendText(s);});
        else VMOSAlert(@"Clipboard does not contain text.");
    }];
}
@end

static VMOSPasteTarget *gTarget;

static void VMOSInstall(void) {
    if (@available(iOS 16.0,*)) {
        UIWindow *w=VMOSKeyWindow(); if(!w) return;
        if([w viewWithTag:0x564D5046]) return;
        gTarget=[VMOSPasteTarget new];
        UIPasteControlConfiguration *cfg=[UIPasteControlConfiguration new];
        UIPasteControl *pc=[[UIPasteControl alloc] initWithConfiguration:cfg];
        pc.target=gTarget;
        pc.tag=0x564D5046;
        pc.frame=CGRectMake(w.bounds.size.width-92,w.safeAreaInsets.top+58,78,44);
        pc.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
        [w addSubview:pc];
    }
}

__attribute__((constructor))
static void VMOSInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{VMOSInstall();});
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{VMOSInstall();});
    }];
}
