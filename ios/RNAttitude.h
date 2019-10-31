
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>

@interface RNAttitude : RCTEventEmitter <RCTBridgeModule> {
    // all angles are in degrees
    // speed in metres per second
    // altitude in metres
    // pressure in millibars
    bool inverseReferenceInUse;
    bool observing;
    long long lastSampleTime;
    int intervalMillis;
    float roll;
    float pitch;
    float yaw;
    float heading;
    float lastHeading;
    float lastRoll;
    float lastPitch;
    CMQuaternion quaternion;
    CMQuaternion inverseReferenceQuaternion;
    CMMotionManager *motionManager;
    NSOperationQueue *attitudeQueue;
}

@end
  
