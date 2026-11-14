#import <UIKit/UIKit.h>
#import <dlfcn.h>

// Runtime-only calls: these private services are present on iOS 15, but
// access still depends on TrollStore granting the signed entitlements.
@interface NSObject (RestartSystemAPI)
+ (id)sharedService;
+ (id)defaultWorkspace;
- (int)pidForApplication:(NSString *)identifier;
- (void)terminateApplication:(NSString *)identifier forReason:(long long)reason andReport:(BOOL)report withDescription:(NSString *)description completion:(void (^)(NSError *error))completion;
- (BOOL)openApplicationWithBundleID:(NSString *)identifier;
@end

static NSString *const MessengerID = @"com.facebook.Messenger";

@interface RestartView : UIViewController
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *detail;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) id systemService;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger generation;
- (void)restartMessenger;
@end

@implementation RestartView
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:0.035 green:0.055 blue:0.10 alpha:1];
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:66 weight:UIImageSymbolWeightMedium];
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise.circle.fill" withConfiguration:config]];
    icon.tintColor=[UIColor colorWithRed:0.28 green:0.63 blue:1 alpha:1];
    icon.contentMode=UIViewContentModeScaleAspectFit;icon.isAccessibilityElement=NO;
    self.status=[UILabel new];self.status.font=[UIFont systemFontOfSize:25 weight:UIFontWeightSemibold];self.status.textColor=UIColor.whiteColor;self.status.textAlignment=NSTextAlignmentCenter;self.status.numberOfLines=0;
    self.detail=[UILabel new];self.detail.font=[UIFont systemFontOfSize:16];self.detail.textColor=UIColor.secondaryLabelColor;self.detail.textAlignment=NSTextAlignmentCenter;self.detail.numberOfLines=0;
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.spinner.hidesWhenStopped=YES;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[icon,self.status,self.detail,self.spinner]];
    stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=22;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],[stack.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.84],[self.status.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[self.detail.widthAnchor constraintEqualToAnchor:stack.widthAnchor]]];
}
- (void)fail:(NSString *)message {
    self.busy=NO;self.generation++;[self.spinner stopAnimating];
    self.status.text=@"Chưa mở lại được";self.detail.text=message;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,self.status.text);
}
- (void)launchMessenger {
    if(!self.busy)return;
    self.status.text=@"Đang mở Messenger…";
    Class workspaceClass=NSClassFromString(@"LSApplicationWorkspace");
    if(![workspaceClass respondsToSelector:@selector(defaultWorkspace)]){[self fail:@"Không tìm thấy dịch vụ mở ứng dụng. Hãy gửi ảnh màn hình này để kiểm tra."];return;}
    id workspace=[workspaceClass defaultWorkspace];
    if(![workspace respondsToSelector:@selector(openApplicationWithBundleID:)] || ![workspace openApplicationWithBundleID:MessengerID]) {
        [self fail:@"Không mở được Messenger. Kiểm tra Messenger bản App Store vẫn còn trên máy."];return;
    }
    // The successful launch switches away from this screen automatically.
    // Show no success claim: actual foreground launch must be observed on-device.
    NSUInteger token=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.busy && token==self.generation && UIApplication.sharedApplication.applicationState==UIApplicationStateActive)
            [self fail:@"iOS chưa chuyển sang Messenger. Hãy gửi ảnh màn hình này để kiểm tra quyền mở ứng dụng."];
    });
}
- (void)waitForExit:(int)oldPID attempt:(NSUInteger)attempt token:(NSUInteger)token {
    if(!self.busy || token!=self.generation)return;
    int currentPID=[self.systemService pidForApplication:MessengerID];
    if(currentPID==0){[self launchMessenger];return;}
    if(currentPID<0){[self fail:@"Không xác minh được Messenger đã đóng. Hãy gửi ảnh màn hình này để kiểm tra quyền TrollStore."];return;}
    if(currentPID!=oldPID){[self launchMessenger];return;}
    if(attempt>=24){[self fail:@"Messenger vẫn đang chạy. iOS chưa cho phép đóng ứng dụng trên máy này. Hãy gửi ảnh màn hình này."];return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self waitForExit:oldPID attempt:attempt+1 token:token];});
}
- (void)restartMessenger {
    if(self.busy)return;
    self.busy=YES;NSUInteger token=++self.generation;
    self.status.text=@"Đang mở lại Messenger…";self.detail.text=@"Chờ một chút, app sẽ tự chuyển sang Messenger.";[self.spinner startAnimating];
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_LAZY);
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_LAZY);
    Class serviceClass=NSClassFromString(@"FBSSystemService");
    if(![serviceClass respondsToSelector:@selector(sharedService)]){[self fail:@"Không tìm thấy dịch vụ đóng ứng dụng trên phiên bản iOS này."];return;}
    self.systemService=[serviceClass sharedService];
    SEL terminate=@selector(terminateApplication:forReason:andReport:withDescription:completion:);
    if(![self.systemService respondsToSelector:@selector(pidForApplication:)] || ![self.systemService respondsToSelector:terminate]){[self fail:@"Dịch vụ iOS không hỗ trợ thao tác cần thiết. Hãy gửi ảnh màn hình này."];return;}
    int oldPID=[self.systemService pidForApplication:MessengerID];
    if(oldPID==0){[self launchMessenger];return;}
    if(oldPID<0){[self fail:@"iOS không cho đọc trạng thái Messenger. Hãy chắc chắn app này được cài bằng TrollStore."];return;}
    // Only this fixed bundle ID can be terminated. No process enumeration,
    // shell, account access, app-data deletion, or periodic background loop.
    [self.systemService terminateApplication:MessengerID forReason:5 andReport:NO withDescription:@"User requested Messenger restart" completion:^(NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.busy || token!=self.generation)return;
            if(error){[self fail:[NSString stringWithFormat:@"iOS từ chối đóng Messenger (%@/%ld). Hãy gửi ảnh màn hình này.",error.domain,(long)error.code]];return;}
            [self waitForExit:oldPID attempt:0 token:token];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.busy && token==self.generation && UIApplication.sharedApplication.applicationState==UIApplicationStateActive)
            [self fail:@"iOS chưa hoàn tất yêu cầu mở lại. Hãy gửi ảnh màn hình này để kiểm tra."];
    });
}
@end

@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) RestartView *controller;
@end
@implementation App
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.controller=[RestartView new];self.window.rootViewController=self.controller;[self.window makeKeyAndVisible];return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(application.applicationState==UIApplicationStateActive)[self.controller restartMessenger];
    });
}
- (void)applicationDidEnterBackground:(UIApplication *)application {self.controller.busy=NO;self.controller.generation++;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}
