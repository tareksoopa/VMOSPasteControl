#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface VMOSPasteReceiver : UIResponder <UIPasteConfigurationSupporting>
@property(nonatomic, copy) UIPasteConfiguration *pasteConfiguration;
@end

static UIWindow *KeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

static void FindWebViews(UIView *v, NSMutableArray<WKWebView *> *out) {
    if ([v isKindOfClass:WKWebView.class]) [out addObject:(WKWebView *)v];
    for (UIView *x in v.subviews) FindWebViews(x, out);
}

static NSString *JSONLiteral(NSString *s) {
    NSData *d=[NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *j=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return j.length>=2 ? [j substringWithRange:NSMakeRange(1,j.length-2)] : @"\"\"";
}

static void Status(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w=KeyWindow(); UIViewController *vc=w.rootViewController;
        while(vc.presentedViewController) vc=vc.presentedViewController;
        if(!vc) return;
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"VMOS Paste" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static void SendToVMOS(NSString *text) {
    UIWindow *w=KeyWindow(); if(!w){Status(@"No active VMOS window.");return;}
    NSMutableArray<WKWebView *> *views=[NSMutableArray array]; FindWebViews(w,views);
    if(!views.count){Status(@"VMOS WebView not found.");return;}

    NSString *lit=JSONLiteral(text);
    NSString *js=[NSString stringWithFormat:
      @"(function(){"
        "const txt=%@;"
        "const ta=document.querySelector('textarea.play-text-input')||document.querySelector('textarea[id$=\"_inputEle\"]');"
        "if(!ta)return 'NO_INPUT';"
        "try{ta.focus()}catch(e){}"
        "try{const s=Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set;s.call(ta,txt)}catch(e){ta.value=txt}"
        "try{ta.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertText',data:txt}))}catch(e){}"
        "try{ta.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:txt}))}catch(e){ta.dispatchEvent(new Event('input',{bubbles:true}))}"
        "ta.dispatchEvent(new Event('change',{bubbles:true}));"
        "return 'SENT:'+ta.id;"
      "})()",lit];

    __block NSInteger pending=views.count; __block BOOL success=NO;
    for(WKWebView *wv in views){
        [wv evaluateJavaScript:js completionHandler:^(id result,NSError *error){
            if(!success && [result isKindOfClass:NSString.class] && [(NSString *)result hasPrefix:@"SENT:"]){
                success=YES; Status([NSString stringWithFormat:@"Received and sent to VMOS.\n%@",result]);
            }
            pending--;
            if(pending==0 && !success) Status(error.localizedDescription ?: @"VMOS input not found.");
        }];
    }
}

@implementation VMOSPasteReceiver
- (instancetype)init {
    self=[super init];
    if(self){
        if (@available(iOS 14.0,*)) {
            self.pasteConfiguration=[[UIPasteConfiguration alloc] initWithAcceptableTypeIdentifiers:@[UTTypePlainText.identifier,UTTypeUTF8PlainText.identifier]];
        } else {
            self.pasteConfiguration=[[UIPasteConfiguration alloc] initWithAcceptableTypeIdentifiers:@[@"public.plain-text",@"public.utf8-plain-text"]];
        }
    }
    return self;
}
- (BOOL)canPasteItemProviders:(NSArray<NSItemProvider *> *)providers { return providers.count>0; }
- (void)pasteItemProviders:(NSArray<NSItemProvider *> *)providers {
    Status(@"iOS delivered the clipboard item.");
    NSItemProvider *p=providers.firstObject;
    NSString *type=nil;
    if (@available(iOS 14.0,*)) {
        if([p hasItemConformingToTypeIdentifier:UTTypeUTF8PlainText.identifier]) type=UTTypeUTF8PlainText.identifier;
        else if([p hasItemConformingToTypeIdentifier:UTTypePlainText.identifier]) type=UTTypePlainText.identifier;
    }
    if(!type) type=@"public.text";
    [p loadItemForTypeIdentifier:type options:nil completionHandler:^(id<NSSecureCoding> item,NSError *error){
        if(error){Status(error.localizedDescription);return;}
        id obj=(id)item; NSString *s=nil;
        if([obj isKindOfClass:NSString.class]) s=(NSString *)obj;
        else if([obj isKindOfClass:NSData.class]) s=[[NSString alloc] initWithData:(NSData *)obj encoding:NSUTF8StringEncoding];
        if(s.length) dispatch_async(dispatch_get_main_queue(),^{ SendToVMOS(s); });
        else Status(@"Clipboard text could not be decoded.");
    }];
}
@end

static VMOSPasteReceiver *receiver;

static void Install(void) {
    if (@available(iOS 16.0,*)) {
        UIWindow *w=KeyWindow(); if(!w)return;
        if([w viewWithTag:0x564D5047])return;
        receiver=[VMOSPasteReceiver new];

        UIPasteControlConfiguration *cfg=[UIPasteControlConfiguration new];
        cfg.displayMode=UIPasteControlDisplayModeIconAndLabel;
        cfg.baseBackgroundColor=[UIColor systemBlueColor];
        cfg.baseForegroundColor=[UIColor whiteColor];
        cfg.cornerStyle=UIPasteControlCornerStyleCapsule;

        UIPasteControl *pc=[[UIPasteControl alloc] initWithConfiguration:cfg];
        pc.target=receiver;
        pc.tag=0x564D5047;
        pc.frame=CGRectMake(w.bounds.size.width-130,w.safeAreaInsets.top+58,116,50);
        pc.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
        [w addSubview:pc];
    }
}

__attribute__((constructor))
static void Init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Install();});
}
