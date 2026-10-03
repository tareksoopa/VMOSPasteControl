#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static UIWindow *KeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}
static void FindWebViews(UIView *v, NSMutableArray<WKWebView *> *out) {
    if ([v isKindOfClass:WKWebView.class]) [out addObject:(WKWebView *)v];
    for (UIView *x in v.subviews) FindWebViews(x,out);
}
static void Show(NSString *text) {
    UIWindow *w=KeyWindow(); UIViewController *vc=w.rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Clipboard Item Inspector"
        message:text ?: @"<empty>" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
        UIPasteboard.generalPasteboard.string=text ?: @"";
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

@interface ClipItemInspector : NSObject @end
@implementation ClipItemInspector
- (void)inspect {
    UIWindow *w=KeyWindow(); NSMutableArray<WKWebView *> *views=[NSMutableArray array];
    FindWebViews(w,views);
    if(!views.count){Show(@"NO WKWEBVIEW");return;}

    NSString *js =
    @"(function(){"
      "const out=[];"
      "const all=[...document.querySelectorAll('*')];"
      "const candidates=all.filter(e=>{"
        "const t=(e.innerText||'').trim();"
        "return t && t.length<500 && "
          "(t==='Clipboard'||/Recently Copied Text/i.test(t)||"
           "(e.closest && e.closest('.play-popup') && /clipboard/i.test(t)));"
      "});"
      "out.push('CANDIDATES='+candidates.length);"
      "for(const e of candidates.slice(0,30)){"
        "out.push('\\n=== ELEMENT ===');"
        "out.push((e.outerHTML||'').slice(0,2500));"
        "let cur=e;"
        "for(let depth=0;cur&&depth<4;depth++,cur=cur.parentElement){"
          "out.push('LEVEL '+depth+' '+cur.tagName+'#'+(cur.id||'')+'.'+(typeof cur.className==='string'?cur.className:''));"
          "const ks=Object.getOwnPropertyNames(cur);"
          "for(const k of ks){"
            "if(k.startsWith('_vei')||k.startsWith('__vue')||/click|event/i.test(k)){"
              "let v;try{v=cur[k]}catch(err){continue}"
              "let s='';try{s=String(v)}catch(err){s='<unprintable>'}"
              "out.push('PROP '+k+' ['+typeof v+'] '+s.slice(0,3000));"
              "if(v&&typeof v==='object'){"
                "let sk=[];try{sk=Object.getOwnPropertyNames(v)}catch(err){}"
                "for(const q of sk.slice(0,80)){"
                  "let sv;try{sv=v[q]}catch(err){continue}"
                  "let ss='';try{ss=String(sv)}catch(err){continue}"
                  "out.push('  SUB '+q+' ['+typeof sv+'] '+ss.slice(0,2500));"
                "}"
              "}"
            "}"
          "}"
          "try{out.push('onclick='+String(cur.onclick))}catch(err){}"
        "}"
      "}"
      "return out.join('\\n').slice(0,45000);"
    "})()";

    [views.firstObject evaluateJavaScript:js completionHandler:^(id result,NSError *error){
        Show(error ? error.localizedDescription : ([result description] ?: @"<empty>"));
    }];
}
@end

static ClipItemInspector *gInspector;
static void Install(void){
    UIWindow *w=KeyWindow(); if(!w)return;
    if([w viewWithTag:0x434C4954])return;
    gInspector=[ClipItemInspector new];
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.tag=0x434C4954;
    b.frame=CGRectMake(w.bounds.size.width-105,w.safeAreaInsets.top+58,91,44);
    b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
    [b setTitle:@"ITEM INSPECT" forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    b.backgroundColor=[UIColor colorWithWhite:.1 alpha:.9];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.layer.cornerRadius=9;
    [b addTarget:gInspector action:@selector(inspect) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:b];
}
__attribute__((constructor))
static void Init(void){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Install();});
}
