#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface Browser : UIViewController <WKNavigationDelegate,WKUIDelegate>
@property(nonatomic,strong) WKWebView *web;
@end
@implementation Browser
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Phimbar";self.view.backgroundColor=UIColor.blackColor;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;
    config.allowsInlineMediaPlayback=YES;config.allowsPictureInPictureMediaPlayback=YES;
    config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeNone;
    NSString *path=[NSBundle.mainBundle pathForResource:@"compat" ofType:@"js"];
    NSString *script=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *css=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"legacy" ofType:@"css"] encoding:NSUTF8StringEncoding error:nil]?:@"";
    NSData *data=[NSJSONSerialization dataWithJSONObject:@[css] options:0 error:nil];
    NSString *encoded=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    script=[NSString stringWithFormat:@"window.__phimbarLegacyCSS=%@[0];\n%@",encoded,script?:@""];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    self.web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:config];self.web.translatesAutoresizingMaskIntoConstraints=NO;self.web.navigationDelegate=self;self.web.UIDelegate=self;self.web.allowsBackForwardNavigationGestures=YES;
    [self.view addSubview:self.web];
    [NSLayoutConstraint activateConstraints:@[[self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.web.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    self.toolbarItems=@[[[UIBarButtonItem alloc] initWithTitle:@"‹" style:0 target:self action:@selector(back)],[[UIBarButtonItem alloc] initWithTitle:@"›" style:0 target:self action:@selector(forward)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:@"Trang chủ" style:0 target:self action:@selector(home)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Tùy chọn" style:0 target:self action:@selector(options)];
    self.navigationController.toolbarHidden=NO;[self home];
}
- (void)home {[self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://phimbar.com/"]]];}
- (void)back {if(self.web.canGoBack)[self.web goBack];}
- (void)forward {if(self.web.canGoForward)[self.web goForward];}
- (void)reload {[self.web reload];}
- (void)options {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Phimbar • iOS 15" message:@"Lớp tương thích dành cho iOS cũ. Đăng nhập và VIP do Phimbar xử lý." preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Sửa lại giao diện" style:0 handler:^(UIAlertAction *v){[self.web evaluateJavaScript:@"window.PhimbarCompat&&window.PhimbarCompat.apply()" completionHandler:nil];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Giao diện gốc" style:0 handler:^(UIAlertAction *v){[self.web evaluateJavaScript:@"document.getElementById('phimbar-ios-legacy')?.remove()" completionHandler:nil];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Mở trong Safari" style:0 handler:^(UIAlertAction *v){NSURL *u=self.web.URL;if([u.scheme isEqual:@"https"])[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {self.title=@"Phimbar";}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {if(error.code==NSURLErrorCancelled)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Không tải được trang" message:error.localizedDescription preferredStyle:1];[a addAction:[UIAlertAction actionWithTitle:@"Thử lại" style:0 handler:^(UIAlertAction *v){[self reload];}]];[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:1 handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *u=action.request.URL;NSString *host=u.host.lowercaseString;
    if([u.scheme isEqual:@"https"]&&([host isEqual:@"phimbar.com"]||[host hasSuffix:@".phimbar.com"])) {handler(WKNavigationActionPolicyAllow);return;}
    if(action.targetFrame&&!action.targetFrame.mainFrame){handler(WKNavigationActionPolicyAllow);return;}
    handler(WKNavigationActionPolicyCancel);
    if([u.scheme isEqual:@"https"]&&action.navigationType==WKNavigationTypeLinkActivated){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Mở trang ngoài Phimbar?" message:host preferredStyle:1];[a addAction:[UIAlertAction actionWithTitle:@"Mở Safari" style:0 handler:^(UIAlertAction *v){[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];}]];[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:1 handler:nil]];[self presentViewController:a animated:YES completion:nil];}
}
- (WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {if(!action.targetFrame)[web loadRequest:action.request];return nil;}
- (void)webView:(WKWebView *)web runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))done {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Phimbar" message:message preferredStyle:1];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:^(UIAlertAction *v){done();}]];[self presentViewController:a animated:YES completion:nil];}
- (void)webView:(WKWebView *)web runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))done {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Phimbar" message:message preferredStyle:1];[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:1 handler:^(UIAlertAction *v){done(NO);}]];[a addAction:[UIAlertAction actionWithTitle:@"Xác nhận" style:0 handler:^(UIAlertAction *v){done(YES);}]];[self presentViewController:a animated:YES completion:nil];}
@end
@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation App
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[Browser new]];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}