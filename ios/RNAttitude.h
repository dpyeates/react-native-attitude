
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>

@interface RNAttitude : RCTEventEmitter <RCTBridgeModule> {
  // all angles are in degrees
  bool inverseReferenceInUse;
  long long nextSampleTime;
  long intervalMillis;
  long rotation;
  CMQuaternion coreQuaternion;
  CMQuaternion worldQuaternion;
  CMQuaternion baseWorldQuaternion;
  CMQuaternion inverseReferenceQuaternion;
  CMMotionManager *motionManager;
  NSOperationQueue *attitudeQueue;
}

@end
  
