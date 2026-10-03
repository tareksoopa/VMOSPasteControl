#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static NSMutableString *gLog;

static void AddLog(NSString *s) {
    if (!gLog) gLog = [NSMutableString string];
    [gLog appendFormat:@"%@\n", s ?: @""];
}

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

@interface VMOSWebDiag : NSObject
@end

@implementation VMOSWebDiag

- (void)scan {
    UIWindow *w = KeyWindow();
    if (!w) { AddLog(@"NO KEY WINDOW"); return; }

    NSMutableArray<WKWebView *> *views = [NSMutableArray array];
    FindWebViews(w, views);
    AddLog([NSString stringWithFormat:@"SCAN: %lu WKWebView(s)", (unsigned long)views.count]);

    NSString *js =
    @"(function(){"
      "const hits=[];"
      "const seen=new Set();"
      "const re=/(clip|paste|input|copy)/i;"
      "function walk(o,path,d){"
        "if(!o||d>3||(typeof o!=='object'&&typeof o!=='function')||seen.has(o))return;"
        "seen.add(o);"
        "let ks=[];try{ks=Object.getOwnPropertyNames(o).slice(0,600)}catch(e){return}"
        "for(const k of ks){"
          "let v;try{v=o[k]}catch(e){continue}"
          "const p=path+'.'+k;"
          "if(re.test(k)){"
            "let t=typeof v;"
            "let sig='';"
            "if(t==='function'){try{sig=String(v).slice(0,240)}catch(e){}}"
            "hits.push(p+' ['+t+'] '+sig);"
          "}"
          "if(d<3 && v && (typeof v==='object'||typeof v==='function') && "
             "!['window','self','top','parent','frames','webkit','document','location'].includes(k)){"
             "walk(v,p,d+1);"
          "}"
        "}"
      "}"
      "walk(window,'window',0);"
      "try{"
        "const els=[...document.querySelectorAll('*')];"
        "for(const e of els){"
          "const txt=((e.innerText||'')+' '+(e.getAttribute&&e.getAttribute('aria-label')||'')+' '+(e.className||'')+' '+(e.id||''));"
          "if(re.test(txt)) hits.push('DOM '+e.tagName+'#'+(e.id||'')+'.'+(typeof e.className==='string'?e.className:'')+' text='+txt.slice(0,180));"
        "}"
      "}catch(e){}"
      "return hits.slice(0,500).join('\\n');"
    "})()";

    if (!views.count) AddLog(@"NO WKWEBVIEW FOUND");

    for (NSUInteger i=0; i<views.count; i++) {
        WKWebView *wv = views[i];
        [wv evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
            if (error) {
                AddLog([NSString stringWithFormat:@"WEBVIEW %lu ERROR: %@", (unsigned long)i, error]);
            } else {
                AddLog([NSString stringWithFormat:@"--- WEBVIEW %lu ---\n%@", (unsigned long)i, result ?: @"<empty>"]);
            }
        }];
    }
}

- (void)showLog {
    UIWindow *w=KeyWindow();
    UIViewController *vc=w.rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;

    NSString *msg=gLog.length?gLog:@"No scan yet.";
    UITextView *tv=[[UITextView alloc] initWithFrame:CGRectMake(0,0,300,420)];
    tv.text=msg; tv.editable=NO; tv.selectable=YES; tv.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];

    UIViewController *box=[UIViewController new];
    box.preferredContentSize=CGSizeMake(320,440);
    [box.view addSubview:tv];
    tv.frame=box.view.bounds; tv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;

    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"VMOS Web Scan" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a setValue:box forKey:@"contentViewController"];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy Log" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
        UIPasteboard.generalPasteboard.string=gLog ?: @"";
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x){
        [gLog setString:@""];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

@end

static VMOSWebDiag *gDiag;

static void Install(void) {
    UIWindow *w=KeyWindow(); if(!w) return;
    if([w viewWithTag:0x5653434E]) return;
    gDiag=[VMOSWebDiag new];

    UIButton *scan=[UIButton buttonWithType:UIButtonTypeSystem];
    scan.tag=0x5653434E;
    scan.frame=CGRectMake(w.bounds.size.width-82,w.safeAreaInsets.top+58,68,40);
    scan.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
    [scan setTitle:@"SCAN" forState:UIControlStateNormal];
    scan.backgroundColor=[UIColor colorWithWhite:0.1 alpha:.88];
    [scan setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    scan.layer.cornerRadius=9;
    [scan addTarget:gDiag action:@selector(scan) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:scan];

    UIButton *log=[UIButton buttonWithType:UIButtonTypeSystem];
    log.frame=CGRectMake(w.bounds.size.width-82,w.safeAreaInsets.top+104,68,40);
    log.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
    [log setTitle:@"LOG" forState:UIControlStateNormal];
    log.backgroundColor=[UIColor colorWithWhite:0.1 alpha:.88];
    [log setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    log.layer.cornerRadius=9;
    [log addTarget:gDiag action:@selector(showLog) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:log];

    AddLog(@"VMOS Web diagnostic ready");
}

__attribute__((constructor))
static void Init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ Install(); });
}
