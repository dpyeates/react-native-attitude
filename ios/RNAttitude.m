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

#define AXIS_X 1
#define AXIS_Y 2
#define AXIS_Z 3
#define AXIS_MINUS_X (AXIS_X | 0x80)
#define AXIS_MINUS_Y (AXIS_Y | 0x80)
#define AXIS_MINUS_Z (AXIS_Z | 0x80)


@implementation RNAttitude

RCT_EXPORT_MODULE();

- (id)init {
  self = [super init];
  if (self) {
    intervalMillis = (int)(1000 / UPDATERATEHZ);
    rotation = ROTATE_NONE;
    pitchOffset = 0;
    rollOffset = 0;
    
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
  self->pitchOffset = -self->pitch;
  self->rollOffset = -self->roll;
}

// Resets the pitch and roll offsets
RCT_EXPORT_METHOD(reset)
{
  self->pitchOffset = 0;
  self->rollOffset = 0;
}

// Sets the interval between event samples
RCT_EXPORT_METHOD(setInterval:(NSInteger)interval)
{
  self->intervalMillis = interval;
  bool shouldStart = motionManager.isDeviceMotionActive;
  [self stopObserving];
  [motionManager setDeviceMotionUpdateInterval:intervalMillis * 0.001];
  if(shouldStart) {
    [self startObserving];
  }
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
  [self reset];
}

RCT_EXPORT_METHOD(startObserving) {
  if(!motionManager.isDeviceMotionActive) {
    
    // the attitude update handler
    CMDeviceMotionHandler attitudeHandler = ^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
    {
      double rotationMatrix[9], remappedMatrix[9];
      
      // Get the current attitude values
      CMAttitude *currentAttitude = self->motionManager.deviceMotion.attitude;
      
      // convert to a float array rotation matrix
      CMRotationMatrixToFloatArray(currentAttitude.rotationMatrix, rotationMatrix);
      
      // Remap the coordinate system depending on screen orientation
      if (self->rotation == ROTATE_LEFT) {
        remapCoordinateSystem(rotationMatrix, AXIS_Z, AXIS_MINUS_X, remappedMatrix);
      } else if (self->rotation == ROTATE_RIGHT) {
        remapCoordinateSystem(rotationMatrix, AXIS_MINUS_Z, AXIS_X, remappedMatrix);
      } else {
        remapCoordinateSystem(rotationMatrix, AXIS_X, AXIS_Z, remappedMatrix);
      }
      
      // apply any pitch and roll offsets
      if(self->pitchOffset != 0 || self->rollOffset != 0) {
        double offsetMatrix1[9], offsetMatrix2[9];
        applyPitchOffset(self->pitchOffset, remappedMatrix, offsetMatrix1);
        applyRollOffset(self->rollOffset, offsetMatrix1, offsetMatrix2);
        getOrientation(offsetMatrix2, &self->pitch, &self->roll);
      }
      else {
        getOrientation(remappedMatrix, &self->pitch, &self->roll);
      }
      
      // Get the current heading
      if (@available(iOS 11.0, *)) {
        self->heading = self->motionManager.deviceMotion.heading;
      } else {
        self->heading = 0;
      }
      
      // Send change events to the Javascript side via the React Native bridge
      @try {
        [self sendEventWithName:@"attitudeUpdate"
                           body:@{
                             @"timestamp" : @((long long)([[NSDate date] timeIntervalSince1970] * 1000.0)),
                             @"roll" : @(self->roll),
                             @"pitch": @(self->pitch),
                             @"heading": @(self->heading),
                           }
         ];
      }
      @catch ( NSException *e ) {
        NSLog( @"Error sending event over the React bridge");
      }
    };
    
    [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical toQueue:attitudeQueue withHandler:attitudeHandler];
  }
}

RCT_EXPORT_METHOD(stopObserving) {
  if(motionManager.isDeviceMotionActive) {
    [motionManager stopDeviceMotionUpdates];
  }
}

//------------------------------------------------------------------------------------------------
// Internal methods

#pragma mark - Private methods

// Rotates the supplied rotation matrix so it is expressed in a different coordinate system.
void remapCoordinateSystem(double inR[], int X, int Y, double outR[]) {
  // Z is "the other" axis, its sign is either +/- sign(X)*sign(Y)
  // this can be calculated by exclusive-or'ing X and Y; except for
  // the sign inversion (+/-) which is calculated below.
  int Z = X ^ Y;
  // extract the axis (remove the sign), offset in the range 0 to 2.
  int x = (X & 0x3) - 1;
  int y = (Y & 0x3) - 1;
  int z = (Z & 0x3) - 1;
  // compute the sign of Z (whether it needs to be inverted)
  int axis_y = (z + 1) % 3;
  int axis_z = (z + 2) % 3;
  if (((x ^ axis_y) | (y ^ axis_z)) != 0) {
    Z ^= 0x80;
  }
  bool sx = (X >= 0x80);
  bool sy = (Y >= 0x80);
  bool sz = (Z >= 0x80);
  // Perform R * r, in avoiding actual muls and adds.
  for (int j = 0; j < 3; j++) {
    int offset = j * 3;
    for (int i = 0; i < 3; i++) {
      if (x == i) outR[offset + i] = sx ? -inR[offset + 0] : inR[offset + 0];
      if (y == i) outR[offset + i] = sy ? -inR[offset + 1] : inR[offset + 1];
      if (z == i) outR[offset + i] = sz ? -inR[offset + 2] : inR[offset + 2];
    }
  }
}

// Computes the device's orientation based on the rotation matrix.
// R should be double[9] array representing a rotation matrix
void getOrientation(double R[9], double *pitch, double *roll) {
  // /  R[ 0]   R[ 1]   R[ 2]  \
  // |  R[ 3]   R[ 4]   R[ 5]  |
  // \  R[ 6]   R[ 7]   R[ 8]  /
  *pitch = asin(R[7]) * RADTODEG;
  *roll = atan2(-R[6], R[8]) * RADTODEG;
}

// Apply a rotation about the roll axis to this rotation matrix.
// see http://planning.cs.uiuc.edu/node102.html
void applyRollOffset(double roll, double matrixIn[], double matrixOut[]) {
  double value = roll * DEGTORAD;
  double rotateMatrix[] = {
    cos(value), 0, sin(value),
    0, 1, 0,
    -sin(value), 0, cos(value)
  };
  matrixMultiply(matrixIn, rotateMatrix, matrixOut);
}

// Apply a rotation about the pitch axis to this rotation matrix.
// see http://planning.cs.uiuc.edu/node102.html
void applyPitchOffset(double pitch, double matrixIn[], double matrixOut[]) {
  double value = pitch * DEGTORAD;
  double rotateMatrix[] = {
    1, 0, 0,
    0, cos(value), -sin(value),
    0, sin(value), cos(value)
  };
  matrixMultiply(matrixIn, rotateMatrix, matrixOut);
}

// multiplies two rotation matrix, A and B
void matrixMultiply(double A[], double B[], double result[]) {
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

// converts a CMRotationMatrix to a basic double[9] array
void CMRotationMatrixToFloatArray(CMRotationMatrix rotIn, double rotOut[]) {
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

@end



