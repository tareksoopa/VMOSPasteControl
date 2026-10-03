#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static NSInteger gLastChange = -1;
static NSString *gLastSynced = nil;
static BOOL gBusy = NO;

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
static NSString *JSONLiteral(NSString *s) {
    NSData *d=[NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *j=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return j.length>=2 ? [j substringWithRange:NSMakeRange(1,j.length-2)] : @"\"\"";
}

static void SyncClipboard(void) {
    if (gBusy) return;
    UIPasteboard *pb=UIPasteboard.generalPasteboard;
    NSInteger cc=pb.changeCount;
    if (cc==gLastChange) return;
    gLastChange=cc;
    if (!pb.hasStrings) return;

    NSString *text=pb.string;
    if (!text.length || [text isEqualToString:gLastSynced]) return;

    UIWindow *w=KeyWindow(); if(!w) return;
    NSMutableArray<WKWebView *> *views=[NSMutableArray array];
    FindWebViews(w,views);
    if(!views.count) return;

    gBusy=YES;
    NSString *lit=JSONLiteral(text);
    NSString *js=[NSString stringWithFormat:
      @"(async function(){"
        "const wanted=%@;"
        "const sleep=ms=>new Promise(r=>setTimeout(r,ms));"
        "function visible(e){if(!e)return false;const s=getComputedStyle(e);return s.display!=='none'&&s.visibility!=='hidden';}"
        "function exactText(e,t){return ((e.innerText||e.textContent||'').trim()===t);}"
        "function clipboardButton(){"
          "return [...document.querySelectorAll('button.card')].find(e=>exactText(e,'Clipboard'));"
        "}"
        "function moreButton(){"
          "return [...document.querySelectorAll('button,.card,div')].find(e=>visible(e)&&exactText(e,'More'));"
        "}"
        "let cb=clipboardButton();"
        "if(!cb){const m=moreButton();if(m){m.click();await sleep(250);}cb=clipboardButton();}"
        "if(!cb)return 'NO_CLIPBOARD_BUTTON';"
        "cb.click();"
        "await sleep(80);"
        "const openedPopup=document.querySelector('.play-popup');"
        "if(openedPopup){openedPopup.style.setProperty('visibility','hidden','important');openedPopup.style.setProperty('pointer-events','none','important');}"
        "for(let i=0;i<30;i++){"
          "await sleep(120);"
          "const items=[...document.querySelectorAll('.clipboard-panel .clipboards .item')];"
          "const hit=items.find(it=>{const t=it.querySelector('.text');return t&&((t.innerText||t.textContent||'').trim()===wanted);});"
          "if(hit){hit.click();await sleep(60);const popup=document.querySelector('.play-popup');if(popup){popup.style.setProperty('display','none','important');}return 'SYNCED';}"
        "}"
        "return 'ITEM_NOT_FOUND';"
      "})()",lit];

    __block NSInteger pending=views.count;
    __block BOOL synced=NO;
    for(WKWebView *wv in views){
        [wv evaluateJavaScript:js completionHandler:^(id result,NSError *error){
            if(!synced && [result isKindOfClass:NSString.class] && [(NSString *)result isEqualToString:@"SYNCED"]){
                synced=YES;
                gLastSynced=[text copy];
            }
            pending--;
            if(pending==0) gBusy=NO;
        }];
    }
}

static void AppActive(NSNotification *n) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ SyncClipboard(); });
}

__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gLastChange = -1;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *n){ AppActive(n); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIPasteboardChangedNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *n){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ SyncClipboard(); });
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ SyncClipboard(); });
    });
}
