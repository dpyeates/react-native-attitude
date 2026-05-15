#import "RNAttitude.h"

#import <UIKit/UIKit.h>
#import <math.h>

#define UPDATERATEHZ 5
#define DEGTORAD 0.017453292
#define RADTODEG 57.29577951

#define ROTATE_NONE 0
#define ROTATE_LEFT 1
#define ROTATE_RIGHT 2

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
  id backgroundObserver;
  id foregroundObserver;
  long long nextEmitTimeMs;
  double lastEmittedRoll;
  double lastEmittedPitch;
  double lastEmittedHeading;
  BOOL hasEmittedSample;
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
    nextEmitTimeMs = 0;
    hasEmittedSample = NO;

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
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  if (backgroundObserver != nil) {
    [center removeObserver:backgroundObserver];
  }
  if (foregroundObserver != nil) {
    [center removeObserver:foregroundObserver];
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
  intervalMillis = interval >= 25 ? (NSInteger)interval : 25;
  @synchronized(self) {
    nextEmitTimeMs = 0;
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
  if ([lowercaseRotation isEqualToString:@"none"]) {
    rotation = ROTATE_NONE;
    locationManager.headingOrientation = CLDeviceOrientationPortrait;
  } else if ([lowercaseRotation isEqualToString:@"left"]) {
    rotation = ROTATE_LEFT;
    locationManager.headingOrientation = CLDeviceOrientationLandscapeLeft;
  } else if ([lowercaseRotation isEqualToString:@"right"]) {
    rotation = ROTATE_RIGHT;
    locationManager.headingOrientation = CLDeviceOrientationLandscapeRight;
  } else {
    NSLog(@"Unrecognised rotation passed to react-native-attitude, must be 'none','left' or 'right' only");
  }
  [self reset];
}

- (void)startObserving
{
  @synchronized(self) {
    nextEmitTimeMs = 0;
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
}

- (void)stopObserving
{
  [motionManager stopDeviceMotionUpdates];
  [locationManager stopUpdatingHeading];
  roll = 0;
  pitch = 0;
  heading = 0;
  isRunning = NO;
  @synchronized(self) {
    hasEmittedSample = NO;
    nextEmitTimeMs = 0;
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
    BOOL rateLimited = nowMs < nextEmitTimeMs;
    if (changed && !rateLimited) {
      nextEmitTimeMs = nowMs + intervalMillis;
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
