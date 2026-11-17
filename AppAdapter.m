// AppAdapter — Hongguo Short Drama window attachment and player layout.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <stdatomic.h>

#ifndef APP_ADAPTER_IPAD_TEST
#define APP_ADAPTER_IPAD_TEST 0
#endif

#if APP_ADAPTER_IPAD_TEST
#define APP_ADAPTER_LABEL @"AppAdapter v36 Adaptive"
static atomic_bool gIPadHookInstalled;
static atomic_uint gIPadChecks;
static atomic_uint gPhoneChecks;
static NSString *gExpandedFeedViewportResult;
static NSString *gNativePlayerLayoutResult;
static NSString *gForegroundFeedLayoutResult;
static __weak UIWindowScene *gBackgroundFeedScene;
static __weak id gBackgroundFeedAdapter;
static __weak id gBackgroundEpisode;
static NSUInteger gForegroundFeedGeneration;
// -1 until the main thread has observed the display configuration.
static atomic_int gIPadMode = -1;
static atomic_bool gDisplayGeometrySettling;
static BOOL gNativeFoldPending;
static BOOL gNativeFoldNeedsRetry;
static BOOL gFullscreenCrossedDisplays;
static CGFloat gLastCoverFeedWidth;
static __weak UIWindowScene *gReconciledScene;
static CGRect gReconciledSceneBounds;
static BOOL gReconciledInnerMode;
static BOOL (*OriginalIPadDevice)(id, SEL);
static UIWindowScene *ForegroundScene(void);
static BOOL IsInnerScene(UIWindowScene *scene);

static void UpdateIPadMode(UIWindowScene *scene) {
    BOOL inner = scene ? IsInnerScene(scene) : UIScreen.screens.count > 1;
    atomic_store_explicit(&gIPadMode, inner, memory_order_relaxed);
}

static BOOL HookHongguoIPadDevice(id self, SEL selector) {
    int mode = atomic_load_explicit(&gIPadMode, memory_order_relaxed);
    if ((mode < 0 || atomic_load_explicit(&gDisplayGeometrySettling, memory_order_relaxed)) &&
        NSThread.isMainThread) {
        UpdateIPadMode(ForegroundScene());
        mode = atomic_load_explicit(&gIPadMode, memory_order_relaxed);
    }
    BOOL isIPad = mode < 0 ? OriginalIPadDevice(self, selector) : mode != 0;
    atomic_fetch_add_explicit(isIPad ? &gIPadChecks : &gPhoneChecks, 1, memory_order_relaxed);
    return isIPad;
}

static void InstallHongguoIPadTest(void) {
    if (atomic_load_explicit(&gIPadHookInstalled, memory_order_relaxed) ||
        !NSClassFromString(@"SSiPadAdapter") || !NSClassFromString(@"SSReadingAppDelegate")) return;
    SEL selector = NSSelectorFromString(@"btd_isPadDevice");
    Method method = class_getClassMethod(UIDevice.class, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return;
    char type[8];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, @encode(BOOL)) != 0) return;
    OriginalIPadDevice = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)HookHongguoIPadDevice);
    atomic_store_explicit(&gIPadHookInstalled, true, memory_order_relaxed);
}

static BOOL (*OriginalStatusBarHidden)(UIViewController *, SEL);
static UIViewController *(*OriginalStatusBarHiddenChild)(UIViewController *, SEL);
static char gStatusBarHideRequested;
static CGFloat (*OriginalTabButtonHeight)(id, SEL);
static unsigned gCompactTabHeightCalls;
static CGFloat (*OriginalSafeAreaTop)(id, SEL);
static unsigned gSafeAreaTopCalls;
static CGFloat gFirstSafeAreaTop;
static CGFloat gLastSafeAreaTop;
static CGFloat gMaxSafeAreaTop;
static CGFloat (*OriginalSafeAreaBottom)(id, SEL);
static unsigned gSafeAreaBottomCalls;
static CGFloat gOriginalSafeAreaBottom;
static CGFloat gAdjustedSafeAreaBottom;

static BOOL IsInnerScene(UIWindowScene *scene) {
    CGSize size = scene.coordinateSpace.bounds.size;
    for (UIScreen *screen in UIScreen.screens) {
        CGSize screenSize = screen.bounds.size;
        if (screenSize.width * screenSize.height < size.width * size.height * 0.8) return YES;
    }
    return NO;
}

static BOOL IsLandscapeInnerScene(UIWindowScene *scene) {
    CGSize size = scene.coordinateSpace.bounds.size;
    return size.width > size.height && IsInnerScene(scene);
}

static BOOL HideInnerStatusBar(UIViewController *controller) {
    UIWindow *window = controller.viewIfLoaded.window;
    return window && window.rootViewController == controller && IsLandscapeInnerScene(window.windowScene);
}

static CGFloat HookTabButtonHeight(id self, SEL selector) {
    CGFloat height = OriginalTabButtonHeight(self, selector);
    if (height == 54 && NSThread.isMainThread && IsLandscapeInnerScene(ForegroundScene())) {
        ++gCompactTabHeightCalls;
        return 48;
    }
    return height;
}

static Method CGFloatClassGetter(NSString *className, NSString *selectorName) {
    Class cls = NSClassFromString(className);
    Method method = cls ? class_getClassMethod(cls, NSSelectorFromString(selectorName)) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return NULL;
    char type[8];
    method_getReturnType(method, type, sizeof(type));
    return strcmp(type, @encode(CGFloat)) == 0 ? method : NULL;
}

static void InstallCompactTabBar(void) {
    if (OriginalTabButtonHeight) return;
    Method method = CGFloatClassGetter(@"SSTabBarControllerContext", @"tabBarButtonHeight");
    if (!method) return;
    OriginalTabButtonHeight = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)HookTabButtonHeight);
}

static BOOL IsLaunchingOnLandscapeInnerScreen(void) {
    UIWindowScene *scene = ForegroundScene();
    if (scene) return IsLandscapeInnerScene(scene);
    NSArray<UIScreen *> *screens = UIScreen.screens;
    if (screens.count < 2) return NO;
    CGSize largest = CGSizeZero;
    for (UIScreen *screen in screens) {
        CGSize size = screen.bounds.size;
        if (size.width * size.height > largest.width * largest.height) largest = size;
    }
    return largest.width > largest.height;
}

static CGFloat HookSafeAreaTop(id self, SEL selector) {
    CGFloat original = OriginalSafeAreaTop(self, selector);
    if (!NSThread.isMainThread || !IsLaunchingOnLandscapeInnerScreen()) return original;
    if (gSafeAreaTopCalls++ == 0) gFirstSafeAreaTop = original;
    gLastSafeAreaTop = original;
    gMaxSafeAreaTop = MAX(gMaxSafeAreaTop, original);
    // SSUIHelper substitutes 20pt even when the status bar is hidden and the inset is zero.
    return 0;
}

static CGFloat HookSafeAreaBottom(id self, SEL selector) {
    CGFloat original = OriginalSafeAreaBottom(self, selector);
    if (!NSThread.isMainThread || !IsLaunchingOnLandscapeInnerScreen()) return original;
    ++gSafeAreaBottomCalls;
    gOriginalSafeAreaBottom = original;
    gAdjustedSafeAreaBottom = MIN(original, 16);
    return gAdjustedSafeAreaBottom;
}

static void InstallSafeAreaHooks(void) {
    if (!OriginalSafeAreaTop) {
        Method top = CGFloatClassGetter(@"SSUIHelper", @"safeAreaTop");
        if (top) {
            OriginalSafeAreaTop = (void *)method_getImplementation(top);
            method_setImplementation(top, (IMP)HookSafeAreaTop);
        }
    }
    if (!OriginalSafeAreaBottom) {
        Method bottom = CGFloatClassGetter(@"SSUIHelper", @"safeAreaBottom");
        if (bottom) {
            OriginalSafeAreaBottom = (void *)method_getImplementation(bottom);
            method_setImplementation(bottom, (IMP)HookSafeAreaBottom);
        }
    }
}

static BOOL HookStatusBarHidden(UIViewController *controller, SEL selector) {
    return HideInnerStatusBar(controller) || OriginalStatusBarHidden(controller, selector);
}

static UIViewController *HookStatusBarHiddenChild(UIViewController *controller, SEL selector) {
    if (HideInnerStatusBar(controller)) return nil;
    return OriginalStatusBarHiddenChild(controller, selector);
}

static void InstallStatusBarPolicy(void) {
    Class root = NSClassFromString(@"SSRootViewController");
    if (!root || OriginalStatusBarHidden) return;
    SEL hidden = @selector(prefersStatusBarHidden);
    SEL child = @selector(childViewControllerForStatusBarHidden);
    Method hiddenMethod = class_getInstanceMethod(root, hidden);
    Method childMethod = class_getInstanceMethod(root, child);
    if (!hiddenMethod || !childMethod) return;
    OriginalStatusBarHidden = (void *)method_getImplementation(hiddenMethod);
    OriginalStatusBarHiddenChild = (void *)method_getImplementation(childMethod);
    if (!class_addMethod(root, hidden, (IMP)HookStatusBarHidden, method_getTypeEncoding(hiddenMethod))) {
        method_setImplementation(hiddenMethod, (IMP)HookStatusBarHidden);
    }
    if (!class_addMethod(root, child, (IMP)HookStatusBarHiddenChild, method_getTypeEncoding(childMethod))) {
        method_setImplementation(childMethod, (IMP)HookStatusBarHiddenChild);
    }
}

static void RefreshStatusBarPolicy(UIWindow *window) {
    UIViewController *root = window.rootViewController;
    if (![root isKindOfClass:NSClassFromString(@"SSRootViewController")] || !OriginalStatusBarHidden) return;
    BOOL desired = HideInnerStatusBar(root);
    NSNumber *previous = objc_getAssociatedObject(root, &gStatusBarHideRequested);
    if (!previous || previous.boolValue != desired) {
        objc_setAssociatedObject(root, &gStatusBarHideRequested, @(desired), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [root setNeedsStatusBarAppearanceUpdate];
    }
}

#else
#define APP_ADAPTER_LABEL @"AppAdapter v15"
static void InstallHongguoIPadTest(void) {}
#endif

static UIScreen *(*OriginalMainScreen)(id, SEL);
static void (*OriginalMakeKeyAndVisible)(UIWindow *, SEL);
static BOOL gResolvingScreen;
static BOOL gTopInsetCaptured;
static CGFloat gTopInset;
static NSUInteger gOrientationUpdate;
static void FitCurrentVideo(void);
#if APP_ADAPTER_IPAD_TEST
static void FitNewFoldedVideoSurface(CAMetalLayer *layer);
#else
static atomic_bool gFitPending;
#endif

@interface AppAdapterMetalStats : NSObject {
@public
    atomic_uint requests;
    atomic_uint returned;
    atomic_uint empty;
    atomic_uint sampled;
    atomic_uint presented;
}
@end
@implementation AppAdapterMetalStats
@end

static char gMetalStatsKey;
static id<CAMetalDrawable> (*OriginalNextDrawable)(CAMetalLayer *, SEL);

static id<CAMetalDrawable> HookNextDrawable(CAMetalLayer *layer, SEL selector) {
    AppAdapterMetalStats *stats = objc_getAssociatedObject(layer, &gMetalStatsKey);
    if (!stats) {
        // Only the first request for a layer needs to take the lock.
        @synchronized (layer) {
            stats = objc_getAssociatedObject(layer, &gMetalStatsKey);
            if (!stats) {
                stats = [AppAdapterMetalStats new];
                objc_setAssociatedObject(layer, &gMetalStatsKey, stats, OBJC_ASSOCIATION_RETAIN);
            }
        }
    }
    atomic_fetch_add_explicit(&stats->requests, 1, memory_order_relaxed);
    id<CAMetalDrawable> drawable = OriginalNextDrawable(layer, selector);
    if (!drawable) {
        atomic_fetch_add_explicit(&stats->empty, 1, memory_order_relaxed);
        return nil;
    }
    unsigned index = atomic_fetch_add_explicit(&stats->returned, 1, memory_order_relaxed);
#if APP_ADAPTER_IPAD_TEST
    if (index == 0 && atomic_load_explicit(&gIPadMode, memory_order_relaxed) == 0) {
        __weak CAMetalLayer *weakLayer = layer;
        dispatch_async(dispatch_get_main_queue(), ^{ FitNewFoldedVideoSurface(weakLayer); });
    }
    BOOL samplePresentation = index == 0 || index == 60 || index % 240 == 0;
#else
    if (index % 60 == 0 && !atomic_exchange_explicit(&gFitPending, true, memory_order_relaxed)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            atomic_store_explicit(&gFitPending, false, memory_order_relaxed);
            FitCurrentVideo();
        });
    }
    BOOL samplePresentation = index % 60 == 0;
#endif
    if (samplePresentation && [drawable respondsToSelector:@selector(addPresentedHandler:)]) {
        atomic_fetch_add_explicit(&stats->sampled, 1, memory_order_relaxed);
        [drawable addPresentedHandler:^(id<MTLDrawable> result) {
            if (result.presentedTime > 0) {
                atomic_fetch_add_explicit(&stats->presented, 1, memory_order_relaxed);
            }
        }];
    }
    return drawable;
}

static void InstallMetalProbe(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable));
        if (method) {
            OriginalNextDrawable = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)HookNextDrawable);
        }
    });
}

static void SampleWindow(void);
static NSMutableArray<NSString *> *gLog;

@interface AppAdapterHUD : UIWindow
@property (nonatomic) UIView *panel;
@property (nonatomic) UITextView *logView;
@property (nonatomic) UIButton *restoreChip;
- (void)refreshLog;
@end

@implementation AppAdapterHUD

- (BOOL)canBecomeKeyWindow { return NO; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL inPanel = self.panel && !self.panel.hidden &&
        [self.panel pointInside:[self convertPoint:point toView:self.panel] withEvent:event];
    BOOL inChip = self.restoreChip && !self.restoreChip.hidden &&
        [self.restoreChip pointInside:[self convertPoint:point toView:self.restoreChip] withEvent:event];
    if (!inPanel && !inChip) {
        return nil;
    }
    return [super hitTest:point withEvent:event];
}

- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (!self) return nil;
    self.windowLevel = UIWindowLevelAlert + 1;
    self.backgroundColor = UIColor.clearColor;
    self.rootViewController = [UIViewController new];
    UIView *root = self.rootViewController.view;
    root.backgroundColor = UIColor.clearColor;

    self.panel = [UIView new];
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.panel.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.96];
    self.panel.layer.cornerRadius = 12;
    self.panel.clipsToBounds = YES;
    [root addSubview:self.panel];

    UILabel *title = [UILabel new];
    title.text = APP_ADAPTER_LABEL;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.textColor = UIColor.whiteColor;

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    [refresh setTitle:@"刷新" forState:UIControlStateNormal];
    [refresh addTarget:self action:@selector(sample) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setTitle:@"复制日志" forState:UIControlStateNormal];
    [copy addTarget:self action:@selector(copyLog:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *hide = [UIButton buttonWithType:UIButtonTypeSystem];
    [hide setTitle:@"隐藏" forState:UIControlStateNormal];
    [hide addTarget:self action:@selector(hidePanel:) forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *button in @[refresh, copy, hide]) {
        button.tintColor = [UIColor colorWithRed:0.60 green:0.81 blue:1 alpha:1];
        [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [button setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                forAxis:UILayoutConstraintAxisHorizontal];
    }
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, refresh, copy, hide]];
    header.spacing = 8;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.panel addSubview:header];

    self.logView = [UITextView new];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.editable = NO;
    self.logView.selectable = NO;
    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.whiteColor;
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.panel addSubview:self.logView];

    UILayoutGuide *safe = root.safeAreaLayoutGuide;
    NSLayoutConstraint *fill = [self.panel.widthAnchor constraintEqualToAnchor:safe.widthAnchor constant:-24];
    fill.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        fill,
        [self.panel.widthAnchor constraintLessThanOrEqualToConstant:480],
        [self.panel.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-24],
        [self.panel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.panel.heightAnchor constraintEqualToConstant:184],
        [header.topAnchor constraintEqualToAnchor:self.panel.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:12],
        [header.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-12],
        [header.heightAnchor constraintEqualToConstant:44],
        [self.logView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:6],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-6],
    ]];

    self.restoreChip = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.restoreChip setTitle:@"…" forState:UIControlStateNormal];
    self.restoreChip.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.restoreChip.tintColor = UIColor.whiteColor;
    self.restoreChip.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.55];
    self.restoreChip.layer.cornerRadius = 14;
    self.restoreChip.translatesAutoresizingMaskIntoConstraints = NO;
    self.restoreChip.hidden = YES;
    [self.restoreChip addTarget:self action:@selector(showPanel:) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.restoreChip];
    [NSLayoutConstraint activateConstraints:@[
        [self.restoreChip.widthAnchor constraintEqualToConstant:28],
        [self.restoreChip.heightAnchor constraintEqualToConstant:28],
        [self.restoreChip.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-6],
        [self.restoreChip.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],
    ]];
    return self;
}

- (void)hidePanel:(UIButton *)button {
    self.panel.hidden = YES;
    self.restoreChip.hidden = NO;
}

- (void)showPanel:(UIButton *)button {
    self.panel.hidden = NO;
    self.restoreChip.hidden = YES;
    [self refreshLog];
}

- (void)sample {
    SampleWindow();
}

- (void)copyLog:(UIButton *)button {
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n%@", APP_ADAPTER_LABEL, self.logView.text ?: @""];
    [button setTitle:@"已复制" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [button setTitle:@"复制日志" forState:UIControlStateNormal];
    });
}

- (void)refreshLog {
    if (self.panel.hidden) return;
    self.logView.text = [gLog componentsJoinedByString:@"\n\n"];
    if (self.logView.text.length) {
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
    }
}

@end

static AppAdapterHUD *gHUD;

static id HongguoDelegate(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    Class delegateClass = NSClassFromString(@"SSReadingAppDelegate");
    return delegateClass && [delegate isKindOfClass:delegateClass] ? delegate : nil;
}

static BOOL IsHongguo(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.phoenix.video"] ||
           HongguoDelegate() != nil;
}

static UIWindow *MainWindow(id delegate) {
    if (!delegate) return nil;
    // Calling -window here would create and show the window during startup.
    Ivar ivar = class_getInstanceVariable(NSClassFromString(@"SSReadingAppDelegate"), "_window");
    id window = ivar ? object_getIvar(delegate, ivar) : nil;
    return [window isKindOfClass:UIWindow.class] ? window : nil;
}

static CGRect PlayerClip(UIView *view, UIWindow *window, CGRect viewport) {
    for (UIView *parent = view.superview; parent && parent != window; parent = parent.superview) {
        if (parent.hidden || parent.alpha < 0.01) return CGRectNull;
        if (parent.clipsToBounds || parent.layer.masksToBounds) {
            viewport = CGRectIntersection(viewport, [parent convertRect:parent.bounds toView:window]);
        }
    }
    return viewport;
}

@interface AppAdapterFrameFit : NSObject
@property (nonatomic) CGRect original;
@property (nonatomic) CGRect applied;
@end
@implementation AppAdapterFrameFit
@end

static char gFrameFitKey;
static void (*OriginalSeriesLayout)(UIView *, SEL);
static void (*OriginalPlayerCellLayout)(UIView *, SEL);
static void (*OriginalMetalViewSetFrame)(UIView *, SEL, CGRect);
#if APP_ADAPTER_IPAD_TEST
static void (*OriginalPlayerWrapperSetFrame)(UIView *, SEL, CGRect);
#endif

static CGRect AppFrame(UIView *view, AppAdapterFrameFit *fit) {
    return fit && CGRectEqualToRect(view.frame, fit.applied) ? fit.original : view.frame;
}

static void RecordFrameFit(UIView *view, CGRect original, CGRect adjusted) {
    AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
    if (!CGRectEqualToRect(original, adjusted)) {
        if (!fit) {
            fit = [AppAdapterFrameFit new];
            objc_setAssociatedObject(view, &gFrameFitKey, fit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        fit.original = original;
        fit.applied = adjusted;
    } else if (fit) {
        objc_setAssociatedObject(view, &gFrameFitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ApplyFrame(UIView *view, CGRect original, CGRect adjusted) {
    RecordFrameFit(view, original, adjusted);
    if (!CGRectEqualToRect(view.frame, adjusted)) view.frame = adjusted;
}

static CGRect BottomMenuFrame(UIView *view, UIWindow *window) {
    if (view.window != window) return CGRectNull;
    for (UIView *parent = view; parent && parent != window; parent = parent.superview) {
        if (parent.hidden || parent.alpha < 0.01) return CGRectNull;
    }
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGRect visible = CGRectIntersection(frame, PlayerClip(view, window, window.bounds));
    CGFloat gap = CGRectGetMaxY(window.bounds) - CGRectGetMaxY(visible);
    if (CGRectIsEmpty(visible) || visible.size.width < window.bounds.size.width * 0.5 ||
        visible.size.height > 140 || gap > window.safeAreaInsets.bottom + 16) return CGRectNull;
    return visible;
}

static UIView *FindBottomMenu(UIView *view, UIWindow *window, NSUInteger *budget) {
    if (*budget == 0 || view.hidden || view.alpha < 0.01) return nil;
    --*budget;
    if (([view isKindOfClass:UITabBar.class] || [NSStringFromClass(view.class) isEqualToString:@"SSTabBar"]) &&
        !CGRectIsNull(BottomMenuFrame(view, window))) return view;
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        if (*budget == 0) break;
        UIView *menu = FindBottomMenu(child, window, budget);
        if (menu) return menu;
    }
    return nil;
}

static CGRect BottomMenuInWindow(UIWindow *window) {
    static __weak UIView *cachedMenu;
    UIView *menu = cachedMenu;
    CGRect frame = menu ? BottomMenuFrame(menu, window) : CGRectNull;
    if (CGRectIsNull(frame)) {
        NSUInteger budget = 400;
        menu = FindBottomMenu(window, window, &budget);
        cachedMenu = menu;
        if (menu) frame = BottomMenuFrame(menu, window);
    }
    return frame;
}

static CGRect PlayerSafeViewport(UIWindow *window) {
    CGRect viewport = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
    CGRect menu = BottomMenuInWindow(window);
    if (!CGRectIsNull(menu)) {
        viewport.size.height = MAX(0, MIN(CGRectGetMaxY(viewport), CGRectGetMinY(menu)) - CGRectGetMinY(viewport));
    }
    return viewport;
}

static CGRect InnerLandscapeViewport(UIWindow *window) {
    if (!window || window.hidden || window.bounds.size.width <= window.bounds.size.height) return CGRectNull;
    return PlayerSafeViewport(window);
}

static CGRect ActivePlayerFitViewport(UIWindow *window) {
#if APP_ADAPTER_IPAD_TEST
    if (!window || window.hidden || !window.windowScene || UIScreen.screens.count != 1) return CGRectNull;
    return PlayerSafeViewport(window);
#else
    return InnerLandscapeViewport(window);
#endif
}

static CGRect VideoFitViewport(CGRect viewport) {
#if APP_ADAPTER_IPAD_TEST
    if (gNativeFoldPending) return CGRectNull;
#endif
    return viewport;
}

#if APP_ADAPTER_IPAD_TEST
static CGRect CenterFoldedPlayerFrame(UIView *view, UIWindow *window, CGRect viewport, CGRect original) {
    UIView *parent = view.superview;
    if (!parent || ![NSStringFromClass(parent.class) isEqualToString:@"FQVPlayer"] ||
        !CGAffineTransformIsIdentity(view.transform) || !CGAffineTransformIsIdentity(parent.transform)) return original;
    CGRect clip = PlayerClip(view, window, viewport);
    if (CGRectIsEmpty(clip) || CGRectIsEmpty(original)) return original;
    CGRect available = [window convertRect:clip toView:parent];
    CGPoint center = CGPointMake(CGRectGetMidX(original), CGRectGetMidY(original));
    if (original.size.width > available.size.width + 8 && CGRectContainsPoint(available, center)) {
        // Center the render container before fitting its Metal view to the available width.
        original.origin.y = CGRectGetMidY(available) - original.size.height / 2;
    }
    return original;
}

static void HookPlayerWrapperSetFrame(UIView *view, SEL selector, CGRect frame) {
    if (NSThread.isMainThread) {
        UIWindow *window = view.window;
        if (window && window == MainWindow(HongguoDelegate())) {
            AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
            if (!fit || !CGRectEqualToRect(frame, fit.applied)) {
                CGRect adjusted = CenterFoldedPlayerFrame(view, window, VideoFitViewport(ActivePlayerFitViewport(window)), frame);
                RecordFrameFit(view, frame, adjusted);
                frame = adjusted;
            }
        }
    }
    OriginalPlayerWrapperSetFrame(view, selector, frame);
}

static void InstallPlayerWrapperFrameHook(void) {
    if (OriginalPlayerWrapperSetFrame) return;
    Class cls = NSClassFromString(@"TTPlayerView");
    SEL selector = @selector(setFrame:);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return;
    OriginalPlayerWrapperSetFrame = (void *)method_getImplementation(method);
    if (!class_addMethod(cls, selector, (IMP)HookPlayerWrapperSetFrame, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)HookPlayerWrapperSetFrame);
    }
}
#endif

static void FitFeedCanvas(UIView *view, UIWindow *window) {
    UIView *parent = view.superview;
    if (!parent || !CGAffineTransformIsIdentity(view.transform)) return;
    AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
    CGRect original = AppFrame(view, fit);
    CGRect adjusted = original;
    CGRect viewport = ActivePlayerFitViewport(window);
    if (!CGRectIsEmpty(viewport)) {
        CGRect projected = [parent convertRect:original toView:window];
        CGRect content = window.bounds;
        content.size.height = CGRectGetMaxY(viewport) - CGRectGetMinY(content);
        CGRect page = [window convertRect:content toView:parent];
        if (projected.size.width >= window.bounds.size.width * 0.85 && !CGRectIsEmpty(page)) {
            // Keep the feed's paging geometry. Resize the canvas inside each page.
            if (original.size.height > page.size.height + 8) adjusted.size.height = page.size.height;
            if (APP_ADAPTER_IPAD_TEST && original.size.width > page.size.width + 8) {
                adjusted.size.width = page.size.width;
            }
        }
    }
    ApplyFrame(view, original, adjusted);
}

static CGRect FitVideoFrame(UIView *view, UIWindow *window, CGRect viewport, CGRect original) {
    if (!CGAffineTransformIsIdentity(view.transform) ||
        !CGAffineTransformIsIdentity(view.superview.transform)) return original;
    CGRect adjusted = original;
    CGRect clip = PlayerClip(view, window, viewport);
    if (!view.hidden && view.alpha >= 0.01 && !CGRectIsEmpty(clip) && !CGRectIsEmpty(original)) {
        CGRect available = [window convertRect:clip toView:view.superview];
        CGPoint center = CGPointMake(CGRectGetMidX(original), CGRectGetMidY(original));
        if (CGRectContainsPoint(available, center) && !CGRectContainsRect(CGRectInset(available, -8, -8), original)) {
            CGFloat scale = MIN(1, MIN(available.size.width / original.size.width,
                                       available.size.height / original.size.height));
            adjusted.size = CGSizeMake(original.size.width * scale, original.size.height * scale);
            adjusted.origin.x = MIN(MAX(center.x - adjusted.size.width / 2, CGRectGetMinX(available)),
                                    CGRectGetMaxX(available) - adjusted.size.width);
            adjusted.origin.y = MIN(MAX(center.y - adjusted.size.height / 2, CGRectGetMinY(available)),
                                    CGRectGetMaxY(available) - adjusted.size.height);
        }
    }
    return adjusted;
}

static void FitVideoSurface(UIView *view, UIWindow *window, CGRect viewport) {
    AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
    CGRect original = AppFrame(view, fit);
    ApplyFrame(view, original, FitVideoFrame(view, window, viewport, original));
}

#if APP_ADAPTER_IPAD_TEST
static void FitNewFoldedVideoSurface(CAMetalLayer *layer) {
    id owner = layer.delegate;
    if (![owner isKindOfClass:UIView.class]) return;
    UIView *view = owner;
    UIView *metal = view.superview;
    if (view.layer != layer || ![NSStringFromClass(metal.class) isEqualToString:@"TTMetalView"]) return;
    UIWindow *window = view.window;
    if (!window || window != MainWindow(HongguoDelegate())) return;
    CGRect viewport = VideoFitViewport(ActivePlayerFitViewport(window));
    if (CGRectIsEmpty(viewport)) return;
    UIView *wrapper = metal.superview;
    if ([NSStringFromClass(wrapper.class) isEqualToString:@"TTPlayerView"]) {
        AppAdapterFrameFit *fit = objc_getAssociatedObject(wrapper, &gFrameFitKey);
        CGRect original = AppFrame(wrapper, fit);
        ApplyFrame(wrapper, original, CenterFoldedPlayerFrame(wrapper, window, viewport, original));
    }
    FitVideoSurface(view, window, viewport);
}
#endif

static void HookMetalViewSetFrame(UIView *view, SEL selector, CGRect frame) {
    if (NSThread.isMainThread &&
        [NSStringFromClass(view.superview.class) isEqualToString:@"TTMetalView"]) {
        UIWindow *window = view.window;
        if (window && window == MainWindow(HongguoDelegate())) {
            AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
            if (!fit || !CGRectEqualToRect(frame, fit.applied)) {
                CGRect adjusted = FitVideoFrame(view, window, VideoFitViewport(ActivePlayerFitViewport(window)), frame);
                RecordFrameFit(view, frame, adjusted);
                frame = adjusted;
            }
        }
    }
    OriginalMetalViewSetFrame(view, selector, frame);
}

static void InstallMetalViewFrameHook(void) {
    if (OriginalMetalViewSetFrame) return;
    Class cls = NSClassFromString(@"MTKView");
    SEL selector = @selector(setFrame:);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return;
    OriginalMetalViewSetFrame = (void *)method_getImplementation(method);
    if (!class_addMethod(cls, selector, (IMP)HookMetalViewSetFrame, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)HookMetalViewSetFrame);
    }
}

static void FitSeriesButtons(UIView *container, UIWindow *window, CGRect viewport) {
    if (!CGAffineTransformIsIdentity(container.transform)) return;
    for (UIView *view in container.subviews) {
        if (![view isKindOfClass:UIButton.class] || !CGAffineTransformIsIdentity(view.transform)) continue;
        AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
        CGRect original = AppFrame(view, fit);
        CGRect adjusted = original;
        CGRect clip = PlayerClip(view, window, viewport);
        if (!container.hidden && !view.hidden && !CGRectIsEmpty(clip) && !CGRectIsEmpty(original)) {
            CGRect available = CGRectIntersection(container.bounds, [window convertRect:clip toView:container]);
            if (!CGRectIsEmpty(available) && original.size.height <= available.size.height &&
                CGRectGetMinX(original) >= CGRectGetMinX(available) &&
                CGRectGetMaxX(original) <= CGRectGetMaxX(available) &&
                CGRectGetMaxY(original) > CGRectGetMaxY(available)) {
                adjusted.origin.y = CGRectGetMaxY(available) - original.size.height;
            }
        }
        ApplyFrame(view, original, adjusted);
    }
}

static void HookSeriesLayout(UIView *container, SEL selector) {
    UIWindow *window = container.window;
    BOOL isMain = window && window == MainWindow(HongguoDelegate());
    if (isMain) FitFeedCanvas(container, window);
    OriginalSeriesLayout(container, selector);
    if (isMain) {
        FitSeriesButtons(container, window, ActivePlayerFitViewport(window));
    }
}

static void HookPlayerCellLayout(UIView *view, SEL selector) {
    UIWindow *window = view.window;
    if (window && window == MainWindow(HongguoDelegate())) FitFeedCanvas(view, window);
    OriginalPlayerCellLayout(view, selector);
}

static void InstallSeriesLayoutHook(void) {
    InstallMetalViewFrameHook();
#if APP_ADAPTER_IPAD_TEST
    InstallPlayerWrapperFrameHook();
#endif
    if (!OriginalPlayerCellLayout) {
        Class cell = NSClassFromString(@"FQVShortVideoPlayerCellView");
        Method layout = cell ? class_getInstanceMethod(cell, @selector(layoutSubviews)) : NULL;
        if (layout) {
            OriginalPlayerCellLayout = (void *)method_getImplementation(layout);
            if (!class_addMethod(cell, @selector(layoutSubviews), (IMP)HookPlayerCellLayout,
                                 method_getTypeEncoding(layout))) {
                method_setImplementation(layout, (IMP)HookPlayerCellLayout);
            }
        }
    }
    if (OriginalSeriesLayout) return;
    Class cls = NSClassFromString(@"FQVShortVideoVPlayerOutterMultiSeriesControlView");
    SEL selector = @selector(layoutSubviews);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return;
    OriginalSeriesLayout = (void *)method_getImplementation(method);
    if (!class_addMethod(cls, selector, (IMP)HookSeriesLayout, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)HookSeriesLayout);
    }
}

static void FitPlayerViews(UIView *view, UIWindow *window, CGRect viewport, NSUInteger *budget) {
    if (!view || *budget == 0 || view.hidden || view.alpha < 0.01) return;
    --*budget;
    NSString *name = NSStringFromClass(view.class);
#if APP_ADAPTER_IPAD_TEST
    if ([name isEqualToString:@"TTPlayerView"]) {
        AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
        CGRect original = AppFrame(view, fit);
        ApplyFrame(view, original, CenterFoldedPlayerFrame(view, window, VideoFitViewport(viewport), original));
    }
#endif
    if ([name isEqualToString:@"FQVShortVideoPlayerCellView"]) FitFeedCanvas(view, window);
    if ([name isEqualToString:@"FQVShortVideoVPlayerOutterMultiSeriesControlView"]) {
        FitFeedCanvas(view, window);
        FitSeriesButtons(view, window, viewport);
    }
    if ([view.layer isKindOfClass:CAMetalLayer.class] &&
        [NSStringFromClass(view.superview.class) isEqualToString:@"TTMetalView"]) {
        AppAdapterMetalStats *stats = objc_getAssociatedObject(view.layer, &gMetalStatsKey);
        if (stats && atomic_load_explicit(&stats->returned, memory_order_relaxed)) {
            FitVideoSurface(view, window, VideoFitViewport(viewport));
        }
    }
    for (UIView *child in view.subviews) {
        if (*budget == 0) break;
        FitPlayerViews(child, window, viewport, budget);
    }
}

static void FitCurrentVideo(void) {
    UIWindow *window = MainWindow(HongguoDelegate());
    CGRect viewport = ActivePlayerFitViewport(window);
#if APP_ADAPTER_IPAD_TEST
    static BOOL hadFoldedViewport;
    BOOL folded = !CGRectIsEmpty(viewport);
    if (!folded && !hadFoldedViewport) return;
    hadFoldedViewport = folded;
#endif
    NSUInteger budget = 1200;
    FitPlayerViews(window.rootViewController.viewIfLoaded, window, viewport, &budget);
}

static CGFloat Area(CGRect bounds) {
    if (CGRectIsEmpty(bounds) || CGRectIsInfinite(bounds)) return 0;
    return bounds.size.width * bounds.size.height;
}

static UIWindowScene *ForegroundScene(void) {
    UIWindowScene *best = nil;
    NSInteger bestRank = 0;
    CGFloat bestArea = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            ![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
        NSInteger rank;
        switch (scene.activationState) {
            case UISceneActivationStateForegroundActive: rank = 2; break;
            case UISceneActivationStateForegroundInactive: rank = 1; break;
            default: continue;
        }
        UIWindowScene *candidate = (UIWindowScene *)scene;
        CGFloat area = Area(candidate.coordinateSpace.bounds);
        if (area > 0 && (rank > bestRank || (rank == bestRank && area > bestArea))) {
            best = candidate;
            bestRank = rank;
            bestArea = area;
        }
    }
    return best;
}

static UIScreen *HookMainScreen(id self, SEL selector) {
    UIScreen *original = OriginalMainScreen(self, selector);
    if (!NSThread.isMainThread || gResolvingScreen) return original;

    gResolvingScreen = YES;
    UIScreen *screen = original;
    @try {
        if (IsHongguo()) {
            InstallHongguoIPadTest();
            InstallMetalProbe();
            InstallSeriesLayoutHook();
            screen = ForegroundScene().screen;
            if (!screen) {
                screen = original;
                for (UIScreen *candidate in UIScreen.screens) {
                    if (Area(candidate.bounds) > Area(screen.bounds)) screen = candidate;
                }
            }
        }
    } @finally {
        gResolvingScreen = NO;
    }
    return screen;
}

static void FitWindow(UIWindow *window, UIWindowScene *scene) {
    if (!scene) return;
    if (window.windowScene != scene) window.windowScene = scene;
    if (!APP_ADAPTER_IPAD_TEST && !gTopInsetCaptured && window.safeAreaInsets.top > 0) {
        gTopInset = window.safeAreaInsets.top;
        gTopInsetCaptured = YES;
    }
    CGRect bounds = scene.coordinateSpace.bounds;
    // The Duo inner screen reports an ~82pt top safe area (a normal iPhone is
    // ~47pt). The app's header sits below that inset, so the black header band
    // looks ~35pt taller than on the phone. Extend the window upward by the
    // excess: the app's header moves up, the bottom edge stays aligned.
    CGFloat excess = !APP_ADAPTER_IPAD_TEST && gTopInsetCaptured ? MAX(0, gTopInset - 47.0) : 0;
    if (excess > 0) {
        bounds.origin.y = -excess;
        bounds.size.height += excess;
    }
    BOOL resized = !CGRectEqualToRect(window.frame, bounds);
    if (resized) window.frame = bounds;
    UIView *root = window.rootViewController.viewIfLoaded;
    if (root && (resized || !CGSizeEqualToSize(root.bounds.size, window.bounds.size))) {
        [window setNeedsLayout];
        [root setNeedsLayout];
    }
}

static void AppendVideoHierarchy(NSMutableString *line, UIView *view, UIWindow *window) {
    CALayer *presented = view.layer.presentationLayer;
    CALayer *presentedWindow = window.layer.presentationLayer;
    if (presented && presentedWindow) {
        [line appendFormat:@"\npresentation in window=%@",
            NSStringFromCGRect([presented convertRect:presented.bounds toLayer:presentedWindow])];
    }
    for (NSUInteger depth = 0; view && view != window && depth < 12; ++depth, view = view.superview) {
        [line appendFormat:@"\n  [%lu] %@ window=%@ bounds=%@ clip=%d mask=%@ hidden=%d alpha=%.2f transform=%@",
            (unsigned long)depth, NSStringFromClass(view.class),
            NSStringFromCGRect([view convertRect:view.bounds toView:window]), NSStringFromCGRect(view.bounds),
            view.clipsToBounds || view.layer.masksToBounds,
            view.layer.mask ? NSStringFromClass(view.layer.mask.class) : @"none",
            view.hidden, view.alpha, NSStringFromCGAffineTransform(view.transform)];
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll = (UIScrollView *)view;
            [line appendFormat:@" offset=%@ content=%@ inset=%@ dragging=%d decelerating=%d",
                NSStringFromCGPoint(scroll.contentOffset), NSStringFromCGSize(scroll.contentSize),
                NSStringFromUIEdgeInsets(scroll.adjustedContentInset), scroll.dragging, scroll.decelerating];
        }
    }
}

static void AppendVideoLayers(CALayer *layer, UIWindow *window, NSMutableArray<NSString *> *output,
                              NSUInteger *budget, BOOL detailed) {
    if (!layer || *budget == 0 || output.count == 5) return;
    --*budget;
    NSString *name = NSStringFromClass(layer.class);
    BOOL metal = [layer isKindOfClass:CAMetalLayer.class];
    if ([name containsString:@"PlayerLayer"] || [name containsString:@"SampleBufferDisplayLayer"] ||
        metal || [layer isKindOfClass:NSClassFromString(@"CAEAGLLayer")]) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"%@ owner=%@ frame=%@ hidden=%d opacity=%.2f",
            name, layer.delegate ? NSStringFromClass([layer.delegate class]) : @"none",
            NSStringFromCGRect(layer.frame), layer.hidden, layer.opacity];
        if (metal) {
            CAMetalLayer *surface = (CAMetalLayer *)layer;
            if ([surface.delegate isKindOfClass:UIView.class]) {
                UIView *view = (UIView *)surface.delegate;
                CGRect rect = [view convertRect:view.bounds toView:window];
                CGRect clip = PlayerClip(view, window, window.bounds);
                [line appendFormat:@"\nin window=%@ clip=%@ visible=%@ parent=%@",
                    NSStringFromCGRect(rect), NSStringFromCGRect(clip),
                    NSStringFromCGRect(CGRectIntersection(rect, clip)),
                    NSStringFromClass(view.superview.class)];
                AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
                if (fit) [line appendFormat:@"\nvideo frame fit %@ → %@",
                    NSStringFromCGRect(fit.original), NSStringFromCGRect(fit.applied)];
                if (detailed) {
                    [line appendFormat:@"\nfit viewport=%@",
                        NSStringFromCGRect(PlayerClip(view, window, ActivePlayerFitViewport(window)))];
                    AppendVideoHierarchy(line, view, window);
                }
            }
            [line appendFormat:@"\ndrawable=%@ scale=%.2f device=%d",
                NSStringFromCGSize(surface.drawableSize), surface.contentsScale, surface.device != nil];
            AppAdapterMetalStats *stats = objc_getAssociatedObject(layer, &gMetalStatsKey);
            if (stats) {
                [line appendFormat:@" requests=%u returned=%u nil=%u presented=%u/%u sampled",
                    atomic_load_explicit(&stats->requests, memory_order_relaxed),
                    atomic_load_explicit(&stats->returned, memory_order_relaxed),
                    atomic_load_explicit(&stats->empty, memory_order_relaxed),
                    atomic_load_explicit(&stats->presented, memory_order_relaxed),
                    atomic_load_explicit(&stats->sampled, memory_order_relaxed)];
            } else {
                [line appendString:@" no drawable calls observed"];
            }
        }
        [output addObject:line];
    }
    for (CALayer *child in layer.sublayers) {
        if (*budget == 0 || output.count == 5) break;
        AppendVideoLayers(child, window, output, budget, detailed);
    }
}

static void FindOffscreenControls(UIView *view, UIWindow *window, CGRect viewport,
                                  NSMutableArray<NSString *> *output, NSUInteger *budget) {
    if (!view || *budget == 0 || output.count == 6 || view.hidden || view.alpha < 0.01) return;
    --*budget;
    CGRect rect = [view convertRect:view.bounds toView:window];
    CGRect screen = CGRectInset(window.bounds, -2, -2);
    BOOL interactive = [view isKindOfClass:UIControl.class] ||
        (view.gestureRecognizers.count > 0 && ![view isKindOfClass:UIScrollView.class]) ||
        (view.accessibilityTraits & UIAccessibilityTraitButton) != 0;
    BOOL seriesButton = [view isKindOfClass:UIButton.class] &&
        [NSStringFromClass(view.superview.class) isEqualToString:@"FQVShortVideoVPlayerOutterMultiSeriesControlView"];
    CGRect clip = PlayerClip(view, window, screen);
    AppAdapterFrameFit *fit = objc_getAssociatedObject(view, &gFrameFitKey);
    if (!CGRectIsEmpty(rect) && (fit || seriesButton ||
        (interactive && view.userInteractionEnabled && !CGRectContainsRect(clip, rect)))) {
        [output addObject:[NSString stringWithFormat:@"%@ in %@ window=%@ clip=%@ original=%@",
                           NSStringFromClass(view.class), NSStringFromClass(view.superview.class),
                           NSStringFromCGRect(rect), NSStringFromCGRect(clip),
                           fit ? NSStringFromCGRect(fit.original) : @"unchanged"]];
    }
    // Cells outside a scroll viewport are normal and should not dominate the sample.
    if ([view isKindOfClass:UIScrollView.class]) viewport = CGRectIntersection(viewport, rect);
    if (CGRectIsNull(viewport)) return;
    BOOL inScrollViewport = !CGRectEqualToRect(viewport, window.bounds);
    for (UIView *child in view.subviews) {
        if (*budget == 0 || output.count == 6) break;
        if (inScrollViewport && !CGRectIntersectsRect(viewport, [child convertRect:child.bounds toView:window])) continue;
        FindOffscreenControls(child, window, viewport, output, budget);
    }
}

#if APP_ADAPTER_IPAD_TEST
static UIView *VisiblePlayerCell(UIWindow *window, BOOL requirePlayer);
#endif

static void LogWindow(UIWindow *window, UIWindowScene *target, NSString *reason) {
    NSMutableString *entry = [NSMutableString stringWithFormat:@"%@\nscreens=%lu scenes=%lu",
        reason, (unsigned long)UIScreen.screens.count,
        (unsigned long)UIApplication.sharedApplication.connectedScenes.count];
    for (UIScreen *screen in UIScreen.screens) {
        [entry appendFormat:@" %.0f×%.0f@%.1f", screen.bounds.size.width, screen.bounds.size.height, screen.scale];
    }
    [entry appendFormat:@"\ntarget=%@ state=%ld",
        target ? NSStringFromCGRect(target.coordinateSpace.bounds) : @"none",
        (long)(target ? target.activationState : UISceneActivationStateUnattached)];
#if APP_ADAPTER_IPAD_TEST
    int mode = atomic_load_explicit(&gIPadMode, memory_order_relaxed);
    [entry appendFormat:@"\ndevice predicate hook=%d mode=%@ iPad calls=%u iPhone calls=%u device idiom=%ld window idiom=%ld",
        atomic_load_explicit(&gIPadHookInstalled, memory_order_relaxed),
        mode < 0 ? @"unknown" : (mode ? @"iPad" : @"iPhone"),
        atomic_load_explicit(&gIPadChecks, memory_order_relaxed),
        atomic_load_explicit(&gPhoneChecks, memory_order_relaxed),
        (long)UIDevice.currentDevice.userInterfaceIdiom,
        (long)(window ? window.traitCollection.userInterfaceIdiom : UIUserInterfaceIdiomUnspecified)];
#endif
    if (window) {
        UIViewController *root = window.rootViewController;
        UIView *rootView = root.viewIfLoaded;
        [entry appendFormat:@"\nwindow=%@ attached=%d sameScene=%d key=%d hidden=%d frame=%@\nroot=%@ view=%@",
            NSStringFromClass(window.class), window.windowScene != nil, target && window.windowScene == target,
            window.isKeyWindow, window.hidden, NSStringFromCGRect(window.frame),
            root ? NSStringFromClass(root.class) : @"none",
            rootView ? NSStringFromCGRect(rootView.frame) : @"not loaded"];
#if APP_ADAPTER_IPAD_TEST
        UIStatusBarManager *status = target.statusBarManager;
        CGRect menu = BottomMenuInWindow(window);
        [entry appendFormat:@"\nstatus hide requested=%d system hidden=%@ frame=%@"
            @"\nwindow safe=%@ root safe=%@ root extra=%@ bottom menu=%@ compact tab calls=%u",
            OriginalStatusBarHidden && HideInnerStatusBar(root),
            status ? (status.statusBarHidden ? @"yes" : @"no") : @"unknown",
            NSStringFromCGRect(status.statusBarFrame),
            NSStringFromUIEdgeInsets(window.safeAreaInsets),
            NSStringFromUIEdgeInsets(rootView.safeAreaInsets),
            NSStringFromUIEdgeInsets(root.additionalSafeAreaInsets),
            CGRectIsNull(menu) ? @"none observed" : NSStringFromCGRect(menu), gCompactTabHeightCalls];
        [entry appendFormat:@"\napp top inset hook=%d calls=%u original first=%.1f last=%.1f max=%.1f",
            OriginalSafeAreaTop != NULL, gSafeAreaTopCalls, gFirstSafeAreaTop, gLastSafeAreaTop, gMaxSafeAreaTop];
        [entry appendFormat:@"\napp bottom inset hook=%d calls=%u original=%.1f adjusted=%.1f",
            OriginalSafeAreaBottom != NULL, gSafeAreaBottomCalls, gOriginalSafeAreaBottom, gAdjustedSafeAreaBottom];
        if (gNativePlayerLayoutResult) {
            [entry appendFormat:@"\nnative player route: %@", gNativePlayerLayoutResult];
        }
        if (gExpandedFeedViewportResult) {
            [entry appendFormat:@"\nexpanded feed viewport: %@", gExpandedFeedViewportResult];
        }
        if (gForegroundFeedLayoutResult) {
            [entry appendFormat:@"\nforeground feed: %@", gForegroundFeedLayoutResult];
        }
#endif
        [entry appendFormat:@"\ntopInset=%.0f captured=%d excess=%.0f",
            gTopInset, gTopInsetCaptured ? 1 : 0, gTopInsetCaptured ? MAX(0, gTopInset - 47.0) : 0];
        NSMutableArray<NSString *> *layers = [NSMutableArray array];
        NSUInteger budget = 400;
        BOOL detailed = [reason isEqualToString:@"manual snapshot"];
        AppendVideoLayers(window.layer, window, layers, &budget, detailed);
        [entry appendFormat:@"\nvideo layers: %@", layers.count ? [layers componentsJoinedByString:@"\n"] : @"none observed"];
        if (detailed) {
#if APP_ADAPTER_IPAD_TEST
            if (!layers.count) {
                UIView *cell = VisiblePlayerCell(window, NO);
                if (cell) {
                    [entry appendString:@"\nfeed hierarchy without video:"];
                    AppendVideoHierarchy(entry, cell, window);
                }
            }
#endif
            NSMutableArray<NSString *> *controls = [NSMutableArray array];
            budget = 1000;
            FindOffscreenControls(rootView, window, window.bounds, controls, &budget);
            [entry appendFormat:@"\nsafe area=%@\nbottom menu=%@\ncontent viewport=%@\nplayer fit viewport=%@\nclipped controls and series buttons: %@",
                NSStringFromUIEdgeInsets(window.safeAreaInsets),
                NSStringFromCGRect(BottomMenuInWindow(window)),
                NSStringFromCGRect(InnerLandscapeViewport(window)),
                NSStringFromCGRect(ActivePlayerFitViewport(window)),
                controls.count ? [controls componentsJoinedByString:@"\n"] : @"none observed"];
        }
    } else {
        [entry appendString:@"\nmain window not created"];
    }
    NSLog(@"[%@] %@", APP_ADAPTER_LABEL, entry);
    if (!gLog) gLog = [NSMutableArray array];
    if (gLog.count == 24) [gLog removeObjectAtIndex:0];
    [gLog addObject:entry];
}

static void UpdateHUD(UIWindowScene *scene) {
    if (!scene) {
        gHUD.hidden = YES;
        return;
    }
    if (!gHUD) gHUD = [[AppAdapterHUD alloc] initWithWindowScene:scene];
    if (gHUD.windowScene != scene) gHUD.windowScene = scene;
    gHUD.frame = scene.coordinateSpace.bounds;
    gHUD.hidden = NO;
    [gHUD refreshLog];
}

static void SampleWindow(void) {
    LogWindow(MainWindow(HongguoDelegate()), ForegroundScene(), @"manual snapshot");
    [gHUD refreshLog];
}

#if APP_ADAPTER_IPAD_TEST
static IMP VerifiedNoArgMethod(id target, SEL selector, const char *expectedType) {
    Method method = target ? class_getInstanceMethod(object_getClass(target), selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return NULL;
    char type[8];
    method_getReturnType(method, type, sizeof(type));
    return strcmp(type, expectedType) == 0 ? method_getImplementation(method) : NULL;
}

static id ReadLayoutObject(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    id (*read)(id, SEL) = (void *)VerifiedNoArgMethod(target, selector, @encode(id));
    return read ? read(target, selector) : nil;
}

static void FindVisiblePlayerCell(UIView *view, UIWindow *window, NSUInteger *budget,
                                  UIView * __strong *best, CGFloat *bestArea, BOOL requirePlayer) {
    if (!view || *budget == 0 || view.hidden || view.alpha < 0.01) return;
    --*budget;
    NSString *name = NSStringFromClass(view.class);
    if ([name isEqualToString:@"FQVShortVideoPlayerCellView"] ||
        [name isEqualToString:@"FQVShortVideoLandscapePlayerCellView"]) {
        CGRect rect = [view convertRect:view.bounds toView:window];
        CGRect visible = CGRectIntersection(rect, PlayerClip(view, window, window.bounds));
        CGFloat area = Area(visible);
        if (area > *bestArea && (!requirePlayer || ReadLayoutObject(view, @"vPlayer"))) {
            *bestArea = area;
            *best = view;
        }
        return;
    }
    for (UIView *child in view.subviews) {
        if (*budget == 0) break;
        FindVisiblePlayerCell(child, window, budget, best, bestArea, requirePlayer);
    }
}

static UIView *VisiblePlayerCellInView(UIView *root, UIWindow *window, BOOL requirePlayer) {
    UIView *cell = nil;
    NSUInteger budget = 1200;
    CGFloat area = Area(window.bounds) * (requirePlayer ? 0.35 : 0.05);
    FindVisiblePlayerCell(root, window, &budget, &cell, &area, requirePlayer);
    return cell;
}

static UIView *VisiblePlayerCell(UIWindow *window, BOOL requirePlayer) {
    return VisiblePlayerCellInView(window.rootViewController.viewIfLoaded, window, requirePlayer);
}

static BOOL IsNativeFullscreenController(UIViewController *controller) {
    return [controller isKindOfClass:NSClassFromString(@"FQVRotateFullScreenViewController")] ||
           [controller isKindOfClass:NSClassFromString(@"FQVRotateViewController")] ||
           [controller isKindOfClass:NSClassFromString(@"FQVShortVideoLandscapeViewController")];
}

static UIViewController *FindFullscreenViewOwner(UIView *view, UIWindow *window, NSUInteger *budget) {
    if (!view || *budget == 0 || view.hidden || view.alpha < 0.01) return nil;
    --*budget;
    UIResponder *responder = view.nextResponder;
    if ([responder isKindOfClass:UIViewController.class]) {
        UIViewController *controller = (UIViewController *)responder;
        if (controller.viewIfLoaded == view && !controller.isBeingDismissed &&
            IsNativeFullscreenController(controller) && view.window == window &&
            CGRectIntersectsRect([view convertRect:view.bounds toView:window], window.bounds)) return controller;
    }
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        if (*budget == 0) break;
        UIViewController *controller = FindFullscreenViewOwner(child, window, budget);
        if (controller) return controller;
    }
    return nil;
}

static UIViewController *VisibleFullscreenController(UIWindow *window) {
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    if (IsNativeFullscreenController(controller) && controller.viewIfLoaded.window == window) return controller;
    NSUInteger budget = 500;
    return FindFullscreenViewOwner(window, window, &budget);
}

static __weak UIView *gExpandedFeedViewport;

static void RestoreExpandedFeedViewport(void) {
    UIView *view = gExpandedFeedViewport;
    if (!view) return;
    CGRect original = AppFrame(view, objc_getAssociatedObject(view, &gFrameFitKey));
    ApplyFrame(view, original, original);
    gExpandedFeedViewport = nil;
}

static void FitExpandedFeedViewport(UIWindow *window, CGFloat previousScreenWidth) {
    UIView *cell = VisiblePlayerCell(window, NO);
    id context = ReadLayoutObject(cell, @"listVCContext");
    id list = ReadLayoutObject(context, @"listVCView");
    CGRect bounds = window.bounds;
    gExpandedFeedViewportResult = cell ? @"no matching narrow feed ancestor" : @"no visible feed cell";
    for (UIView *view = cell.superview; view && view != window; view = view.superview) {
        UIView *parent = view.superview;
        BOOL collection = [NSStringFromClass(view.class) isEqualToString:@"FQVCollectionView"] &&
            [view isKindOfClass:UICollectionView.class];
        if ((!collection && view != list) || !parent || !view.clipsToBounds ||
            !CGAffineTransformIsIdentity(view.transform) || !CGAffineTransformIsIdentity(parent.transform) ||
            fabs(view.bounds.origin.x) > 2) continue;
        CGRect projected = [view convertRect:view.bounds toView:window];
        CGRect parentFrame = [parent convertRect:parent.bounds toView:window];
        BOOL matchesPreviousScreen = previousScreenWidth > 0 &&
            fabs(projected.size.width - previousScreenWidth) <= 4;
        if (fabs(CGRectGetMinX(projected) - CGRectGetMinX(bounds)) > 4 ||
            (!matchesPreviousScreen && projected.size.width < bounds.size.width * 0.55) ||
            projected.size.width >= bounds.size.width - 8 ||
            projected.size.height < bounds.size.height * 0.5 ||
            CGRectGetMinX(parentFrame) > CGRectGetMinX(bounds) + 4 ||
            CGRectGetMaxX(parentFrame) < CGRectGetMaxX(bounds) - 4) continue;
        CGRect original = view.frame;
        CGRect adjusted = original;
        adjusted.size.width = [window convertRect:bounds toView:parent].size.width;
        ApplyFrame(view, original, adjusted);
        gExpandedFeedViewport = view;
        if (collection) [[(UICollectionView *)view collectionViewLayout] invalidateLayout];
        [view setNeedsLayout];
        [view layoutIfNeeded];
        gExpandedFeedViewportResult = [NSString stringWithFormat:@"%@ %.0f → %.0f (after layout %.0f)",
            NSStringFromClass(view.class), original.size.width, adjusted.size.width, view.frame.size.width];
        return;
    }
}

static IMP VerifiedOneArgMethod(id target, SEL selector, const char *result, const char *argument) {
    Method method = target ? class_getInstanceMethod(object_getClass(target), selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3) return NULL;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(signature.methodReturnType, result) != 0 ||
        strcmp([signature getArgumentTypeAtIndex:2], argument) != 0) return NULL;
    return method_getImplementation(method);
}

static BOOL AdjustNativeVideoSize(id ui, SEL getter, SEL setter, CGSize viewport, CGFloat previousWidth) {
    Method method = class_getInstanceMethod(object_getClass(ui), getter);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(signature.methodReturnType, @encode(CGSize)) != 0) return NO;
    CGSize (*read)(id, SEL) = (void *)method_getImplementation(method);
    void (*write)(id, SEL, CGSize) = (void *)VerifiedOneArgMethod(ui, setter, @encode(void), @encode(CGSize));
    if (!write) return NO;
    CGSize original = read(ui, getter);
    if (original.width <= 0 || original.height <= 0) return NO;
    CGSize adjusted = original;
    if (previousWidth > 0) {
        if (fabs(original.width - previousWidth) > 4 || viewport.width <= original.width + 8) return NO;
        adjusted.width = viewport.width;
    } else {
        adjusted.width = MIN(original.width, viewport.width);
        adjusted.height = MIN(original.height, viewport.height);
    }
    if (CGSizeEqualToSize(original, adjusted)) return NO;
    write(ui, setter, adjusted);
    return YES;
}

static BOOL RefreshNativeLandscapeCell(UIView *cell, id context) {
    id component = ReadLayoutObject(context, @"playerComponent");
    id model = ReadLayoutObject(cell, @"model");
    if (!model || ![component isKindOfClass:NSClassFromString(@"FQVShortVideoListVCPlayerComponent")]) return NO;
    SEL calculate = NSSelectorFromString(@"videoPlayerViewFrameWithModel:");
    SEL refresh = NSSelectorFromString(@"refreshUIWithPlayerViewFrame:");
    CGRect (*frameForModel)(id, SEL, id) = (void *)VerifiedOneArgMethod(component, calculate, @encode(CGRect), @encode(id));
    void (*refreshFrame)(id, SEL, CGRect) = (void *)VerifiedOneArgMethod(cell, refresh, @encode(void), @encode(CGRect));
    if (!frameForModel || !refreshFrame) return NO;
    CGRect frame = frameForModel(component, calculate, model);
    if (CGRectIsEmpty(frame) || CGRectIsInfinite(frame)) return NO;
    refreshFrame(cell, refresh, frame);
    return YES;
}

static UIView *NativeRenderView(UIView *cell, UIWindow *window) {
    id player = ReadLayoutObject(cell, @"vPlayer");
    id renderView = ReadLayoutObject(ReadLayoutObject(player, @"videoEngine"), @"playerView");
    if (![renderView isKindOfClass:NSClassFromString(@"TTPlayerView")] ||
        ((UIView *)renderView).window != window) return nil;
    return renderView;
}

static BOOL CallNativeLayoutMethod(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    void (*update)(id, SEL) = (void *)VerifiedNoArgMethod(target, selector, @encode(void));
    if (!update) return NO;
    update(target, selector);
    return YES;
}

static BOOL RefreshNativeVideoSurface(UIView *cell, UIWindow *window) {
    return CallNativeLayoutMethod(NativeRenderView(cell, window), @"updateVideoFrame");
}

static UIView *FindFullscreenRenderer(UIView *view, NSUInteger *budget) {
    if (!view || *budget == 0 || view.hidden || view.alpha < 0.01) return nil;
    --*budget;
    if ([view isKindOfClass:NSClassFromString(@"TTPlayerView")]) return view;
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        if (*budget == 0) break;
        UIView *render = FindFullscreenRenderer(child, budget);
        if (render) return render;
    }
    return nil;
}

static BOOL FitsWindowHorizontally(UIView *view, UIWindow *window) {
    CGRect rect = [view convertRect:view.bounds toView:window];
    return CGRectGetMinX(rect) <= CGRectGetMinX(window.bounds) + 4 &&
           CGRectGetMaxX(rect) >= CGRectGetMaxX(window.bounds) - 4;
}

static CGSize PrepareFullscreenLayout(UIViewController *controller, UIWindow *window) {
    UIView *surface = controller.viewIfLoaded;
    UIView *container = controller.presentationController.containerView ?: surface.superview;
    CGSize oldSize = surface.bounds.size;
    [container setNeedsLayout];
    [container layoutIfNeeded];
    UIView *parent = surface.superview;
    if (parent && IsInnerScene(window.windowScene) && FitsWindowHorizontally(parent, window) &&
        CGAffineTransformIsIdentity(surface.transform) && CGAffineTransformIsIdentity(parent.transform)) {
        CGRect target = [window convertRect:window.bounds toView:parent];
        if (surface.bounds.size.width < window.bounds.size.width - 8 &&
            CGRectContainsRect(CGRectInset(parent.bounds, -4, -4), target)) surface.frame = target;
    }
    [surface setNeedsLayout];
    [surface layoutIfNeeded];
    return oldSize;
}

static BOOL RefreshFullscreenRenderer(UIViewController *controller, CGSize oldSize) {
    UIView *surface = controller.viewIfLoaded;
    NSUInteger budget = 500;
    UIView *renderer = FindFullscreenRenderer(surface, &budget);
    UIView *player = renderer.superview;
    while (player && player != surface &&
           ![player isKindOfClass:NSClassFromString(@"FQVPlayer")]) player = player.superview;
    if (player && player != surface &&
        fabs(player.bounds.size.width - oldSize.width) <= 4 &&
        fabs(player.bounds.size.height - oldSize.height) <= 4 &&
        !CGSizeEqualToSize(oldSize, surface.bounds.size) &&
        CGAffineTransformIsIdentity(player.transform) && player.superview == surface) {
        player.frame = surface.bounds;
    }
    if (player && player != surface) CallNativeLayoutMethod(player, @"updatePlayerLayout");
    BOOL refreshed = CallNativeLayoutMethod(renderer, @"updateVideoFrame");
    gNativePlayerLayoutResult = [NSString stringWithFormat:@"%@ fullscreen %@ → %@ renderer refreshed=%d",
        NSStringFromClass(controller.class), NSStringFromCGSize(oldSize),
        NSStringFromCGSize(surface.bounds.size), refreshed];
    return refreshed;
}

static BOOL RunNativePlayerRelayout(UIWindow *window, CGFloat previousWidth) {
    UIViewController *fullscreen = VisibleFullscreenController(window);
    CGSize oldFullscreenSize = fullscreen ? PrepareFullscreenLayout(fullscreen, window) : CGSizeZero;
    UIView *cell = fullscreen ? VisiblePlayerCellInView(fullscreen.viewIfLoaded, window, YES) :
                                VisiblePlayerCell(window, YES);
    if (fullscreen && !cell) return RefreshFullscreenRenderer(fullscreen, oldFullscreenSize);
    gNativePlayerLayoutResult = cell ? NSStringFromClass(cell.class) : @"no visible player cell";
    id context = ReadLayoutObject(cell, @"listVCContext");
    id ui = ReadLayoutObject(context, @"uiComponent");
    if (![ui isKindOfClass:NSClassFromString(@"FQVShortVideoListVCUIComponent")]) return NO;
    SEL insets = NSSelectorFromString(@"setupSafeInsets");
    SEL sizes = NSSelectorFromString(@"setupVideoSizes");
    SEL resize = NSSelectorFromString(@"refreshCellViewLayoutForResizing");
    void (*setupInsets)(id, SEL) = (void *)VerifiedNoArgMethod(ui, insets, @encode(void));
    void (*setupSizes)(id, SEL) = (void *)VerifiedNoArgMethod(ui, sizes, @encode(void));
    void (*refresh)(id, SEL) = (void *)VerifiedNoArgMethod(cell, resize, @encode(void));
    BOOL landscape = [NSStringFromClass(cell.class) isEqualToString:@"FQVShortVideoLandscapePlayerCellView"];
    if (!setupInsets || !setupSizes || (!landscape && !refresh)) return NO;
    setupInsets(ui, insets);
    setupSizes(ui, sizes);
    BOOL adjusted = NO;
    if (previousWidth > 0) {
        CGSize viewport = window.bounds.size;
        adjusted = AdjustNativeVideoSize(ui, NSSelectorFromString(@"portraitVideoSize"),
                                         NSSelectorFromString(@"setPortraitVideoSize:"), viewport, previousWidth);
        adjusted |= AdjustNativeVideoSize(ui, NSSelectorFromString(@"landscapeVideoSize"),
                                          NSSelectorFromString(@"setLandscapeVideoSize:"), viewport, previousWidth);
    } else if (!CGRectIsEmpty(ActivePlayerFitViewport(window))) {
        CGSize limit = window.bounds.size;
        if (landscape) {
            adjusted = AdjustNativeVideoSize(ui, NSSelectorFromString(@"landscapeVideoSize"),
                                             NSSelectorFromString(@"setLandscapeVideoSize:"), limit, 0);
        } else {
            adjusted = AdjustNativeVideoSize(ui, NSSelectorFromString(@"portraitVideoSize"),
                                             NSSelectorFromString(@"setPortraitVideoSize:"), limit, 0);
        }
    }
    BOOL relaid = YES;
    if (landscape) relaid = RefreshNativeLandscapeCell(cell, context);
    else refresh(cell, resize);
    BOOL rendererRefreshed = relaid && RefreshNativeVideoSurface(cell, window);
    gNativePlayerLayoutResult = [NSString stringWithFormat:@"%@ cached size adjusted=%d cell refreshed=%d renderer refreshed=%d",
        NSStringFromClass(cell.class), adjusted, relaid, rendererRefreshed];
    return relaid;
}

static BOOL FeedSizesMatch(CGSize size, CGSize reference) {
    return fabs(size.width - reference.width) <= 4 && fabs(size.height - reference.height) <= 4;
}

static BOOL FeedSizeIsTransposed(CGSize size, CGSize viewport) {
    return viewport.width > viewport.height + 32 &&
           FeedSizesMatch(size, CGSizeMake(viewport.height, viewport.width));
}

static UIView *ForegroundFeedCell(UIWindow *window) {
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController.viewIfLoaded.window == window &&
           !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    return VisiblePlayerCellInView(controller.viewIfLoaded, window, NO);
}

static id FeedScrollComponent(UIView *cell) {
    return ReadLayoutObject(ReadLayoutObject(cell, @"listVCContext"), @"scrollComponent");
}

static void SaveBackgroundEpisode(UIWindow *window) {
    id scroll = IsLandscapeInnerScene(window.windowScene) ? FeedScrollComponent(ForegroundFeedCell(window)) : nil;
    gBackgroundFeedAdapter = ReadLayoutObject(scroll, @"listAdapter");
    gBackgroundEpisode = ReadLayoutObject(scroll, @"currentCenterModel");
}

static BOOL IsShortVideoSection(id adapter, NSInteger section) {
    SEL selector = NSSelectorFromString(@"sectionControllerForSection:");
    id (*read)(id, SEL, NSInteger) =
        (void *)VerifiedOneArgMethod(adapter, selector, @encode(id), @encode(NSInteger));
    return read && [read(adapter, selector, section)
        isKindOfClass:NSClassFromString(@"FQVShortVideoSectionController")];
}

static NSIndexPath *FeedIndexForEpisode(id adapter, id episode, UICollectionView *collection) {
    SEL selector = NSSelectorFromString(@"sectionForObject:");
    NSInteger (*sectionForObject)(id, SEL, id) =
        (void *)VerifiedOneArgMethod(adapter, selector, @encode(NSInteger), @encode(id));
    if (!episode || !sectionForObject) return nil;
    NSInteger section = sectionForObject(adapter, selector, episode);
    if (section < 0 || section >= collection.numberOfSections ||
        [collection numberOfItemsInSection:section] != 1 || !IsShortVideoSection(adapter, section)) return nil;
    return [NSIndexPath indexPathForItem:0 inSection:section];
}

static BOOL InvalidateFeedMetrics(UICollectionView *collection) {
    UICollectionViewLayout *layout = collection.collectionViewLayout;
    UICollectionViewLayoutInvalidationContext *context = [[layout.class invalidationContextClass] new];
    SEL selector = NSSelectorFromString(@"setIg_invalidateAllAttributes:");
    void (*invalidateAll)(id, SEL, BOOL) =
        (void *)VerifiedOneArgMethod(context, selector, @encode(void), @encode(BOOL));
    BOOL isIGList = [layout isKindOfClass:NSClassFromString(@"IGListCollectionViewLayout")] && invalidateAll;
    if (isIGList) {
        // IGList uses its own cache flag when the collection changes size.
        invalidateAll(context, selector, YES);
        [layout invalidateLayoutWithContext:context];
    } else if ([context isKindOfClass:UICollectionViewFlowLayoutInvalidationContext.class]) {
        UICollectionViewFlowLayoutInvalidationContext *flow = (UICollectionViewFlowLayoutInvalidationContext *)context;
        flow.invalidateFlowLayoutDelegateMetrics = YES;
        flow.invalidateFlowLayoutAttributes = YES;
        [layout invalidateLayoutWithContext:flow];
    } else {
        [layout invalidateLayout];
    }
    [collection setNeedsLayout];
    [collection layoutIfNeeded];
    return isIGList;
}

static id gFeedSizingAdapter;
static CGSize gFeedSizingViewport;
static CGSize (*OriginalFeedItemSize)(id, SEL, NSIndexPath *);

static CGSize HookFeedItemSize(id adapter, SEL selector, NSIndexPath *index) {
    CGSize size = OriginalFeedItemSize(adapter, selector, index);
    if (!NSThread.isMainThread || adapter != gFeedSizingAdapter ||
        index.item != 0 || !FeedSizeIsTransposed(size, gFeedSizingViewport)) return size;
    return IsShortVideoSection(adapter, index.section) ? gFeedSizingViewport : size;
}

static BOOL InstallFeedItemSizeHook(void) {
    if (OriginalFeedItemSize) return YES;
    Class cls = NSClassFromString(@"IGListAdapter");
    SEL selector = NSSelectorFromString(@"sizeForItemAtIndexPath:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(signature.methodReturnType, @encode(CGSize)) != 0 ||
        strcmp([signature getArgumentTypeAtIndex:2], @encode(id)) != 0) return NO;
    OriginalFeedItemSize = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)HookFeedItemSize);
    return YES;
}

// Returns YES if the foreground pass should check again after the scene settles.
static BOOL RefreshForegroundFeed(UIWindow *window) {
    UIView *cell = ForegroundFeedCell(window);
    if (!cell) return YES;
    if (![cell isKindOfClass:NSClassFromString(@"FQVShortVideoPlayerCellView")]) return NO;

    UICollectionViewCell *page = nil;
    UICollectionView *collection = nil;
    for (UIView *view = cell.superview; view && view != window; view = view.superview) {
        if ([view isKindOfClass:NSClassFromString(@"FQVShortVideoCell")]) page = (UICollectionViewCell *)view;
        if ([view isKindOfClass:UICollectionView.class]) {
            collection = (UICollectionView *)view;
            break;
        }
    }
    if (!page || ![collection isKindOfClass:NSClassFromString(@"FQVCollectionView")] ||
        !FitsWindowHorizontally(collection, window)) return NO;
    CGSize viewport = collection.bounds.size;
    CGSize before = page.bounds.size;
    if (!FeedSizeIsTransposed(before, viewport) && !FeedSizeIsTransposed(cell.bounds.size, viewport)) return NO;
    if (collection.isTracking || collection.isDragging || collection.isDecelerating) return YES;
    NSIndexPath *visibleIndex = [collection indexPathForCell:page];
    id scroll = FeedScrollComponent(cell);
    id adapter = ReadLayoutObject(scroll, @"listAdapter");
    if (![adapter isKindOfClass:NSClassFromString(@"IGListAdapter")] ||
        ReadLayoutObject(adapter, @"collectionView") != collection) adapter = nil;
    NSIndexPath *savedIndex = adapter && adapter == gBackgroundFeedAdapter ?
        FeedIndexForEpisode(adapter, gBackgroundEpisode, collection) : nil;
    NSIndexPath *episodeIndex = savedIndex ?:
        FeedIndexForEpisode(adapter, ReadLayoutObject(scroll, @"currentCenterModel"), collection);
    NSIndexPath *index = episodeIndex ?: visibleIndex;
    if (!index) return YES;

    id context = ReadLayoutObject(cell, @"listVCContext");
    id ui = ReadLayoutObject(context, @"uiComponent");
    UICollectionViewLayout *layout = collection.collectionViewLayout;
    UICollectionViewLayoutAttributes *previousAttributes = [layout layoutAttributesForItemAtIndexPath:index];
    CGRect previousFrame = previousAttributes ? previousAttributes.frame : CGRectNull;
    CGPoint previousOffset = collection.contentOffset;
    __block BOOL usedAttributes = NO;
    __block BOOL refreshed = NO;
    __block CGSize appliedSize = CGSizeZero;
    __block CGSize playerSize = CGSizeZero;
    __block CGSize attributesSize = CGSizeZero;
    __block CGSize nativeItemSize = CGSizeZero;
    __block BOOL usedNativeInvalidation = NO;
    __block BOOL correctedItemSize = NO;
    [UIView performWithoutAnimation:^{
        if ([ui isKindOfClass:NSClassFromString(@"FQVShortVideoListVCUIComponent")]) {
            CallNativeLayoutMethod(ui, @"setupSafeInsets");
            CallNativeLayoutMethod(ui, @"setupVideoSizes");
        }
        usedNativeInvalidation = InvalidateFeedMetrics(collection);
        UICollectionViewLayoutAttributes *attributes = [layout layoutAttributesForItemAtIndexPath:index];
        SEL sizeSelector = NSSelectorFromString(@"sizeForItemAtIndexPath:");
        CGSize (*readSize)(id, SEL, NSIndexPath *) =
            (void *)VerifiedOneArgMethod(adapter, sizeSelector, @encode(CGSize), @encode(id));
        if (readSize) nativeItemSize = readSize(adapter, sizeSelector, index);
        if (adapter && attributes && FeedSizeIsTransposed(attributes.size, viewport) && InstallFeedItemSizeHook()) {
            gFeedSizingViewport = viewport;
            gFeedSizingAdapter = adapter;
            @try {
                InvalidateFeedMetrics(collection);
                attributes = [layout layoutAttributesForItemAtIndexPath:index];
                correctedItemSize = attributes && FeedSizesMatch(attributes.size, viewport);
            } @finally {
                gFeedSizingAdapter = nil;
            }
        }
        attributesSize = attributes ? attributes.size : CGSizeZero;
        if (attributes && FeedSizesMatch(attributesSize, viewport)) {
            // Keep the same item in view if recalculating the paging layout moved it.
            UIEdgeInsets insets = collection.adjustedContentInset;
            CGFloat minY = -insets.top;
            CGFloat maxY = MAX(minY, collection.contentSize.height - viewport.height + insets.bottom);
            CGFloat targetY = previousOffset.y;
            if (FeedSizeIsTransposed(previousFrame.size, viewport) ||
                (episodeIndex && ![episodeIndex isEqual:visibleIndex])) {
                targetY = CGRectGetMinY(attributes.frame) - insets.top;
            } else if (!CGRectIsEmpty(previousFrame)) {
                targetY += CGRectGetMinY(attributes.frame) - CGRectGetMinY(previousFrame);
            }
            targetY = MIN(MAX(targetY, minY), maxY);
            if (fabs(collection.contentOffset.y - targetY) > 1) {
                [collection setContentOffset:CGPointMake(collection.contentOffset.x, targetY) animated:NO];
                [collection layoutIfNeeded];
            }
        }

        UICollectionViewCell *currentPage = [collection cellForItemAtIndexPath:index];
        if (![currentPage isKindOfClass:NSClassFromString(@"FQVShortVideoCell")]) return;
        if (FeedSizeIsTransposed(currentPage.bounds.size, viewport) &&
            FeedSizesMatch(attributesSize, viewport) &&
            CGAffineTransformIsIdentity(currentPage.transform) &&
            CATransform3DIsIdentity(attributes.transform3D)) {
            // Reapply UIKit's frame if the existing cell kept its pre-resume geometry.
            currentPage.frame = attributes.frame;
            usedAttributes = YES;
        }
        appliedSize = currentPage.bounds.size;
        if (!FeedSizesMatch(appliedSize, viewport)) return;
        [currentPage setNeedsLayout];
        [currentPage layoutIfNeeded];
        UIView *currentCell = VisiblePlayerCellInView(currentPage, window, NO);
        refreshed = CallNativeLayoutMethod(currentCell, @"refreshCellViewLayoutForResizing");
        id player = ReadLayoutObject(currentCell, @"vPlayer");
        if (player) {
            CallNativeLayoutMethod(player, @"refreshPlayerViewLayout");
            RefreshNativeVideoSurface(currentCell, window);
        }
        playerSize = currentCell ? currentCell.bounds.size : CGSizeZero;
    }];
    gForegroundFeedLayoutResult = [NSString stringWithFormat:
        @"viewport=%@ page=%@ → %@ layout=%@ attributes=%@ native item=%@ IGList reset=%d size corrected=%d "
         "player=%@ frame reapplied=%d UI refreshed=%d anchor=%@[%ld,%ld] offset=%.0f→%.0f",
        NSStringFromCGSize(viewport), NSStringFromCGSize(before), NSStringFromCGSize(appliedSize),
        NSStringFromClass(layout.class), NSStringFromCGSize(attributesSize), NSStringFromCGSize(nativeItemSize), usedNativeInvalidation,
        correctedItemSize, NSStringFromCGSize(playerSize), usedAttributes, refreshed,
        savedIndex ? @"background episode" : episodeIndex ? @"current episode" : @"visible item",
        (long)index.section, (long)index.item, previousOffset.y, collection.contentOffset.y];
    return !FeedSizesMatch(appliedSize, viewport) || CGSizeEqualToSize(playerSize, CGSizeZero) ||
           FeedSizeIsTransposed(playerSize, viewport);
}

static void ScheduleForegroundFeedRelayout(UIWindowScene *scene, NSUInteger generation, BOOL retry) {
    __weak UIWindowScene *weakScene = scene;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (retry ? 300 : 400) * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        UIWindowScene *activeScene = weakScene;
        UIWindow *window = MainWindow(HongguoDelegate());
        if (generation != gForegroundFeedGeneration || !activeScene || !window || window.hidden ||
            activeScene.activationState != UISceneActivationStateForegroundActive ||
            window.windowScene != activeScene || !IsLandscapeInnerScene(activeScene)) return;
        if (gNativeFoldPending) {
            if (retry) ScheduleForegroundFeedRelayout(activeScene, generation, NO);
            return;
        }
        if (VisibleFullscreenController(window)) return;
        gForegroundFeedLayoutResult = nil;
        BOOL needsRetry = RefreshForegroundFeed(window);
        if (!gForegroundFeedLayoutResult && (!needsRetry || !retry)) {
            gForegroundFeedLayoutResult = needsRetry ? @"feed unavailable or scrolling" :
                                                      @"no transposed feed page detected";
        }
        if (gForegroundFeedLayoutResult) {
            NSString *reason = !needsRetry ? @"foreground feed checked" :
                (retry ? @"foreground feed retry scheduled" : @"foreground feed relayout incomplete");
            LogWindow(window, activeScene, reason);
            UpdateHUD(activeScene);
        }
        if (needsRetry && retry) ScheduleForegroundFeedRelayout(activeScene, generation, NO);
    });
}

static void RefreshFeedAfterFullscreenExit(UIWindow *window, BOOL retry) {
    UIWindowScene *scene = ForegroundScene();
    if (!window || window.hidden || !scene || window.windowScene != scene || !IsInnerScene(scene)) return;
    if (VisibleFullscreenController(window)) {
        if (retry) {
            __weak UIWindow *weakWindow = window;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                RefreshFeedAfterFullscreenExit(weakWindow, NO);
            });
        }
        return;
    }
    [window layoutIfNeeded];
    FitExpandedFeedViewport(window, gLastCoverFeedWidth);
    BOOL relaid = RunNativePlayerRelayout(window, gLastCoverFeedWidth);
    RefreshStatusBarPolicy(window);
    LogWindow(window, scene, relaid ? @"native feed relayout after fullscreen exit" :
              @"native feed relayout unavailable after fullscreen exit");
    UpdateHUD(scene);
    if (retry && (!relaid || !NativeRenderView(VisiblePlayerCell(window, YES), window))) {
        __weak UIWindow *weakWindow = window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            RefreshFeedAfterFullscreenExit(weakWindow, NO);
        });
    }
}

static void (*OriginalEndFullscreenDismiss)(id, SEL);

static void HookEndFullscreenDismiss(id manager, SEL selector) {
    OriginalEndFullscreenDismiss(manager, selector);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gFullscreenCrossedDisplays) return;
        gFullscreenCrossedDisplays = NO;
        __weak UIWindow *window = MainWindow(HongguoDelegate());
        // The app can reattach the rotated player after notifying its delegate.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            RefreshFeedAfterFullscreenExit(window, YES);
        });
    });
}

static void InstallFullscreenDismissHook(void) {
    if (OriginalEndFullscreenDismiss) return;
    Class cls = NSClassFromString(@"FQVRotateScreenManager");
    SEL selector = NSSelectorFromString(@"endDismissFullScreenViewController");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return;
    char type[8];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, @encode(void)) != 0) return;
    OriginalEndFullscreenDismiss = (void *)method_getImplementation(method);
    if (!class_addMethod(cls, selector, (IMP)HookEndFullscreenDismiss, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)HookEndFullscreenDismiss);
    }
}

static void ScheduleNativeFoldRelayout(UIWindow *window, UIWindowScene *scene) {
    static __weak UIWindow *previousWindow;
    static BOOL previousInner;
    static BOOL awaitingFirstCoverExpansion;
    static CGFloat lastCoverWidth;
    static NSUInteger generation;
    if (!window || !scene || window.hidden) return;
    BOOL inner = IsInnerScene(scene);
    if (!inner) {
        CGSize size = scene.coordinateSpace.bounds.size;
        lastCoverWidth = size.width;
        gLastCoverFeedWidth = MIN(size.width, size.height);
    }
    if (previousWindow != window) {
        RestoreExpandedFeedViewport();
        previousWindow = window;
        previousInner = inner;
        awaitingFirstCoverExpansion = !inner;
        ++generation;
        gNativeFoldPending = NO;
        gNativeFoldNeedsRetry = NO;
        return;
    }
    if (inner == previousInner) return;
    if (VisibleFullscreenController(window)) gFullscreenCrossedDisplays = YES;
    gNativeFoldNeedsRetry = NO;
    if (!inner) {
        RestoreExpandedFeedViewport();
        gExpandedFeedViewportResult = nil;
    }
    previousInner = inner;
    CGFloat previousScreenWidth = lastCoverWidth;
    gNativePlayerLayoutResult = nil;
    NSUInteger change = ++generation;
    gNativeFoldPending = YES;
    __weak UIWindow *weakWindow = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        UIWindow *current = weakWindow;
        UIWindowScene *target = ForegroundScene();
        if (change != generation) return;
        if (!current || current.hidden || !target || current.windowScene != target ||
            IsInnerScene(target) != inner) {
            gNativeFoldPending = NO;
            previousInner = !inner;
            gNativeFoldNeedsRetry = YES;
            return;
        }
        [current layoutIfNeeded];
        UIViewController *fullscreen = VisibleFullscreenController(current);
        if (fullscreen) gFullscreenCrossedDisplays = YES;
        if (inner && !fullscreen) FitExpandedFeedViewport(current, previousScreenWidth);
        BOOL relaid = RunNativePlayerRelayout(current, 0);
        LogWindow(current, target, relaid ? @"native fold relayout before video fallback" :
                  @"native fold relayout unavailable before video fallback");
        gNativeFoldPending = NO;
        FitCurrentVideo();
        LogWindow(current, target, @"after video fallback check");
        UpdateHUD(target);
        if (!inner || !awaitingFirstCoverExpansion) return;
        awaitingFirstCoverExpansion = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            UIWindow *expanded = weakWindow;
            UIWindowScene *expandedScene = ForegroundScene();
            if (change != generation || !expanded || expanded.hidden || !expandedScene ||
                expanded.windowScene != expandedScene || !IsInnerScene(expandedScene)) return;
            [expanded layoutIfNeeded];
            if (VisibleFullscreenController(expanded)) return;
            UIView *cell = VisiblePlayerCell(expanded, YES);
            UIView *render = NativeRenderView(cell, expanded);
            BOOL staleCell = cell && fabs(cell.bounds.size.width - previousScreenWidth) <= 4;
            BOOL staleRender = render && fabs(render.bounds.size.width - previousScreenWidth) <= 4;
            if (render && !staleCell && !staleRender && relaid) return;
            BOOL retried = RunNativePlayerRelayout(expanded, previousScreenWidth);
            LogWindow(expanded, expandedScene, retried ? @"first expansion native retry invoked" :
                      @"first expansion native retry unavailable");
            UpdateHUD(expandedScene);
        });
    });
}
#endif

static void ReconcileWindow(NSString *reason) {
    if (!IsHongguo()) return;
    InstallHongguoIPadTest();
#if APP_ADAPTER_IPAD_TEST
    InstallStatusBarPolicy();
    InstallCompactTabBar();
    InstallSafeAreaHooks();
    InstallFullscreenDismissHook();
#endif
    InstallMetalProbe();
    InstallSeriesLayoutHook();
    UIWindow *window = MainWindow(HongguoDelegate());
    UIWindowScene *scene = ForegroundScene();
#if APP_ADAPTER_IPAD_TEST
    UpdateIPadMode(scene);
    gReconciledScene = scene;
    gReconciledSceneBounds = scene ? scene.coordinateSpace.bounds : CGRectNull;
    gReconciledInnerMode = IsInnerScene(scene);
    ScheduleNativeFoldRelayout(window, scene);
#endif
    if (window && !window.hidden) {
        FitWindow(window, scene);
        if (scene && scene.activationState == UISceneActivationStateForegroundActive &&
            !window.isKeyWindow) {
            BOOL hasKeyWindow = NO;
            for (UIWindow *other in scene.windows) {
                if (other.isKeyWindow && !other.hidden) {
                    hasKeyWindow = YES;
                    break;
                }
            }
            if (!hasKeyWindow) [window makeKeyWindow];
        }
    }
    FitCurrentVideo();
#if APP_ADAPTER_IPAD_TEST
    RefreshStatusBarPolicy(window);
#endif
    LogWindow(window, scene, reason);
    UpdateHUD(scene);
}

#if APP_ADAPTER_IPAD_TEST
static void ObserveDisplayTransition(void) {
    if (!IsHongguo()) return;
    static NSUInteger generation;
    NSUInteger change = ++generation;
    atomic_store_explicit(&gDisplayGeometrySettling, true, memory_order_relaxed);
    UpdateIPadMode(ForegroundScene());
    // A screen notification can arrive before its window scene adopts the new geometry.
    const NSUInteger delays[] = {150, 400, 800};
    for (NSUInteger index = 0; index < sizeof(delays) / sizeof(delays[0]); ++index) {
        BOOL last = index == sizeof(delays) / sizeof(delays[0]) - 1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[index] * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (change != generation) return;
            UIWindowScene *scene = ForegroundScene();
            CGRect bounds = scene ? scene.coordinateSpace.bounds : CGRectNull;
            if (scene != gReconciledScene || !CGRectEqualToRect(bounds, gReconciledSceneBounds) ||
                IsInnerScene(scene) != gReconciledInnerMode || gNativeFoldNeedsRetry) {
                ReconcileWindow(@"display geometry settled");
            }
            if (last) atomic_store_explicit(&gDisplayGeometrySettling, false, memory_order_relaxed);
        });
    }
}
#endif

static void HookMakeKeyAndVisible(UIWindow *window, SEL selector) {
    BOOL isMainWindow = NSThread.isMainThread && window == MainWindow(HongguoDelegate());
    if (isMainWindow) {
        InstallMetalProbe();
        UIWindowScene *scene = ForegroundScene();
        LogWindow(window, scene, @"before makeKeyAndVisible");
        FitWindow(window, scene);
    }
    OriginalMakeKeyAndVisible(window, selector);
    if (isMainWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ReconcileWindow(@"after makeKeyAndVisible");
        });
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                ReconcileWindow(@"startup +2s");
            });
        });
    }
}

__attribute__((constructor))
static void Init(void) {
    InstallHongguoIPadTest();
#if APP_ADAPTER_IPAD_TEST
    InstallStatusBarPolicy();
    InstallCompactTabBar();
    InstallSafeAreaHooks();
    InstallFullscreenDismissHook();
#endif
    Method screen = class_getClassMethod(UIScreen.class, @selector(mainScreen));
    if (screen) OriginalMainScreen = (void *)method_setImplementation(screen, (IMP)HookMainScreen);
    Method show = class_getInstanceMethod(UIWindow.class, @selector(makeKeyAndVisible));
    if (show) OriginalMakeKeyAndVisible = (void *)method_setImplementation(show, (IMP)HookMakeKeyAndVisible);

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
#if APP_ADAPTER_IPAD_TEST
    [center addObserverForName:UISceneDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue
                   usingBlock:^(NSNotification *note) {
        UIWindow *window = MainWindow(HongguoDelegate());
        if (!window.windowScene || window.windowScene != note.object) return;
        SaveBackgroundEpisode(window);
        gBackgroundFeedScene = window.windowScene;
        gForegroundFeedLayoutResult = nil;
        ++gForegroundFeedGeneration;
    }];
#endif
    for (NSNotificationName name in @[UISceneWillEnterForegroundNotification,
                                      UISceneDidActivateNotification,
                                      UIScreenDidConnectNotification,
                                      UIScreenDidDisconnectNotification,
                                      UIApplicationDidBecomeActiveNotification,
                                      UIDeviceOrientationDidChangeNotification]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
#if APP_ADAPTER_IPAD_TEST
            if ([note.name isEqualToString:UIScreenDidConnectNotification] ||
                [note.name isEqualToString:UIScreenDidDisconnectNotification]) {
                if (NSThread.isMainThread) ObserveDisplayTransition();
                else dispatch_async(dispatch_get_main_queue(), ^{ ObserveDisplayTransition(); });
            }
#endif
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![note.name isEqualToString:UIDeviceOrientationDidChangeNotification]) {
                    ReconcileWindow(note.name);
#if APP_ADAPTER_IPAD_TEST
                    if ([note.name isEqualToString:UISceneDidActivateNotification] &&
                        gBackgroundFeedScene && note.object == gBackgroundFeedScene) {
                        UIWindowScene *scene = gBackgroundFeedScene;
                        gBackgroundFeedScene = nil;
                        ScheduleForegroundFeedRelayout(scene, gForegroundFeedGeneration, YES);
                    }
#endif
                    return;
                }
                // Orientation notifications can precede the scene and root layout updates.
                NSUInteger update = ++gOrientationUpdate;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                               dispatch_get_main_queue(), ^{
                    if (update == gOrientationUpdate) ReconcileWindow(@"orientation settled");
                });
            });
        }];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        ReconcileWindow(@"injection +3s");
    });
}
