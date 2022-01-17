
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>

typedef NS_ENUM(NSUInteger, Output) {
  kHeading,
  kAttitude,
  kBoth
};

@interface RNAttitude : RCTEventEmitter <RCTBridgeModule> {
  // all angles are in degrees
  Boolean isRunning;
  long intervalMillis;
  long rotation;
  double roll;
  double pitch;
  double pitchOffset;
  double rollOffset;
  double heading;
  Output output;
  CLLocationManager *locationManager;
  CMMotionManager *motionManager;
  NSOperationQueue *attitudeQueue;
}

@end

