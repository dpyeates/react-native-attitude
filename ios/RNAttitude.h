
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>

@interface RNAttitude : RCTEventEmitter <RCTBridgeModule> {
    // all angles are in degrees
    // speed in metres per second
    // altitude in metres
    // pressure in millibars
    bool hasAttitudeListeners;
    bool hasHeadingListeners;
    bool inverseReferenceInUse;
    float roll;
    float pitch;
    float yaw;
    float heading;
    float refPitch;
    float refRoll;
    float lastHeadingSent;
    float lastRollSent;
    float lastPitchSent;
    CMQuaternion quaternion;
    CMQuaternion inverseReferenceQuaternion;
    CMMotionManager *motionManager;
    NSOperationQueue *attitudeQueue;
}

@end
  
