
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>

@interface RNAttitude : RCTEventEmitter <RCTBridgeModule> {
    // all angles are in degrees
    bool inverseReferenceInUse;
    bool observing;
    long long lastSampleTime;
    long intervalMillis;
    float roll;
    float pitch;
    float yaw;
    float heading;
    CMQuaternion quaternion;
    CMQuaternion inverseReferenceQuaternion;
    CMMotionManager *motionManager;
    NSOperationQueue *attitudeQueue;
}

@end
  
