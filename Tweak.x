#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <CaptainHook/CaptainHook.h>
#import <CoreMotion/CoreMotion.h>

static CFMutableSetRef icons;
static CATransform3D currentTransform;
static CGFloat reflectionOpacity;
static CMMotionManager *motionManager;
static UIApplication *springboard;
static volatile int orientationStatus;
static BOOL isUnlocked = NO;

@interface SBIconView : UIView
@end	

@interface SBNowPlayingBarView : UIView
@property (readonly, nonatomic) UIButton *toggleButton;
@property (readonly, nonatomic) UIButton *airPlayButton;
@end

@interface SBNowPlayingBarMediaControlsView : UIView
@property (readonly, nonatomic) UIButton *prevButton;
@property (readonly, nonatomic) UIButton *playButton;
@property (readonly, nonatomic) UIButton *nextButton;
@property (readonly, nonatomic) UIButton *airPlayButton;
@end

@interface UIView (Springtomize)
- (CGFloat)springtomizeScaleFactor;
@end


@interface SBOrientationLockManager : NSObject {
	NSMutableSet *_lockOverrideReasons;
	UIInterfaceOrientation _userLockedOrientation;
}
+ (SBOrientationLockManager *)sharedInstance;
- (void)restoreStateFromPrefs;
- (id)init;
- (void)dealloc;
- (void)lock;
- (void)lock:(UIInterfaceOrientation)lock;
- (void)unlock;
- (BOOL)isLocked;
- (UIInterfaceOrientation)userLockOrientation;
- (void)setLockOverrideEnabled:(BOOL)enabled forReason:(id)reason;
- (void)enableLockOverrideForReason:(id)reason suggestOrientation:(UIInterfaceOrientation)orientation;
- (void)enableLockOverrideForReason:(id)reason forceOrientation:(UIInterfaceOrientation)orientation;
- (BOOL)lockOverrideEnabled;
- (void)updateLockOverrideForCurrentDeviceOrientation;
- (void)_updateLockStateWithChanges:(id)changes;
- (void)_updateLockStateWithOrientation:(int)orientation changes:(id)changes;
- (void)_updateLockStateWithOrientation:(int)orientation forceUpdateHID:(BOOL)forceHID changes:(id)changes;
- (BOOL)_effectivelyLocked;
@end


static CATransform3D (*ScaledTransform)(UIView *);

static CATransform3D ScaledTransformSpringtomize(UIView *iconView)
{
	CGFloat scale = [iconView springtomizeScaleFactor];
	return CATransform3DScale(currentTransform, scale, scale, 1.0f);
}

static CATransform3D ScaledTransformDefault(UIView *iconView)
{
	return currentTransform;
}

%hook UIView 

- (void)didMoveToWindow
{
	if (!self.window)
		CFSetRemoveValue(icons, self);
	%orig;
}

- (void)dealloc
{
	CFSetRemoveValue(icons, self);
	%orig;
}

%end

%hook SBIconView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		CFSetSetValue(icons, self);
		CALayer *layer = self.layer;
		layer.sublayerTransform = ScaledTransform(self);
		[layer setValue:@"sublayerTransform" forKey:@"IconRotatorKeyPath"];
		CHIvar(self, _reflection, UIImageView *).alpha = reflectionOpacity;
	}
}

- (void)didMoveToSuperview
{
	%orig;
	if (self.superview) {
		self.layer.sublayerTransform = ScaledTransform(self);
	}
}

%end
	
static void ApplyRotatedViewTransform(UIView *view)
{
	if (view) {
		CALayer *layer = view.layer;
		layer.transform = ScaledTransform(view);
		[layer setValue:@"transform" forKey:@"IconRotatorKeyPath"];
		CFSetSetValue(icons, view);
	}
}


%hook SBNowPlayingBarView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self.toggleButton);
		ApplyRotatedViewTransform(self.airPlayButton);
	}
}

%end

%hook SBNowPlayingBarMediaControlsView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self.prevButton);
		ApplyRotatedViewTransform(self.playButton);
		ApplyRotatedViewTransform(self.nextButton);
		ApplyRotatedViewTransform(self.airPlayButton);
	}
}

%end

%hook SBSearchController

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
	UIView *result = %orig;
	if (result) {
		NSArray *subviews = result.subviews;
		if ([subviews count]) {
			ApplyRotatedViewTransform([subviews objectAtIndex:0]);
		}
	}
	return result;
}

%end
	

static void UpdateWithOrientation(UIInterfaceOrientation orientation)
{
	//NSLog(@"Calculate new Rotation: %i", orientation);
	switch (orientation) {
		case UIInterfaceOrientationPortrait:
			currentTransform = CATransform3DIdentity;
			reflectionOpacity = 1.0f;
			orientationStatus = UIInterfaceOrientationPortrait;
			break;
		case UIInterfaceOrientationPortraitUpsideDown:
		//Never called
			currentTransform = CATransform3DMakeRotation(M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		case UIInterfaceOrientationLandscapeRight:
			currentTransform = CATransform3DMakeRotation(0.5f * M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			orientationStatus = UIInterfaceOrientationLandscapeRight;
			break;
		case UIInterfaceOrientationLandscapeLeft:
			currentTransform = CATransform3DMakeRotation(-0.5f * M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			orientationStatus = UIInterfaceOrientationLandscapeLeft;
			break;
		default:
			return;
	}
	for (UIView *view in (id)icons) {
		CALayer *layer = view.layer;
		NSString *keyPath = [layer valueForKey:@"IconRotatorKeyPath"];
		CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
		NSValue *toValue = [NSValue valueWithCATransform3D:ScaledTransform(view)];
		animation.toValue = toValue;
		animation.duration = 0.2;
		animation.removedOnCompletion = YES;
		animation.fromValue = [layer.presentationLayer valueForKeyPath:keyPath];
		[layer setValue:toValue forKeyPath:keyPath];
		[layer addAnimation:animation forKey:@"IconRotator"];
		UIImageView **imageView = CHIvarRef(view, _reflection, UIImageView *);
		if (imageView)
			(*imageView).alpha = reflectionOpacity;
	}
}

static void SetAccelerometerEnabled(BOOL enabled)
{
	if(enabled){
		//NSLog(@"Set Accelerometer enabled");
		if(!motionManager){
			motionManager = [[CMMotionManager alloc] init];
			motionManager.accelerometerUpdateInterval = 0.2;
		}
		[motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMAccelerometerData *accelerometerData, NSError *error)
		{
			if(accelerometerData){
				float x = accelerometerData.acceleration.x;
				float y = accelerometerData.acceleration.y;
				float z = accelerometerData.acceleration.z; //That it only moves if not lying
				//Turn Right
				if(x > 0.5 && y > -0.3 && z > -0.7 && z < 0.7 && orientationStatus != 4){
					UpdateWithOrientation(UIInterfaceOrientationLandscapeLeft);
				}
				//Turn Portrait
				else if(y < -0.5 && x > -0.3 && x < 0.3 && z > -0.7 && z < 0.7 && orientationStatus != 1){
					UpdateWithOrientation(UIInterfaceOrientationPortrait);
				}
				//Turn Left
				else if(x < -0.5 && y > -0.3 && z > -0.7 && z < 0.7 && orientationStatus != 3){
					UpdateWithOrientation(UIInterfaceOrientationLandscapeRight);
				}
			}
		}];

	}
	else{
		//NSLog(@"Set Accelerometer disbaled");
		if(motionManager){
			[motionManager stopAccelerometerUpdates];
		}
	}
}

%hook SBAwayController
	
- (void)dimScreen:(BOOL)animated
{
	%orig;
	SetAccelerometerEnabled(NO);
	isUnlocked = NO;
	UpdateWithOrientation(UIInterfaceOrientationPortrait);
}
%end;



%hook SpringBoard

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	%orig;
	if ([UIView instancesRespondToSelector:@selector(springtomizeScaleFactor)])
		ScaledTransform = ScaledTransformSpringtomize;
	if(!springboard)
		springboard = self;
}

- (void)undim //Springboard is shown
{
	%orig;
	isUnlocked = YES;
	SBOrientationLockManager *olm = [%c(SBOrientationLockManager) sharedInstance];
		if (![olm _effectivelyLocked])
	 	    SetAccelerometerEnabled(YES);
}

%end

%hook SBOrientationLockManager
	
- (void)_updateLockStateWithChanges:(id)changes
{
	%orig;
	if ([self _effectivelyLocked]) {
		SetAccelerometerEnabled(NO);
		UpdateWithOrientation([self userLockOrientation]);
	} else if(isUnlocked){
		SetAccelerometerEnabled(YES);
	}
}

- (void)_updateLockStateWithOrientation:(UIInterfaceOrientation)orientation forceUpdateHID:(BOOL)updateHID changes:(id)changes
{
	%orig;
	if ([self _effectivelyLocked]) {
		SetAccelerometerEnabled(NO);
		UpdateWithOrientation([self userLockOrientation]);
	} else if(isUnlocked){
		SetAccelerometerEnabled(YES);
	}
}

- (void)_updateLockStateWithOrientation:(UIInterfaceOrientation)orientation changes:(id)changes
{
	%orig;
	if ([self _effectivelyLocked]) {
		SetAccelerometerEnabled(NO);
		UpdateWithOrientation([self userLockOrientation]);
	} else if(isUnlocked) {
		SetAccelerometerEnabled(YES);
	}
}

%end

%ctor
{
	%init;
	ScaledTransform = ScaledTransformDefault;
	currentTransform = CATransform3DIdentity;
	icons = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
	orientationStatus = 1;
}
