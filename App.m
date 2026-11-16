#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <CallKit/CallKit.h>
#import <unistd.h>
#import "RestartSchedule.h"

// Runtime-only calls: these private services are present on iOS 15, but
// access still depends on TrollStore granting the signed entitlements.
@interface NSObject (RestartSystemAPI)
+ (id)sharedService;
+ (id)defaultWorkspace;
- (int)pidForApplication:(NSString *)identifier;
- (void)terminateApplication:(NSString *)identifier forReason:(long long)reason andReport:(BOOL)report withDescription:(NSString *)description completion:(void (^)(NSError *error))completion;
- (BOOL)openApplicationWithBundleID:(NSString *)identifier;
- (BOOL)isPasscodeLockedOrBlocked;
- (id)initWithPID:(int)pid flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(void (^)(BOOL acquired))handler;
- (BOOL)isValid;
- (BOOL)valid;
- (void)invalidate;
- (void)setInvalidationHandler:(void (^)(void))handler;
@end

static NSString *const MessengerID = @"com.facebook.Messenger";

@interface RestartView : UIViewController {
    RestartSchedule _schedule;
}
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *detail;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) id systemService;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger session;
@property(nonatomic) BOOL starting;
@property(nonatomic) BOOL launchPending;
@property(nonatomic,strong) id backgroundAssertion;
@property(nonatomic,strong) CXCallObserver *callObserver;
- (void)restartMessenger;
- (void)toggleAutomation;
- (void)enteredBackground;
@end

@implementation RestartView
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:0.035 green:0.055 blue:0.10 alpha:1];
    self.callObserver=[CXCallObserver new];
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
- (BOOL)isSafeToRestart {
    // If lock state cannot be read, do not launch apps unattended.
    if(![self.systemService respondsToSelector:@selector(isPasscodeLockedOrBlocked)] || [self.systemService isPasscodeLockedOrBlocked])return NO;
    for(CXCall *call in self.callObserver.calls)if(!call.hasEnded)return NO;
    return YES;
}
- (BOOL)backgroundIsValid {
    if([self.backgroundAssertion respondsToSelector:@selector(valid)])return [self.backgroundAssertion valid];
    if([self.backgroundAssertion respondsToSelector:@selector(isValid)])return [self.backgroundAssertion isValid];
    return NO;
}
- (void)stopAutomation {
    self.session++;self.generation++;self.starting=NO;self.busy=NO;self.launchPending=NO;
    RestartScheduleStop(&_schedule);
    id assertion=self.backgroundAssertion;self.backgroundAssertion=nil;
    if([assertion respondsToSelector:@selector(setInvalidationHandler:)])[assertion setInvalidationHandler:nil];
    if([assertion respondsToSelector:@selector(invalidate)])[assertion invalidate];
    [self.spinner stopAnimating];
}
- (void)scheduleNextTick {
    if(!_schedule.enabled)return;
    NSUInteger token=self.session;
    double wait=MAX(0.01,_schedule.nextDue-NSProcessInfo.processInfo.systemUptime);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(wait*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(token!=self.session || !self->_schedule.enabled)return;
        if(![self backgroundIsValid]){[self fail:@"iOS đã thu hồi quyền chạy nền. Chế độ tự động đã dừng."];return;}
        BOOL eligible=!self.busy && [self isSafeToRestart];
        if(RestartScheduleTick(&self->_schedule,NSProcessInfo.processInfo.systemUptime,eligible))[self restartMessenger];
        [self scheduleNextTick];
    });
}
- (void)toggleAutomation {
    if(_schedule.enabled || self.starting){
        [self stopAutomation];self.status.text=@"Đã tắt tự động";self.detail.text=@"Messenger sẽ không bị mở lại định kỳ.\nChạm lại biểu tượng để bật.";return;
    }
    self.starting=YES;NSUInteger token=++self.session;
    self.status.text=@"Đang bật chế độ 30 giây…";self.detail.text=@"Chạm lại biểu tượng để tắt.\nTạm ngưng khi khóa màn hình hoặc có cuộc gọi được iOS nhận diện.";[self.spinner startAnimating];
    dlopen("/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices",RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_LAZY);
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_LAZY);
    Class serviceClass=NSClassFromString(@"FBSSystemService");
    self.systemService=[serviceClass respondsToSelector:@selector(sharedService)]?[serviceClass sharedService]:nil;
    if(![self.systemService respondsToSelector:@selector(isPasscodeLockedOrBlocked)]){[self fail:@"Không kiểm tra được trạng thái khóa máy nên chưa bật tự động."];return;}
    Class cls=NSClassFromString(@"BKSProcessAssertion");
    SEL initializer=@selector(initWithPID:flags:reason:name:withHandler:);
    if(!cls || ![cls instancesRespondToSelector:initializer] || (![cls instancesRespondToSelector:@selector(valid)] && ![cls instancesRespondToSelector:@selector(isValid)])){[self fail:@"iOS này chưa hỗ trợ cách giữ tiện ích chạy nền. Chế độ 30 giây chưa được bật."];return;}
    // Self-only assertion: prevent suspension but allow device idle sleep.
    // FinishTaskUnbounded (10004) needs the separately signed privileged rights.
    __weak RestartView *weakSelf=self;
    self.backgroundAssertion=[[cls alloc] initWithPID:getpid() flags:5 reason:10004 name:@"Messenger restart timer" withHandler:^(BOOL acquired){
        dispatch_async(dispatch_get_main_queue(),^{
            RestartView *s=weakSelf;if(!s || s.session!=token || !s.starting)return;
            if(!acquired || ![s backgroundIsValid]){[s fail:@"iOS không cấp quyền chạy nền. Chế độ 30 giây chưa được bật. Hãy gửi ảnh màn hình này."];return;}
            s.starting=NO;RestartScheduleStart(&s->_schedule,NSProcessInfo.processInfo.systemUptime);
            s.status.text=@"Đã bật chu kỳ 30 giây";[s.spinner stopAnimating];
            [s scheduleNextTick];
            if([s isSafeToRestart])[s restartMessenger];
        });
    }];
    if([self.backgroundAssertion respondsToSelector:@selector(setInvalidationHandler:)]) {
        [self.backgroundAssertion setInvalidationHandler:^{dispatch_async(dispatch_get_main_queue(),^{
            RestartView *s=weakSelf;if(s && s.session==token)[s fail:@"Quyền chạy nền đã hết hiệu lực. Chế độ tự động đã dừng."];
        });}];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.session==token && self.starting)[self fail:@"iOS chưa xác nhận quyền chạy nền. Chế độ 30 giây chưa được bật."];
    });
}
- (void)fail:(NSString *)message {
    [self stopAutomation];
    self.status.text=@"Chưa mở lại được";self.detail.text=message;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,self.status.text);
}
- (void)launchMessenger {
    if(!self.busy)return;
    if(![self isSafeToRestart]){self.busy=NO;self.generation++;return;}
    self.status.text=@"Đang mở Messenger…";
    BOOL wasForeground=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    self.launchPending=YES;
    Class workspaceClass=NSClassFromString(@"LSApplicationWorkspace");
    if(![workspaceClass respondsToSelector:@selector(defaultWorkspace)]){[self fail:@"Không tìm thấy dịch vụ mở ứng dụng. Hãy gửi ảnh màn hình này để kiểm tra."];return;}
    id workspace=[workspaceClass defaultWorkspace];
    if(![workspace respondsToSelector:@selector(openApplicationWithBundleID:)] || ![workspace openApplicationWithBundleID:MessengerID]) {
        [self fail:@"Không mở được Messenger. Kiểm tra Messenger bản App Store vẫn còn trên máy."];return;
    }
    if(!wasForeground){self.launchPending=NO;self.busy=NO;self.generation++;return;}
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
    if(self.busy || !_schedule.enabled || ![self isSafeToRestart])return;
    self.busy=YES;NSUInteger token=++self.generation;
    self.status.text=@"Đang mở lại Messenger…";self.detail.text=@"Đã bật chu kỳ 30 giây.\nChạm lại biểu tượng Mở lại Mess để tắt.";[self.spinner startAnimating];
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
    // shell, account access, or app-data deletion.
    [self.systemService terminateApplication:MessengerID forReason:5 andReport:NO withDescription:@"User requested Messenger restart" completion:^(NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.busy || token!=self.generation)return;
            if(error){[self fail:[NSString stringWithFormat:@"iOS từ chối đóng Messenger (%@/%ld). Hãy gửi ảnh màn hình này.",error.domain,(long)error.code]];return;}
            [self waitForExit:oldPID attempt:0 token:token];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.busy && token==self.generation)
            [self fail:@"iOS chưa hoàn tất yêu cầu mở lại. Hãy gửi ảnh màn hình này để kiểm tra."];
    });
}
- (void)enteredBackground {
    if(self.launchPending){self.launchPending=NO;self.busy=NO;self.generation++;[self.spinner stopAnimating];}
}
@end

@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) RestartView *controller;
@property(nonatomic) BOOL needsUserActivation;
@end
@implementation App
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.controller=[RestartView new];self.window.rootViewController=self.controller;self.needsUserActivation=YES;[self.window makeKeyAndVisible];return YES;
}
- (void)applicationWillEnterForeground:(UIApplication *)application {self.needsUserActivation=YES;}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    if(!self.needsUserActivation)return;self.needsUserActivation=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(application.applicationState==UIApplicationStateActive)[self.controller toggleAutomation];
    });
}
- (void)applicationDidEnterBackground:(UIApplication *)application {[self.controller enteredBackground];}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}
