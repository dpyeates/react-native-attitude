#import "RNAttitude.h"

#import <UIKit/UIKit.h>
#import <math.h>

#define UPDATERATEHZ 5
#define HEARTBEAT_INTERVAL_MS 1000
#define MOTION_AUTH_TIMEOUT_SEC 30.0
#define DEGTORAD 0.017453292
#define RADTODEG 57.29577951

#define ROTATE_NONE 0
#define ROTATE_LEFT 1
#define ROTATE_RIGHT 2
#define ROTATE_UPSIDEDOWN 3

#define AXIS_X 1
#define AXIS_Y 2
#define AXIS_Z 3
#define AXIS_MINUS_X (AXIS_X | 0x80)
#define AXIS_MINUS_Y (AXIS_Y | 0x80)
#define AXIS_MINUS_Z (AXIS_Z | 0x80)

static void remapCoordinateSystem(double inR[], int X, int Y, double outR[]);
static void getOrientation(double R[9], double *pitch, double *roll);
static void applyRollOffset(double roll, double matrixIn[], double matrixOut[]);
static void applyPitchOffset(double pitch, double matrixIn[], double matrixOut[]);
static void matrixMultiply(double A[], double B[], double result[]);
static void CMRotationMatrixToFloatArray(CMRotationMatrix rotIn, double rotOut[]);
static NSInteger intervalMillisForInterval(double interval);

@implementation RNAttitude {
  BOOL isRunning;
  NSInteger intervalMillis;
  NSInteger rotation;
  double roll;
  double pitch;
  double pitchOffset;
  double rollOffset;
  double heading;
  RNAttitudeOutput output;
  CLLocationManager *locationManager;
  CMMotionManager *motionManager;
  NSOperationQueue *attitudeQueue;
  BOOL wasRunningBeforeBackground;
  BOOL autoRotation;
  id backgroundObserver;
  id foregroundObserver;
  id orientationObserver;
  long long nextEmitTimeMs;
  long long lastEmitTimeMs;
  double lastEmittedRoll;
  double lastEmittedPitch;
  double lastEmittedHeading;
  BOOL hasEmittedSample;
  dispatch_source_t heartbeatSource;
  dispatch_queue_t heartbeatQueue;
  NSMutableArray<RCTPromiseResolveBlock> *pendingMotionAuthResolvers;
  dispatch_source_t motionAuthPollSource;
  CMMotionActivityManager *motionAuthActivityManager;
  NSDate *motionAuthDeadline;
}

- (instancetype)init
{
  if (self = [super init]) {
    intervalMillis = (NSInteger)(1000 / UPDATERATEHZ);
    isRunning = NO;
    rotation = ROTATE_NONE;
    pitchOffset = 0;
    rollOffset = 0;
    roll = 0;
    pitch = 0;
    heading = 0;
    output = RNAttitudeOutputBoth;
    wasRunningBeforeBackground = NO;
    autoRotation = NO;
    orientationObserver = nil;
    nextEmitTimeMs = 0;
    lastEmitTimeMs = 0;
    hasEmittedSample = NO;
    heartbeatSource = nil;
    heartbeatQueue = dispatch_queue_create("com.sensorworks.rnattitude.heartbeat", DISPATCH_QUEUE_SERIAL);
    pendingMotionAuthResolvers = [NSMutableArray new];
    motionAuthPollSource = nil;
    motionAuthActivityManager = nil;
    motionAuthDeadline = nil;

    locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    locationManager.headingFilter = 1.0;

    motionManager = [[CMMotionManager alloc] init];
    motionManager.showsDeviceMovementDisplay = NO;
    motionManager.deviceMotionUpdateInterval = intervalMillis * 0.001;

    attitudeQueue = [[NSOperationQueue alloc] init];
    attitudeQueue.name = @"RNAttitudeDeviceMotion";
    attitudeQueue.maxConcurrentOperationCount = 1;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    backgroundObserver = [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                             object:nil
                                              queue:nil
                                         usingBlock:^(__unused NSNotification *note) {
                                           [self handleEnterBackground];
                                         }];
    foregroundObserver = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                             object:nil
                                              queue:nil
                                         usingBlock:^(__unused NSNotification *note) {
                                           [self handleBecomeActive];
                                         }];
  }
  return self;
}

- (void)dealloc
{
  [self stopHeartbeatTimer];
  // Resolve any in-flight auth promises so JS callers are not left hanging.
  [self settlePendingMotionAuthorization:NO];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  if (backgroundObserver != nil) {
    [center removeObserver:backgroundObserver];
  }
  if (foregroundObserver != nil) {
    [center removeObserver:foregroundObserver];
  }
  if (orientationObserver != nil) {
    [center removeObserver:orientationObserver];
  }
}

+ (NSString *)moduleName
{
  return @"RNAttitude";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeRNAttitudeSpecJSI>(params);
}

- (void)handleEnterBackground
{
  wasRunningBeforeBackground = isRunning;
  if (isRunning) {
    [self stopObserving];
  }
}

- (void)handleBecomeActive
{
  if (autoRotation) {
    // The interface orientation may have changed while backgrounded.
    [self updateAutoRotationBaseline];
  }
  if (wasRunningBeforeBackground) {
    wasRunningBeforeBackground = NO;
    [self startObserving];
  }
}

- (void)isSupported:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  BOOL motionAvailable = motionManager.isDeviceMotionAvailable;
  BOOL headingAvailable = [CLLocationManager headingAvailable];
  BOOL supported = motionAvailable;
  if (output == RNAttitudeOutputHeading) {
    supported = headingAvailable;
  } else if (output == RNAttitudeOutputBoth) {
    supported = motionAvailable && headingAvailable;
  }
  resolve(@(supported));
}

- (void)getAvailableSensors:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  NSMutableArray *sensors = [NSMutableArray new];

  void (^addSensor)(NSString *, NSString *) = ^(NSString *sensorId, NSString *name) {
    [sensors addObject:@{
      @"id": sensorId,
      @"name": name,
      @"vendor": @"",
      @"version": @0,
      @"maxRange": @0,
      @"resolution": @0,
      @"minDelayUs": @0,
    }];
  };

  if (motionManager.isAccelerometerAvailable) {
    addSensor(@"accelerometer", @"Accelerometer");
  }
  if (motionManager.isGyroAvailable) {
    addSensor(@"gyroscope", @"Gyroscope");
  }
  if (motionManager.isMagnetometerAvailable) {
    addSensor(@"magnetometer", @"Magnetometer");
  }
  if (motionManager.isDeviceMotionAvailable) {
    addSensor(@"deviceMotion", @"Device Motion");
  }
  if ([CLLocationManager headingAvailable]) {
    addSensor(@"heading", @"Heading");
  }

  resolve(sensors);
}

- (void)isMotionAuthorizationGranted:(RCTPromiseResolveBlock)resolve
                              reject:(RCTPromiseRejectBlock)reject
{
  CMAuthorizationStatus status = [CMMotionActivityManager authorizationStatus];
  resolve(@(status == CMAuthorizationStatusAuthorized));
}

- (void)requestMotionAuthorization:(RCTPromiseResolveBlock)resolve
                            reject:(RCTPromiseRejectBlock)reject
{
  CMAuthorizationStatus status = [CMMotionActivityManager authorizationStatus];
  if (status == CMAuthorizationStatusAuthorized) {
    resolve(@(YES));
    return;
  }
  if (status == CMAuthorizationStatusDenied || status == CMAuthorizationStatusRestricted) {
    resolve(@(NO));
    return;
  }

  // NotDetermined
  if (!motionManager.isDeviceMotionAvailable || ![CMMotionActivityManager isActivityAvailable]) {
    resolve(@(NO));
    return;
  }

  @synchronized(self) {
    [pendingMotionAuthResolvers addObject:[resolve copy]];
    if (pendingMotionAuthResolvers.count > 1) {
      // Another request is already waiting; share its result.
      return;
    }
  }

  motionAuthDeadline = [NSDate dateWithTimeIntervalSinceNow:MOTION_AUTH_TIMEOUT_SEC];
  NSDate *now = [NSDate date];
  motionAuthActivityManager = [[CMMotionActivityManager alloc] init];
  __weak RNAttitude *weakSelf = self;
  [motionAuthActivityManager queryActivityStartingFromDate:now
                                                    toDate:now
                                                   toQueue:[NSOperationQueue mainQueue]
                                               withHandler:^(__unused NSArray<CMMotionActivity *> *_Nullable activities,
                                                             NSError *_Nullable error) {
                                                 RNAttitude *strongSelf = weakSelf;
                                                 if (strongSelf == nil) {
                                                   return;
                                                 }
                                                 if ([strongSelf finishMotionAuthorizationIfDetermined]) {
                                                   return;
                                                 }
                                                 // Query finished but status never left NotDetermined
                                                 // (unavailable hardware, certain errors, etc.).
                                                 if (error != nil || ![CMMotionActivityManager isActivityAvailable]) {
                                                   [strongSelf settlePendingMotionAuthorization:NO];
                                                 }
                                               }];

  [self startMotionAuthPoll];
}

- (void)startMotionAuthPoll
{
  [self stopMotionAuthPoll];

  motionAuthPollSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(
      motionAuthPollSource,
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
      (uint64_t)(0.1 * NSEC_PER_SEC),
      (uint64_t)(0.05 * NSEC_PER_SEC));
  __weak RNAttitude *weakSelf = self;
  dispatch_source_set_event_handler(motionAuthPollSource, ^{
    RNAttitude *strongSelf = weakSelf;
    if (strongSelf != nil) {
      [strongSelf finishMotionAuthorizationIfDetermined];
    }
  });
  dispatch_resume(motionAuthPollSource);
}

- (void)stopMotionAuthPoll
{
  if (motionAuthPollSource != nil) {
    dispatch_source_cancel(motionAuthPollSource);
    motionAuthPollSource = nil;
  }
}

/**
 * Resolves all pending motion-auth promises and tears down poll/query state.
 */
- (void)settlePendingMotionAuthorization:(BOOL)authorized
{
  NSArray<RCTPromiseResolveBlock> *resolvers;
  @synchronized(self) {
    if (pendingMotionAuthResolvers.count == 0) {
      [self stopMotionAuthPoll];
      motionAuthActivityManager = nil;
      motionAuthDeadline = nil;
      return;
    }
    resolvers = [pendingMotionAuthResolvers copy];
    [pendingMotionAuthResolvers removeAllObjects];
  }
  [self stopMotionAuthPoll];
  motionAuthActivityManager = nil;
  motionAuthDeadline = nil;
  for (RCTPromiseResolveBlock resolve in resolvers) {
    resolve(@(authorized));
  }
}

/**
 * @return YES if authorization left NotDetermined and pending promises were settled.
 */
- (BOOL)finishMotionAuthorizationIfDetermined
{
  CMAuthorizationStatus status = [CMMotionActivityManager authorizationStatus];
  if (status == CMAuthorizationStatusNotDetermined) {
    NSDate *deadline = motionAuthDeadline;
    if (deadline != nil && [[NSDate date] compare:deadline] != NSOrderedAscending) {
      // Timed out waiting for a determination (dialog abandoned / status stuck).
      [self settlePendingMotionAuthorization:NO];
      return YES;
    }
    return NO;
  }

  [self settlePendingMotionAuthorization:status == CMAuthorizationStatusAuthorized];
  return YES;
}

- (void)zero
{
  pitchOffset = -pitch;
  rollOffset = -roll;
}

- (void)reset
{
  pitchOffset = 0;
  rollOffset = 0;
}

- (void)setOutput:(NSString *)outputIn
{
  NSString *lowercaseOutput = [outputIn lowercaseString];
  BOOL shouldStart = isRunning;
  [self stopObserving];
  if ([lowercaseOutput isEqualToString:@"both"]) {
    output = RNAttitudeOutputBoth;
  } else if ([lowercaseOutput isEqualToString:@"attitude"]) {
    output = RNAttitudeOutputAttitude;
  } else if ([lowercaseOutput isEqualToString:@"heading"]) {
    output = RNAttitudeOutputHeading;
  } else {
    NSLog(@"Unrecognised output passed to react-native-attitude, must be 'both', 'attitude' or 'heading' only");
  }
  if (shouldStart) {
    [self startObserving];
  }
}

- (void)setInterval:(double)interval
{
  intervalMillis = intervalMillisForInterval(interval);
  @synchronized(self) {
    nextEmitTimeMs = 0;
    lastEmitTimeMs = 0;
    hasEmittedSample = NO;
  }
  BOOL shouldStart = isRunning;
  [self stopObserving];
  motionManager.deviceMotionUpdateInterval = intervalMillis * 0.001;
  if (shouldStart) {
    [self startObserving];
  }
}

- (void)setRotation:(NSString *)rotationIn
{
  NSString *lowercaseRotation = [rotationIn lowercaseString];
  if ([lowercaseRotation isEqualToString:@"auto"]) {
    [self startAutoRotationTracking];
    return;
  }
  [self stopAutoRotationTracking];
  if ([lowercaseRotation isEqualToString:@"none"]) {
    [self applyRotation:ROTATE_NONE];
  } else if ([lowercaseRotation isEqualToString:@"left"]) {
    [self applyRotation:ROTATE_LEFT];
  } else if ([lowercaseRotation isEqualToString:@"right"]) {
    [self applyRotation:ROTATE_RIGHT];
  } else if ([lowercaseRotation isEqualToString:@"upsidedown"]) {
    [self applyRotation:ROTATE_UPSIDEDOWN];
  } else {
    NSLog(@"Unrecognised rotation passed to react-native-attitude, must be 'none','left','right','upsidedown' or 'auto' only");
  }
}

/**
 * Applies a rotation baseline: updates the coordinate remap mode, the heading
 * reference orientation and clears any zero() offsets (they are baseline-relative).
 */
- (void)applyRotation:(NSInteger)rotationMode
{
  rotation = rotationMode;
  switch (rotationMode) {
    case ROTATE_LEFT:
      locationManager.headingOrientation = CLDeviceOrientationLandscapeLeft;
      break;
    case ROTATE_RIGHT:
      locationManager.headingOrientation = CLDeviceOrientationLandscapeRight;
      break;
    case ROTATE_UPSIDEDOWN:
      locationManager.headingOrientation = CLDeviceOrientationPortraitUpsideDown;
      break;
    case ROTATE_NONE:
    default:
      locationManager.headingOrientation = CLDeviceOrientationPortrait;
      break;
  }
  [self reset];
}

/**
 * Auto rotation mode: follow the current interface orientation so pitch/roll/heading
 * stay correct even when the OS rotates the screen (or refuses an orientation lock,
 * as it may on iPadOS 26+ tablets).
 */
- (void)startAutoRotationTracking
{
  if (autoRotation) {
    [self updateAutoRotationBaseline];
    return;
  }
  autoRotation = YES;
  __weak RNAttitude *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
  });
  orientationObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:UIDeviceOrientationDidChangeNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(__unused NSNotification *note) {
                // The interface rotation animation lags the device orientation change;
                // re-read the actual interface orientation shortly after.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                                 [weakSelf updateAutoRotationBaseline];
                               });
                [weakSelf updateAutoRotationBaseline];
              }];
  [self updateAutoRotationBaseline];
}

- (void)stopAutoRotationTracking
{
  if (!autoRotation) {
    return;
  }
  autoRotation = NO;
  if (orientationObserver != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:orientationObserver];
    orientationObserver = nil;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
  });
}

- (void)updateAutoRotationBaseline
{
  if (!autoRotation) {
    return;
  }
  void (^update)(void) = ^{
    UIInterfaceOrientation interfaceOrientation = [self currentInterfaceOrientation];
    NSInteger newRotation;
    switch (interfaceOrientation) {
      // Interface landscapeRight corresponds to device orientation landscapeLeft and vice versa.
      case UIInterfaceOrientationLandscapeRight:
        newRotation = ROTATE_LEFT;
        break;
      case UIInterfaceOrientationLandscapeLeft:
        newRotation = ROTATE_RIGHT;
        break;
      case UIInterfaceOrientationPortraitUpsideDown:
        newRotation = ROTATE_UPSIDEDOWN;
        break;
      case UIInterfaceOrientationPortrait:
        newRotation = ROTATE_NONE;
        break;
      default:
        return; // unknown - keep the current baseline
    }
    if (newRotation != self->rotation) {
      [self applyRotation:newRotation];
    }
  };
  if ([NSThread isMainThread]) {
    update();
  } else {
    dispatch_async(dispatch_get_main_queue(), update);
  }
}

/** Must be called on the main thread. */
- (UIInterfaceOrientation)currentInterfaceOrientation
{
  UIWindowScene *foregroundScene = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    if (scene.activationState == UISceneActivationStateForegroundActive) {
      foregroundScene = (UIWindowScene *)scene;
      break;
    }
    if (foregroundScene == nil) {
      foregroundScene = (UIWindowScene *)scene;
    }
  }
  if (foregroundScene != nil) {
    return foregroundScene.interfaceOrientation;
  }
  return UIInterfaceOrientationUnknown;
}

- (void)startObserving
{
  @synchronized(self) {
    nextEmitTimeMs = 0;
    lastEmitTimeMs = 0;
    hasEmittedSample = NO;
  }
  motionManager.deviceMotionUpdateInterval = intervalMillis * 0.001;

  if (output == RNAttitudeOutputBoth || output == RNAttitudeOutputAttitude) {
    if (!motionManager.isDeviceMotionActive) {
      __weak RNAttitude *weakSelf = self;
      CMDeviceMotionHandler attitudeHandler = ^(CMDeviceMotion *_Nullable motion, NSError *_Nullable error) {
        RNAttitude *strongSelf = weakSelf;
        if (strongSelf == nil || motion == nil) {
          return;
        }
        double rotationMatrix[9], remappedMatrix[9];
        CMRotationMatrixToFloatArray(motion.attitude.rotationMatrix, rotationMatrix);

        if (strongSelf->rotation == ROTATE_LEFT) {
          remapCoordinateSystem(rotationMatrix, AXIS_Z, AXIS_MINUS_X, remappedMatrix);
        } else if (strongSelf->rotation == ROTATE_RIGHT) {
          remapCoordinateSystem(rotationMatrix, AXIS_MINUS_Z, AXIS_X, remappedMatrix);
        } else if (strongSelf->rotation == ROTATE_UPSIDEDOWN) {
          remapCoordinateSystem(rotationMatrix, AXIS_MINUS_X, AXIS_MINUS_Z, remappedMatrix);
        } else {
          remapCoordinateSystem(rotationMatrix, AXIS_X, AXIS_Z, remappedMatrix);
        }

        double r, p;
        if (strongSelf->pitchOffset != 0 || strongSelf->rollOffset != 0) {
          double offsetMatrix1[9], offsetMatrix2[9];
          applyPitchOffset(strongSelf->pitchOffset, remappedMatrix, offsetMatrix1);
          applyRollOffset(strongSelf->rollOffset, offsetMatrix1, offsetMatrix2);
          getOrientation(offsetMatrix2, &p, &r);
        } else {
          getOrientation(remappedMatrix, &p, &r);
        }

        strongSelf->roll = round(r * 10) / 10.0;
        strongSelf->pitch = round(p * 10) / 10.0;
        [strongSelf emitAttitudeUpdate];
      };

      [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical
                                                         toQueue:attitudeQueue
                                                     withHandler:attitudeHandler];
    }
  } else {
    [motionManager stopDeviceMotionUpdates];
    roll = 0;
    pitch = 0;
  }

  if (output == RNAttitudeOutputBoth || output == RNAttitudeOutputHeading) {
    [locationManager startUpdatingHeading];
  } else {
    [locationManager stopUpdatingHeading];
    heading = 0;
  }

  isRunning = YES;
  [self startHeartbeatTimer];
}

- (void)startHeartbeatTimer
{
  [self stopHeartbeatTimer];

  uint64_t intervalNs = (uint64_t)HEARTBEAT_INTERVAL_MS * NSEC_PER_MSEC;
  heartbeatSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, heartbeatQueue);
  dispatch_source_set_timer(
      heartbeatSource,
      dispatch_time(DISPATCH_TIME_NOW, intervalNs),
      intervalNs,
      100 * NSEC_PER_MSEC);
  __weak RNAttitude *weakSelf = self;
  dispatch_source_set_event_handler(heartbeatSource, ^{
    RNAttitude *strongSelf = weakSelf;
    if (strongSelf == nil || !strongSelf->isRunning) {
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      RNAttitude *mainSelf = weakSelf;
      if (mainSelf != nil && mainSelf->isRunning) {
        [mainSelf emitAttitudeUpdate];
      }
    });
  });
  dispatch_resume(heartbeatSource);
}

- (void)stopHeartbeatTimer
{
  if (heartbeatSource != nil) {
    dispatch_source_cancel(heartbeatSource);
    heartbeatSource = nil;
  }
}

- (void)stopObserving
{
  [self stopHeartbeatTimer];
  [motionManager stopDeviceMotionUpdates];
  [locationManager stopUpdatingHeading];
  roll = 0;
  pitch = 0;
  heading = 0;
  isRunning = NO;
  @synchronized(self) {
    hasEmittedSample = NO;
    nextEmitTimeMs = 0;
    lastEmitTimeMs = 0;
  }
}

- (void)addListener:(NSString *)eventName
{
}

- (void)removeListeners:(double)count
{
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
  heading = roundf(newHeading.magneticHeading);
  if (output == RNAttitudeOutputHeading || output == RNAttitudeOutputBoth) {
    [self emitAttitudeUpdate];
  }
}

- (void)emitAttitudeUpdate
{
  long long nowMs =
      (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
  BOOL shouldEmit = NO;
  @synchronized(self) {
    BOOL changed = !hasEmittedSample || roll != lastEmittedRoll ||
        pitch != lastEmittedPitch || heading != lastEmittedHeading;
    BOOL rateLimited = changed && (nowMs < nextEmitTimeMs);
    BOOL heartbeatDue = hasEmittedSample && !changed &&
        (nowMs >= lastEmitTimeMs + HEARTBEAT_INTERVAL_MS);
    if ((changed && !rateLimited) || heartbeatDue) {
      if (changed) {
        nextEmitTimeMs = nowMs + intervalMillis;
      }
      lastEmitTimeMs = nowMs;
      lastEmittedRoll = roll;
      lastEmittedPitch = pitch;
      lastEmittedHeading = heading;
      hasEmittedSample = YES;
      shouldEmit = YES;
    }
  }
  if (!shouldEmit) {
    return;
  }

  NSDictionary *payload = @{
    @"timestamp" : @(nowMs),
    @"roll" : @(roll),
    @"pitch" : @(pitch),
    @"heading" : @(heading),
  };
  [self emitOnAttitudeUpdate:payload];
}

@end

static NSInteger intervalMillisForInterval(double interval)
{
  switch ((NSInteger)interval) {
    case 1000:
    case 200:
    case 100:
    case 50:
    case 25:
      return (NSInteger)interval;
    default:
      return 200;
  }
}

static void remapCoordinateSystem(double inR[], int X, int Y, double outR[])
{
  int Z = X ^ Y;
  int x = (X & 0x3) - 1;
  int y = (Y & 0x3) - 1;
  int z = (Z & 0x3) - 1;
  int axis_y = (z + 1) % 3;
  int axis_z = (z + 2) % 3;
  if (((x ^ axis_y) | (y ^ axis_z)) != 0) {
    Z ^= 0x80;
  }
  bool sx = (X >= 0x80);
  bool sy = (Y >= 0x80);
  bool sz = (Z >= 0x80);
  for (int j = 0; j < 3; j++) {
    int offset = j * 3;
    for (int i = 0; i < 3; i++) {
      if (x == i)
        outR[offset + i] = sx ? -inR[offset + 0] : inR[offset + 0];
      if (y == i)
        outR[offset + i] = sy ? -inR[offset + 1] : inR[offset + 1];
      if (z == i)
        outR[offset + i] = sz ? -inR[offset + 2] : inR[offset + 2];
    }
  }
}

static void getOrientation(double R[9], double *pitch, double *roll)
{
  *pitch = asin(R[7]) * RADTODEG;
  *roll = atan2(-R[6], R[8]) * RADTODEG;
}

static void applyRollOffset(double rollIn, double matrixIn[], double matrixOut[])
{
  double value = rollIn * DEGTORAD;
  double rotateMatrix[] = {cos(value), 0, sin(value), 0, 1, 0, -sin(value), 0, cos(value)};
  matrixMultiply(matrixIn, rotateMatrix, matrixOut);
}

static void applyPitchOffset(double pitchIn, double matrixIn[], double matrixOut[])
{
  double value = pitchIn * DEGTORAD;
  double rotateMatrix[] = {1, 0, 0, 0, cos(value), -sin(value), 0, sin(value), cos(value)};
  matrixMultiply(matrixIn, rotateMatrix, matrixOut);
}

static void matrixMultiply(double A[], double B[], double result[])
{
  result[0] = A[0] * B[0] + A[1] * B[3] + A[2] * B[6];
  result[1] = A[0] * B[1] + A[1] * B[4] + A[2] * B[7];
  result[2] = A[0] * B[2] + A[1] * B[5] + A[2] * B[8];
  result[3] = A[3] * B[0] + A[4] * B[3] + A[5] * B[6];
  result[4] = A[3] * B[1] + A[4] * B[4] + A[5] * B[7];
  result[5] = A[3] * B[2] + A[4] * B[5] + A[5] * B[8];
  result[6] = A[6] * B[0] + A[7] * B[3] + A[8] * B[6];
  result[7] = A[6] * B[1] + A[7] * B[4] + A[8] * B[7];
  result[8] = A[6] * B[2] + A[7] * B[5] + A[8] * B[8];
}

static void CMRotationMatrixToFloatArray(CMRotationMatrix rotIn, double rotOut[])
{
  rotOut[0] = rotIn.m11;
  rotOut[1] = rotIn.m21;
  rotOut[2] = rotIn.m31;
  rotOut[3] = rotIn.m12;
  rotOut[4] = rotIn.m22;
  rotOut[5] = rotIn.m32;
  rotOut[6] = rotIn.m13;
  rotOut[7] = rotIn.m23;
  rotOut[8] = rotIn.m33;
}
