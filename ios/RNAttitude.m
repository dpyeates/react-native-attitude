// RNAttitude.m
//
// Useful info:
// https://dev.opera.com/articles/w3c-device-orientation-usage/
// http://bediyap.com/programming/convert-quaternion-to-euler-rotations/
// https://stackoverflow.com/questions/19239482/using-quaternion-instead-of-roll-pitch-and-yaw-to-track-device-motion
// https://stackoverflow.com/questions/11103683/euler-angle-to-quaternion-then-quaternion-to-euler-angle
// https://stackoverflow.com/questions/14482518/how-multiplybyinverseofattitude-cmattitude-class-is-implemented
#import "RNAttitude.h"

#import <React/RCTAssert.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>

#import <CoreMotion/CoreMotion.h>

#define DEGTORAD 0.017453292
#define RADTODEG 57.29577951
#define TRIGGER 0.25

@implementation RNAttitude
{
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
    NSOperationQueue *operationQueue;
}

// To export a module named RNAttitude
RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"attitudeDidChange", @"headingDidChange"];
}

- (id)init {
    self = [super init];
    if (self) {
        hasAttitudeListeners = false;
        hasHeadingListeners = false;
        lastHeadingSent = FLT_MAX;
        lastRollSent = FLT_MAX;
        lastPitchSent = FLT_MAX;
        inverseReferenceInUse = false;
        refPitch = 0;
        refRoll = 0;
        // Allocate and initialize the motion manager.
        motionManager = [[CMMotionManager alloc] init];
        [motionManager setShowsDeviceMovementDisplay:YES];
        [motionManager setDeviceMotionUpdateInterval:1.0/30];
        // Allocate and initialize the operation queue.
        operationQueue = [[NSOperationQueue alloc] init];
        [operationQueue setName:@"DeviceMotion"];
        [operationQueue setMaxConcurrentOperationCount:1];
    }
    return self;
}

#pragma mark - Public API

// Called when we have a new heading listener
RCT_EXPORT_METHOD(startObservingHeading) {
    hasHeadingListeners = YES;
    if(!motionManager.isDeviceMotionActive) {
        [self start];
    }
    RCTLogInfo(@"RNAttitude has started heading updates");
}

// Called when we have a new attitude listener
RCT_EXPORT_METHOD(startObservingAttitude) {
    hasAttitudeListeners = YES;
    if(!motionManager.isDeviceMotionActive) {
        [self start];
    }
    RCTLogInfo(@"RNAttitude has started attitude updates");
}

// Called when we have are removing the last heading listener
RCT_EXPORT_METHOD(stopObservingHeading) {
    hasHeadingListeners = NO;
    if(!hasAttitudeListeners && motionManager.isDeviceMotionActive) {
        [self stop];
    }
    RCTLogInfo(@"RNAttitude has stopped heading updates");
}

// Called when we have are removing the last attitude listener
RCT_EXPORT_METHOD(stopAttitudeHeading) {
    hasAttitudeListeners = NO;
    if(!hasHeadingListeners && motionManager.isDeviceMotionActive) {
        [self stop];
    }
    RCTLogInfo(@"RNAttitude has stopped attitude updates");
}

// Will be called when this module's last listener is removed, or on dealloc.
RCT_EXPORT_METHOD(stopObserving) {
    hasAttitudeListeners = NO;
    hasHeadingListeners = NO;
    if(motionManager.isDeviceMotionActive) {
        [self stop];
    }
    RCTLogInfo(@"RNAttitude has stopped all attitude and heading updates");
}

// Called to zero the current roll and pitch values as the reference attitude
RCT_EXPORT_METHOD(zero)
{
    inverseReferenceQuaternion.w = quaternion.w;
    inverseReferenceQuaternion.x = -quaternion.x;
    inverseReferenceQuaternion.y = -quaternion.y;
    inverseReferenceQuaternion.z = -quaternion.z;
    inverseReferenceInUse = true;
    RCTLogInfo(@"RNAttitude is taking a new reference attitude");
}

// Called to reset any in use reference attitudes and start using the baseline attitude reference
RCT_EXPORT_METHOD(reset)
{
    inverseReferenceInUse = false;
    RCTLogInfo(@"RNAttitude reference attitude reset");
}

#pragma mark - Private API

// Kicks off the motion processing
-(void)start
{
    CMDeviceMotionHandler handler = ^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
    {
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        int headingAdjustment = -90;
        int rollAdjustment = 0;
        if(orientation == UIInterfaceOrientationLandscapeLeft) {
            headingAdjustment = -180;
            rollAdjustment = -90;
        }
        else if(orientation == UIInterfaceOrientationLandscapeRight) {
            headingAdjustment = 180;
            rollAdjustment = 90;
        }
        // Get the core IOS device motion quaternion
        CMQuaternion q = [[motion attitude] quaternion];
        // Create a quaternion representing an adjustment of 90 degrees to the core IOS
        // reference frame. This moves it from the reference being sitting flat on
        // the table to a frame where the user is holding looking 'through' the screen.
        quaternion = quaternionMultiply(q, getWorldTransformationQuaternion());
        // If we are using a pitch/roll reference 'offset' then apply the required
        // transformation here. This is doing the same as the built-in multiplyByInverseOfAttitude.
        if(inverseReferenceInUse) {
            CMQuaternion qRef = quaternionMultiply(inverseReferenceQuaternion, quaternion);
            computeEulerAnglesFromQuaternion(qRef, &roll, &pitch, &yaw);
        }
        else {
            computeEulerAnglesFromQuaternion(quaternion, &roll, &pitch, &yaw);
        }
        // calculate a 0-360 heading based upon -180<->180 yaw
        heading = 360 - normalizeRange(yaw, 1, 360);
        // adjust roll and heading for orientation
        heading = normalizeRange(heading + headingAdjustment, 1, 360);
        roll = normalizeRange(roll + rollAdjustment, -180, 180);
        // Send change events to the Javascript side
        // To avoid flooding the bridge, we only send if we have listeners, and the data has significantly changed
        if(hasAttitudeListeners) {
            if((lastRollSent == FLT_MAX || (roll > (lastRollSent+TRIGGER) || roll < (lastRollSent-TRIGGER))) ||
               (lastPitchSent == FLT_MAX || (pitch > (lastPitchSent+TRIGGER) || pitch < (lastPitchSent-TRIGGER)))) {
                [self sendEventWithName:@"attitudeDidChange"
                                   body:@{
                                          @"attitude": @{
                                                  @"roll" : @(roll),
                                                  @"pitch": @(pitch),
                                                  @"yaw"  : @(yaw),
                                                  }
                                          }
                 ];
                lastRollSent = roll;
                lastPitchSent = pitch;
            }
        }
        if(hasHeadingListeners) {
            if(lastHeadingSent == FLT_MAX || (heading > (lastHeadingSent+TRIGGER) || heading < (lastHeadingSent-TRIGGER))) {
                [self sendEventWithName:@"headingDidChange" body:@{@"heading": @(heading)}];
                lastHeadingSent = heading;
            }
        }
    };
    
    // Start motion updates.
    [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical toQueue:operationQueue withHandler:handler];
}

-(void)stop
{
    [motionManager stopDeviceMotionUpdates];
}

CMQuaternion getWorldTransformationQuaternion() {
    const float worldAngle = 90 * DEGTORAD;
    const float minusHalfAngle = -worldAngle / 2;
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

CMQuaternion getScreenTransformationQuaternion(float screenOrientation) {
    const float orientationAngle = screenOrientation * DEGTORAD;
    const float minusHalfAngle = -orientationAngle / 2;
    CMQuaternion q_s;
    q_s.w = cos(minusHalfAngle);
    q_s.x = 0;
    q_s.y = 0;
    q_s.z = sin(minusHalfAngle);
    return q_s;
}

// Calculates Euler angles from quaternion.
// See http://www.euclideanspace.com/maths/geometry/rotations/conversions/quaternionToEuler/
void computeEulerAnglesFromQuaternion(CMQuaternion q, float *roll, float *pitch, float *yaw) {
    const float w2 = q.w * q.w;
    const float x2 = q.x * q.x;
    const float y2 = q.y * q.y;
    const float z2 = q.z * q.z;
    const float unitLength = w2 + x2 + y2 + z2; // Normalised == 1, otherwise correction divisor.
    const float abcd = q.w * q.x + q.y * q.z;
    const float eps = 1e-7f;
    if (abcd > (0.5f - eps) * unitLength)
    {
        // singularity at north pole
        *roll = 0.0f;
        *pitch = (float)M_PI;
        *yaw = 2.0f * atan2f(q.y, q.w);
    }
    else if (abcd < (-0.5f + eps) * unitLength)
    {
        // singularity at south pole
        *roll  = 0.0f;
        *pitch = (float)-M_PI;
        *yaw   = -2.0f * atan2(q.y, q.w);
    }
    else
    {
        const float adbc = q.w * q.z - q.x * q.y;
        const float acbd = q.w * q.y - q.x * q.z;
        *roll  = atan2f(2.0f * acbd, 1.0f - 2.0f * (y2 + x2)) * RADTODEG;
        *pitch = asinf(2.0f * abcd / unitLength) * RADTODEG;
        *yaw   = atan2f(2.0f * adbc, 1.0f - 2.0f * (z2 + x2)) * RADTODEG;
    }
}

float normalizeRange(float val, float min, float max) {
    const float step = max - min;
    while(val >= max) val -= step;
    while(val < min) val += step;
    return val;
}

@end

