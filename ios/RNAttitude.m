// RNAttitude.m
//
// Useful info:
// http://plaw.info/articles/sensorfusion/
// https://dev.opera.com/articles/w3c-device-orientation-usage/
// http://bediyap.com/programming/convert-quaternion-to-euler-rotations/
// https://stackoverflow.com/questions/19239482/using-quaternion-instead-of-roll-pitch-and-yaw-to-track-device-motion
// https://stackoverflow.com/questions/11103683/euler-angle-to-quaternion-then-quaternion-to-euler-angle
// https://stackoverflow.com/questions/14482518/how-multiplybyinverseofattitude-cmattitude-class-is-implemented
// https://stackoverflow.com/questions/5782658/extracting-yaw-from-a-quaternion
#import "RNAttitude.h"

#import <React/RCTAssert.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>

#define UPDATERATEHZ 5
#define DEGTORAD 0.017453292
#define RADTODEG 57.29577951

#define ROTATE_NONE 0
#define ROTATE_LEFT 1
#define ROTATE_RIGHT 2

@implementation RNAttitude

RCT_EXPORT_MODULE();

- (id)init {
  self = [super init];
  if (self) {
    inverseReferenceInUse = false;
    intervalMillis = (int)(1000 / UPDATERATEHZ);
    nextSampleTime = 0;
    rotation = ROTATE_NONE;
    baseWorldQuaternion = getWorldTransformationQuaternion();
    
    // Allocate and initialize the motion manager.
    motionManager = [[CMMotionManager alloc] init];
    [motionManager setShowsDeviceMovementDisplay:YES];
    [motionManager setDeviceMotionUpdateInterval:intervalMillis * 0.001];
    
    // Allocate and initialize the operation queue for attitude updates.
    attitudeQueue = [[NSOperationQueue alloc] init];
    [attitudeQueue setName:@"DeviceMotion"];
    [attitudeQueue setMaxConcurrentOperationCount:1];
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"attitudeUpdate"];
}

// Determines if this device is capable of providing attitude updates - defaults to yes on IOS
RCT_REMAP_METHOD(isSupported,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
  return resolve(@YES);
}

// Applies an inverse to core data and compensates for any non-zero installations.
// Basically it makes a new 'zero' position for both pitch and roll.
RCT_EXPORT_METHOD(zero)
{
  inverseReferenceQuaternion.w = worldQuaternion.w;
  inverseReferenceQuaternion.x = -worldQuaternion.x;
  inverseReferenceQuaternion.y = -worldQuaternion.y;
  inverseReferenceQuaternion.z = -worldQuaternion.z;
  inverseReferenceInUse = true;
}

// Resets the inverse quaternion in use and goes back to using the default 'zero' position
RCT_EXPORT_METHOD(reset)
{
  inverseReferenceInUse = false;
  inverseReferenceQuaternion.w = 0;
  inverseReferenceQuaternion.x = 0;
  inverseReferenceQuaternion.y = 0;
  inverseReferenceQuaternion.z = 0;
}

// Sets the interval between event samples
RCT_EXPORT_METHOD(setInterval:(NSInteger)interval)
{
  self->intervalMillis = interval;
  [motionManager setDeviceMotionUpdateInterval:intervalMillis * 0.001];
}

// Sets the device rotation to either 'none', 'left' or 'right'
// If this isn't called then we assume 'portrait'/no rotation orientation
RCT_EXPORT_METHOD(setRotation:(NSString *)rotation)
{
  NSString *lowercaseRotation = [rotation lowercaseString];
  if([lowercaseRotation isEqualToString:@"none"]) {
    self->rotation = ROTATE_NONE;
  } else if([lowercaseRotation isEqualToString:@"left"]) {
    self->rotation = ROTATE_LEFT;
  } else if([lowercaseRotation isEqualToString:@"right"]) {
    self->rotation = ROTATE_RIGHT;
  } else {
    NSLog( @"Unrecognised rotation passed to react-native-attitude, must be 'none','left' or 'right' only");
  }
  if(self->inverseReferenceInUse) {
    inverseReferenceInUse = false;
  }
}

RCT_EXPORT_METHOD(startObserving) {
  if(!motionManager.isDeviceMotionActive) {
    nextSampleTime = 0;
    // the attitude update handler
    CMDeviceMotionHandler attitudeHandler = ^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
    {
      long long currentTime = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
      if (currentTime < self->nextSampleTime) {
        return;
      }
     
      // Extract the quaternion
      self->coreQuaternion = [[motion attitude] quaternion];
        
      // Adjust the core motion quaternion and heading result for left/right screen orientations
      CMQuaternion screenQuaternion;
      if(self->rotation == ROTATE_LEFT) {
        screenQuaternion = quaternionMultiply(self->coreQuaternion, getScreenTransformationQuaternion(90));
      } else if(self->rotation == ROTATE_RIGHT) {
        screenQuaternion = quaternionMultiply(self->coreQuaternion, getScreenTransformationQuaternion(-90));
      } else {
        screenQuaternion = self->coreQuaternion; // no adjustment needed
      }

      // Adjust the screen quaternion for our 'real-world' viewport.
      // This is an adjustment of 90 degrees to the core reference frame.
      // This moves the reference from sitting flat on the table to a frame where
      // the user is holding looking 'through' the screen.
      self->worldQuaternion = quaternionMultiply(screenQuaternion, self->baseWorldQuaternion);
      
      // Extract heading from world quaternion before we apply any inverse reference offset
      double heading = computeYawEulerAngleFromQuaternion(self->worldQuaternion);
      
      // If we are using a inverse reference offset then apply the required transformation
      if (self->inverseReferenceInUse) {
        self->worldQuaternion = quaternionMultiply(self->inverseReferenceQuaternion, self->worldQuaternion);
      }
    
      // Extract the roll and pitch euler angles from the world quaternion
      double roll, pitch;
      computeRollPitchEulerAnglesFromQuaternion(self->worldQuaternion,  &roll, &pitch);
      
      // Send change events to the Javascript side via the React Native bridge
      @try {
        [self sendEventWithName:@"attitudeUpdate"
                           body:@{
                             @"timestamp" : @(currentTime),
                             @"roll" : @(roll),
                             @"pitch": @(pitch),
                             @"heading": @(heading),
                           }
         ];
      }
      @catch ( NSException *e ) {
        NSLog( @"Error sending event over the React bridge");
      }
      
      // Calculate the next time we should run
      self->nextSampleTime = currentTime + self->intervalMillis;
    };
    
    [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical toQueue:attitudeQueue withHandler:attitudeHandler];
  }
}

RCT_EXPORT_METHOD(stopObserving) {
  [motionManager stopDeviceMotionUpdates];
}

//------------------------------------------------------------------------------------------------
// Internal methods

#pragma mark - Private methods

CMQuaternion getScreenTransformationQuaternion(double screenOrientation) {
  const double orientationAngle = screenOrientation * DEGTORAD;
  const double minusHalfAngle = -orientationAngle / 2;
  CMQuaternion q_s;
  q_s.w = cos(minusHalfAngle);
  q_s.x = 0;
  q_s.y = 0;
  q_s.z = sin(minusHalfAngle);
  return q_s;
}

CMQuaternion getWorldTransformationQuaternion() {
  const double worldAngle = 90 * DEGTORAD;
  const double minusHalfAngle = -worldAngle / 2;
  CMQuaternion q_w;
  q_w.w = cos(minusHalfAngle);
  q_w.x = sin(minusHalfAngle);
  q_w.y = 0;
  q_w.z = 0;
  return q_w;
}

CMQuaternion quaternionMultiply(CMQuaternion a, CMQuaternion b) {
  CMQuaternion q;
  q.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
  q.x = a.x * b.w + a.w * b.x + a.y * b.z - a.z * b.y;
  q.y = a.y * b.w + a.w * b.y + a.z * b.x - a.x * b.z;
  q.z = a.z * b.w + a.w * b.z + a.x * b.y - a.y * b.x;
  return q;
}

// Calculates Euler angles from quaternion.
// See http://www.euclideanspace.com/maths/geometry/rotations/conversions/quaternionToEuler/
void computeRollPitchEulerAnglesFromQuaternion(CMQuaternion q, double *roll, double *pitch) {
  const double w2 = q.w * q.w;
  const double x2 = q.x * q.x;
  const double y2 = q.y * q.y;
  const double z2 = q.z * q.z;
  const double unitLength = w2 + x2 + y2 + z2; // Normalised == 1, otherwise correction divisor.
  const double abcd = q.w * q.x + q.y * q.z;
  const double eps = 1e-7f;
  if (abcd > (0.5f - eps) * unitLength)
  {
    // singularity at north pole
    *roll = 0.0f;
    *pitch = (double)M_PI;
  }
  else if (abcd < (-0.5f + eps) * unitLength)
  {
    // singularity at south pole
    *roll  = 0.0f;
    *pitch = (double)-M_PI;
  }
  else
  {
    const double acbd = q.w * q.y - q.x * q.z;
    *roll  = atan2(2.0f * acbd, 1.0f - 2.0f * (y2 + x2)) * RADTODEG;
    *pitch = asin(2.0f * abcd / unitLength) * RADTODEG;
  }
}

// Calculates the yaw (heading) euler angle only from a quaternion.
double computeYawEulerAngleFromQuaternion(CMQuaternion q) {
  const double x2 = q.x * q.x;
  const double z2 = q.z * q.z;
  const double adbc = q.w * q.z - q.x * q.y;
  double y = -atan2(2.0 * adbc, 1.0 - 2.0 * (z2 + x2)) * RADTODEG;
  if (y < 0) {
    y += 360;
  }
  return y;
}

@end



