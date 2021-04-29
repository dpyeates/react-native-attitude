
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>

@interface RNAttitude : RCTEventEmitter <RCTBridgeModule> {
  // all angles are in degrees
  long intervalMillis;
  long rotation;
  double roll;
  double pitch;
  double pitchOffset;
  double rollOffset;
  double heading;
  CMMotionManager *motionManager;
  NSOperationQueue *attitudeQueue;
}

@end

