#import "DecoratedAppSceneViewController.h"
#import "ResizeHandleView.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "AppSceneViewController.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "PiPManager.h"
#import "VirtualWindowsHostView.h"
#import "../LiveContainer/Localization.h"
#import "utils.h"

@interface DecoratedAppSceneViewController()
@property(nonatomic) NSArray* activatedVerticalConstraints;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) int pid;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) UIBarButtonItem *maximizeButton;
@property(nonatomic) bool isAppTerminationRequested;
@property(nonatomic) BOOL isClosing;
@end

@implementation DecoratedAppSceneViewController
- (instancetype)initWindowName:(NSString*)windowName bundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID rootVC:(UIViewController*)rootVC {
    self = [super initWithNibName:nil bundle:nil];
    self.view = [[UIStackView alloc] initWithFrame:self.view.frame];
    [MultitaskDockManager.shared.windowHostingView addSubview:self.view];
    [rootVC addChildViewController:self];
    
    _dataUUID = dataUUID;
    _scaleRatio = 1.0;
    _isMaximized = [NSUserDefaults.lcUserDefaults boolForKey:@"LCLaunchMultitaskMaximized"];
    _appSceneVC = [[AppSceneViewController alloc] initWithBundleId:bundleId dataUUID:dataUUID delegate:self];
    self.title = windowName;
    [self setupDecoratedView];
    
    [MultitaskDockManager.shared addRunningApp:windowName appUUID:dataUUID view:self.view];
    
    NSArray *menuItems = @[
        [UIAction actionWithTitle:@"lc.multitask.copyPid".loc image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = @(self.appSceneVC.pid).stringValue;
        }],
        [UIAction actionWithTitle:@"lc.multitask.enablePip".loc image:[UIImage systemImageNamed:@"pip.enter"] identifier:nil handler:^(UIAction * _Nonnull action) {
            if ([PiPManager.shared isPiPWithVC:self.appSceneVC]) {
                [PiPManager.shared stopPiP];
            } else {
                [PiPManager.shared startPiPWithVC:self.appSceneVC];
            }
        }],
        [UICustomViewMenuElement elementWithViewProvider:^UIView *(UICustomViewMenuElement *element) {
            return [self scaleSliderViewWithTitle:@"lc.multitask.scale".loc min:0.5 max:2.0 value:self.scaleRatio stepInterval:0.01];
        }]
    ];
    

    __weak typeof(self) weakSelf = self;
    [self.navigationItem setTitleMenuProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions){
        if(!weakSelf.appSceneVC.isAppRunning) {
            return [UIMenu menuWithTitle:NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", nil) children:@[]];
        } else {
            NSString *pidText = [NSString stringWithFormat:@"PID: %d", weakSelf.pid];
            return [UIMenu menuWithTitle:pidText children:menuItems];
        }
    }];
    
    UIImage *minimizeImage = [UIImage systemImageNamed:@"minus.circle"];
    UIImageConfiguration *minimizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    minimizeImage = [minimizeImage imageWithConfiguration:minimizeConfig];
    UIBarButtonItem *minimizeButton = [[UIBarButtonItem alloc] initWithImage:minimizeImage style:UIBarButtonItemStylePlain target:self action:@selector(minimizeWindow)];
    minimizeButton.tintColor = [UIColor systemYellowColor];
    
    NSString *maximizeImageName = _isMaximized ? @"arrow.down.right.and.arrow.up.left.circle" : @"arrow.up.left.and.arrow.down.right.circle";
    UIImage *maximizeImage = [UIImage systemImageNamed:maximizeImageName];
    UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    maximizeImage = [maximizeImage imageWithConfiguration:maximizeConfig];
    self.maximizeButton = [[UIBarButtonItem alloc] initWithImage:maximizeImage style:UIBarButtonItemStylePlain target:self action:@selector(maximizeWindow)];
    self.maximizeButton.tintColor = [UIColor systemGreenColor];
    
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark.circle"];
    UIImageConfiguration *closeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    closeImage = [closeImage imageWithConfiguration:closeConfig];
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:closeImage style:UIBarButtonItemStylePlain target:self action:@selector(closeWindow)];
    closeButton.tintColor = [UIColor systemRedColor];
    
    NSArray *barButtonItems = @[closeButton, self.maximizeButton, minimizeButton];
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        // resize handle overlaps the close button, so put the buttons on the left
        self.navigationItem.leftBarButtonItems = barButtonItems;
    } else {
        self.navigationItem.rightBarButtonItems = barButtonItems;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    });

    return self;
}

- (void)setupDecoratedView {
    CGFloat navBarHeight = 44;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);
    CGRect frame = CGRectMake(0, 0, isLandscape ? 480 : 320, (isLandscape ? 320 : 480) + navBarHeight);
    CGRect safeFrame = [self windowFrameWithInsets:self.view.window.safeAreaInsets];
    CGRect availableFrame = CGRectIsEmpty(safeFrame) ? self.view.superview.bounds : safeFrame;
    frame.origin = CGPointMake(CGRectGetMidX(availableFrame) - frame.size.width / 2, CGRectGetMidY(availableFrame) - frame.size.height / 2);
    frame = [self constrainedWindowedFrame:frame];

    if(_isMaximized) {
        if(!CGRectIsEmpty(safeFrame)) {
            // Save the windowed frame relative to the safe area, in the host view's coordinates.
            frame.origin.x = (frame.origin.x - safeFrame.origin.x) / safeFrame.size.width;
            frame.origin.y = (frame.origin.y - safeFrame.origin.y) / safeFrame.size.height;
            self.originalFrame = frame;
        }
    } else {
        self.view.frame = frame;
    }
    
    // Navigation bar
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, navBarHeight)];
    navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:self.title];
    navigationBar.items = @[navigationItem];
    
    self.view.axis = UILayoutConstraintAxisVertical;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.layer.cornerRadius = 10;
    self.view.layer.masksToBounds = YES;

    self.navigationBar = navigationBar;
    self.navigationItem = navigationBar.items.firstObject;
    if (!self.navigationBar.superview) {
        [self.view addArrangedSubview:self.navigationBar];
    }
    
    CGRect contentFrame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height - navBarHeight);
    UIView *fixedPositionContentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        [self.view insertArrangedSubview:fixedPositionContentView atIndex:0];
    } else {
        [self.view addArrangedSubview:fixedPositionContentView];
    }
    [self.view sendSubviewToBack:fixedPositionContentView];
    
    self.contentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.layer.anchorPoint = self.contentView.layer.position = CGPointMake(0, 0);
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [fixedPositionContentView addSubview:self.contentView];
    
    UIPanGestureRecognizer *moveGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindow:)];
    moveGesture.minimumNumberOfTouches = 1;
    moveGesture.maximumNumberOfTouches = 1;
    [self.navigationBar addGestureRecognizer:moveGesture];

    // Resize handle (idea stolen from Notes debugging window)
    UIPanGestureRecognizer *resizeGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeWindow:)];
    resizeGesture.minimumNumberOfTouches = 1;
    resizeGesture.maximumNumberOfTouches = 1;
    self.resizeHandle = [[ResizeHandleView alloc] initWithFrame:CGRectMake(self.view.frame.size.width - navBarHeight, self.view.frame.size.height - navBarHeight, navBarHeight, navBarHeight)];
    self.resizeHandle.alpha = _isMaximized ? 0.0 : 1.0;
    [self.resizeHandle addGestureRecognizer:resizeGesture];
    [self.view addSubview:self.resizeHandle];
    
    self.view.layer.borderWidth = _isMaximized ? 0.0 : 1.0;
    self.view.layer.borderColor = UIColor.secondarySystemBackgroundColor.CGColor;
    
    [self addChildViewController:_appSceneVC];
    [self.view insertSubview:_appSceneVC.view atIndex:0];
    _appSceneVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self updateVerticalConstraints];
    [NSLayoutConstraint activateConstraints:@[
        [_appSceneVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_appSceneVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    
    
    NSUserDefaults *defaults = NSUserDefaults.lcSharedDefaults;

    [defaults addObserver:self forKeyPath:@"LCMultitaskBottomWindowBar" options:NSKeyValueObservingOptionNew context:NULL];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sceneDidActivate:) name:UISceneDidActivateNotification object:nil];
    [self updateOriginalFrame];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSUserDefaults.lcSharedDefaults removeObserver:self forKeyPath:@"LCMultitaskBottomWindowBar"];
}

- (void)sceneDidActivate:(NSNotification *)notification {
    if(notification.object != self.view.window.windowScene) return;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self updateWindowFrame];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateWindowFrame];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateWindowFrame];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updateWindowFrame];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updateWindowFrame];
    }];
}

// Stolen from UIKitester
- (UIView *)scaleSliderViewWithTitle:(NSString *)title min:(CGFloat)minValue max:(CGFloat)maxValue value:(CGFloat)initialValue stepInterval:(CGFloat)step {
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.exclusiveTouch = YES;

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:10.0],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0],
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16.0]
    ]];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    [stackView addArrangedSubview:label];
    
    _UIPrototypingMenuSlider *slider = [[_UIPrototypingMenuSlider alloc] init];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = initialValue;
    slider.stepSize = step;
    
    NSLayoutConstraint *sliderHeight = [slider.heightAnchor constraintEqualToConstant:40.0];
    sliderHeight.active = YES;
    
    [stackView addArrangedSubview:slider];
    
    [slider addTarget:self action:@selector(scaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    return containerView;
}

- (void)scaleSliderChanged:(_UIPrototypingMenuSlider *)slider {
    self.scaleRatio = slider.value;
    self.appSceneVC.scaleRatio = _scaleRatio;
    if(self.appSceneVC.usesHostingControllerAPI) {
        self.appSceneVC.contentView.transform = CGAffineTransformMakeScale(_scaleRatio, _scaleRatio);
    } else {
        self.appSceneVC.contentView.layer.sublayerTransform = CATransform3DMakeScale(_scaleRatio, _scaleRatio, 1.0);
    }
    __weak typeof(self) weakSelf = self;
    [self.appSceneVC updateFrameWithSettingsBlock:^(UIMutableApplicationSceneSettings *settings) {
        if(weakSelf.isMaximized) {
            [weakSelf updateMaximizedSafeAreaWithSettings:settings];
        } else {
            // it seems some apps don't honor these settings so we don't cover the top of the app
            settings.peripheryInsets = UIEdgeInsetsZero;
            settings.safeAreaInsetsPortrait = UIEdgeInsetsZero;
        }
    }];
}

- (void)closeWindow {
    _isAppTerminationRequested = true;
    if([_appSceneVC isAppRunning]) {
        [_appSceneVC terminate];
    } else {
        [self appSceneVCAppDidExit:self.appSceneVC];
    }
}

- (void)minimizeWindow {
    if (self.view.hidden) return;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
        self.view.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        if (!finished) return;
        self.view.hidden = YES;
        self.view.transform = CGAffineTransformIdentity;
        [self.view.superview sendSubviewToBack:self.view];
    }];
}

- (void)minimizeWindowPiP {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
    }];
}

- (void)unminimizeWindowPiP {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.hidden = NO;
        self.view.alpha = 1;
    } completion:nil];
}

- (void)maximizeWindow {
    [self.view layoutIfNeeded];
    if(!self.isMaximized) {
        [self updateOriginalFrame];
    }
    self.isMaximized = !self.isMaximized;

    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        if(!self.isMaximized) {
            CGRect safeFrame = [self windowFrameWithInsets:self.view.window.safeAreaInsets];
            if(!CGRectIsEmpty(safeFrame) && !CGRectIsEmpty(self.originalFrame)) {
                CGRect frame = self.originalFrame;
                frame.origin.x = safeFrame.origin.x + frame.origin.x * safeFrame.size.width;
                frame.origin.y = safeFrame.origin.y + frame.origin.y * safeFrame.size.height;
                self.view.frame = [self constrainedWindowedFrame:frame];
            }
        }
        // Layout the outer window even if the guest's scene has already been destroyed.
        [self updateVerticalConstraints];
        self.view.layer.borderWidth = self.isMaximized ? 0 : 1;
        self.resizeHandle.alpha = self.isMaximized ? 0 : 1;

        if(!self.isMaximized) {
            [self.appSceneVC updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
                settings.peripheryInsets = UIEdgeInsetsZero;
                settings.safeAreaInsetsPortrait = UIEdgeInsetsZero;
            }];
        }
        [self.view layoutIfNeeded];
    } completion:nil];

    NSString *imageName = self.isMaximized ? @"arrow.down.right.and.arrow.up.left.circle" : @"arrow.up.left.and.arrow.down.right.circle";
    UIImageConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    self.maximizeButton.image = [[UIImage systemImageNamed:imageName] imageWithConfiguration:config];
}

- (void)appSceneVCAppDidExit:(AppSceneViewController*)vc {
    BOOL skipTerminationScreen = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCSkipTerminatedScreen"];
    BOOL isManual = _isAppTerminationRequested;
    if(isManual || skipTerminationScreen) {
        self.isClosing = YES;
        MultitaskDockManager *dock = [MultitaskDockManager shared];
        [dock removeRunningApp:self.dataUUID];
        
        self.view.layer.masksToBounds = NO;
        [UIView transitionWithView:self.view duration:0.4 options:UIViewAnimationOptionTransitionCurlUp animations:^{
            self.view.hidden = YES;
        } completion:^(BOOL b){
            [self.view removeFromSuperview];
        }];
        
        if(skipTerminationScreen) {
            [MultitaskRelaunchManager scheduleRelaunchIfNeededWithBundleId:self.appSceneVC.bundleId dataUUID:self.dataUUID isManualTermination:isManual];
        }
    } else {
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.numberOfLines = 0;
        label.text = NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", @"");
        label.textAlignment = NSTextAlignmentCenter;
        [self.view insertSubview:label atIndex:0];
        [self updateWindowFrame];
    }
}

- (void)appSceneVC:(AppSceneViewController*)vc didInitializeWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(error) {
            [vc appTerminationCleanUp];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"lc.common.error".loc message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"lc.common.copy".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                UIPasteboard.generalPasteboard.string = error.localizedDescription;
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            self.pid = vc.pid;
            [self updateOriginalFrame];
            if (self.pidAvailableHandler) {
                self.pidAvailableHandler(@(self.pid), nil);
            }
        }
    });
}

- (void)appSceneVCWillActivateScene:(AppSceneViewController *)vc {
    // Set up initial settings such as frame, safe area, etc
    [self appSceneVC:vc didUpdateFromSettings:vc.presenter.scene.settings.mutableCopy transitionContext:nil lifecycleActionType:0];
}

- (void)appSceneVC:(AppSceneViewController*)vc didUpdateFromSettings:(UIMutableApplicationSceneSettings *)baseSettings transitionContext:(id)newContext lifecycleActionType:(uint32_t)actionType {
    [self updateWindowFrame];
    if(!baseSettings) return;
    [self.appSceneVC updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
        settings.userInterfaceStyle = baseSettings.userInterfaceStyle;
        settings.interfaceOrientation = baseSettings.interfaceOrientation;
        settings.deviceOrientation = baseSettings.deviceOrientation;
        settings.foreground = YES;
        
        if(self.isMaximized) {
            [self updateMaximizedSafeAreaWithSettings:settings];
        } else {
            settings.peripheryInsets = UIEdgeInsetsZero;
            settings.safeAreaInsetsPortrait = UIEdgeInsetsZero;
        }
        CGRect newFrame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height - self.navigationBar.frame.size.height/self.scaleRatio);
        
        if(UIInterfaceOrientationIsLandscape(baseSettings.interfaceOrientation)) {
            settings.frame = CGRectMake(0, 0, newFrame.size.height, newFrame.size.width);
        } else {
            settings.frame = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
        }
    }];
}

- (void)adjustNavigationBarButtonSpacingWithNegativeSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    if (!self.navigationBar) return;
    [self findAndAdjustButtonBarStackView:self.navigationBar withSpacing:spacing rightMargin:margin];
}

- (void)findAndAdjustButtonBarStackView:(UIView *)view withSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"_UIButtonBarStackView")]) {
            if ([subview respondsToSelector:@selector(setSpacing:)]) {
                [(_UIButtonBarStackView *)subview setSpacing:spacing];
            }
            
            if (subview.superview) {
                for (NSLayoutConstraint *constraint in subview.superview.constraints) {
                    if ((constraint.firstItem == subview && constraint.firstAttribute == NSLayoutAttributeTrailing) ||
                        (constraint.secondItem == subview && constraint.secondAttribute == NSLayoutAttributeTrailing)) {
                        constraint.constant = (constraint.firstItem == subview) ? -margin : margin;
                        break;
                    }
                }
                
                [subview setNeedsLayout];
                [subview.superview setNeedsLayout];
            }
            
            return;
        }
        
        [self findAndAdjustButtonBarStackView:subview withSpacing:spacing rightMargin:margin];
    }
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.3 animations:^{
        BOOL bottomWindowBar = [change[NSKeyValueChangeNewKey] boolValue];
        if(bottomWindowBar) {
            self.navigationItem.leftBarButtonItems = self.navigationItem.rightBarButtonItems;
            self.navigationItem.rightBarButtonItems = nil;
            [self.view addArrangedSubview:self.navigationBar];
        } else {
            self.navigationItem.rightBarButtonItems = self.navigationItem.leftBarButtonItems;
            self.navigationItem.leftBarButtonItems = nil;
            [self.view insertArrangedSubview:self.navigationBar atIndex:0];
        }
        
        [self updateVerticalConstraints];
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
        
        [self.view layoutIfNeeded];
    }];
}

- (void)moveWindow:(UIPanGestureRecognizer*)sender {
    if(_isMaximized) return;
    
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    self.view.center = CGPointMake(self.view.center.x + point.x, self.view.center.y + point.y);
    self.view.frame = [self constrainedWindowedFrame:self.view.frame];
    [self updateOriginalFrame];
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    if(_isMaximized) return;
    
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    CGRect frame = self.view.frame;
    frame.size.width = MAX(50, frame.size.width + point.x);
    frame.size.height = MAX(50, frame.size.height + point.y);
    self.view.frame = [self constrainedWindowedFrame:frame];
    [self updateOriginalFrame];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // FIXME: how to bring view to front when touching the passthrough view?
    [self.view.superview bringSubviewToFront:self.view];
}

- (void)updateVerticalConstraints {
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.3 animations:^{
        BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
        BOOL hideWindowBar = MultitaskDockManager.shared.isCollapsed && self.isMaximized;
        CGFloat navBarHeight = hideWindowBar ? 0 : 44;
        self.navigationBar.alpha = hideWindowBar ? 0 : 1;
        self.navigationBar.hidden = hideWindowBar;
        
        [self updateWindowFrame];
        // Updating the guest's insets must not gate the outer window's layout.
        if(self.isMaximized) {
            self.appSceneVC.shouldSkipDebounceOnce = YES;
            __weak typeof(self) weakSelf = self;
            [self.appSceneVC updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
                [weakSelf updateMaximizedSafeAreaWithSettings:settings];
            }];
        }
        
        [NSLayoutConstraint deactivateConstraints:self.activatedVerticalConstraints];
        if(bottomWindowBar) {
            self.activatedVerticalConstraints = @[
                [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-navBarHeight],
                [self.navigationBar.heightAnchor constraintEqualToConstant:navBarHeight]
            ];
        } else {
            self.activatedVerticalConstraints = @[
                [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:navBarHeight],
                [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
                [self.navigationBar.heightAnchor constraintEqualToConstant:navBarHeight]
            ];
        }
        [NSLayoutConstraint activateConstraints:self.activatedVerticalConstraints];

        [self.view layoutIfNeeded];
    }];
}

- (void)updateMaximizedSafeAreaWithSettings:(UIMutableApplicationSceneSettings *)settings {
    BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
    UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
    if(self.navigationBar.hidden) {
        settings.peripheryInsets = safeAreaInsets;
    } else if(bottomWindowBar) {
        // allow the control bar to overlap the bottom safe area
        safeAreaInsets.bottom = 0;
        settings.peripheryInsets = safeAreaInsets;
    } else {
        settings.peripheryInsets = UIEdgeInsetsMake(0, safeAreaInsets.left, safeAreaInsets.bottom, safeAreaInsets.right);
    }
    
    // scale peripheryInsets to match the scale ratio
    settings.peripheryInsets = UIEdgeInsetsMake(settings.peripheryInsets.top/_scaleRatio, settings.peripheryInsets.left/_scaleRatio, settings.peripheryInsets.bottom/_scaleRatio, settings.peripheryInsets.right/_scaleRatio);
    if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation currentOrientation = self.view.window.windowScene.interfaceOrientation;
        settings.safeAreaInsetsPortrait = LCUIEdgeInsetsRotateToOrientation(settings.peripheryInsets, currentOrientation);

    } else {
        settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(settings.peripheryInsets.top, settings.peripheryInsets.left, settings.peripheryInsets.bottom, settings.peripheryInsets.right);
    }
}

- (CGRect)windowFrameWithInsets:(UIEdgeInsets)insets {
    UIWindow *window = self.view.window;
    UIView *hostView = self.view.superview;
    if(!window || !hostView) return CGRectZero;
    // UIWindow.frame is not in the host view's coordinate space.
    CGRect frame = UIEdgeInsetsInsetRect(window.bounds, insets);
    return [hostView convertRect:frame fromView:window];
}

- (CGRect)constrainedWindowedFrame:(CGRect)frame {
    CGRect safeFrame = [self windowFrameWithInsets:self.view.window.safeAreaInsets];
    if(CGRectIsEmpty(safeFrame)) return frame;

    frame.size.width = MIN(MAX(50, frame.size.width), safeFrame.size.width);
    frame.size.height = MIN(MAX(50, frame.size.height), safeFrame.size.height);
    // Preserve horizontal off-screen dragging, but keep either control-bar position out of system UI.
    CGFloat oobOffset = MAX(30, frame.size.width - 30);
    frame.origin.x = MAX(CGRectGetMinX(safeFrame) - oobOffset, MIN(CGRectGetMaxX(safeFrame) - frame.size.width + oobOffset, frame.origin.x));
    frame.origin.y = MAX(CGRectGetMinY(safeFrame), MIN(CGRectGetMaxY(safeFrame) - frame.size.height, frame.origin.y));
    return frame;
}

- (void)updateWindowFrame {
    UIWindow *window = self.view.window;
    if(!window || !self.navigationBar || self.isClosing || window.windowScene.activationState == UISceneActivationStateBackground) return;
    // A scaled frame is undefined during minimize/restore animations.
    if(!CGAffineTransformIsIdentity(self.view.transform)) return;

    CGRect safeFrame = [self windowFrameWithInsets:window.safeAreaInsets];
    if(CGRectIsEmpty(safeFrame)) return;
    CGRect frame;
    if(self.isMaximized) {
        BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
        UIEdgeInsets insets = UIEdgeInsetsZero;
        if(!self.navigationBar.hidden && !bottomWindowBar) {
            insets.top = window.safeAreaInsets.top;
        }
        frame = [self windowFrameWithInsets:insets];
    } else {
        frame = self.view.frame;
        if(!CGRectIsEmpty(self.originalFrame)) {
            CGPoint center = self.view.center;
            frame.size = self.originalFrame.size;
            frame.origin = CGPointMake(center.x - frame.size.width / 2, center.y - frame.size.height / 2);
        }
        frame = [self constrainedWindowedFrame:frame];
    }
    if(!CGRectEqualToRect(self.view.frame, frame)) {
        self.view.frame = frame;
    }
}

- (void)updateOriginalFrame {
    if(_isMaximized || !CGAffineTransformIsIdentity(self.view.transform)) return;
    CGRect safeFrame = [self windowFrameWithInsets:self.view.window.safeAreaInsets];
    if(CGRectIsEmpty(safeFrame)) return;
    CGRect frame = self.view.frame;
    self.originalFrame = CGRectMake((frame.origin.x - safeFrame.origin.x) / safeFrame.size.width, (frame.origin.y - safeFrame.origin.y) / safeFrame.size.height, frame.size.width, frame.size.height);
}

@end
