// RNAttitude.m
//
// Useful info:
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

#define UPDATERATEHZ 30
#define DEGTORAD 0.017453292
#define RADTODEG 57.29577951
#define MOTIONTRIGGER 0.25
#define HEADINGTRIGGER 0.5

@implementation RNAttitude

RCT_EXPORT_MODULE();

- (id)init {
    self = [super init];
    if (self) {
        // configure default values
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
        [motionManager setDeviceMotionUpdateInterval:1.0/UPDATERATEHZ];
       
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

#pragma mark - React event emitter

// the supported events that the Javascript side can subscribe to
- (NSArray<NSString *> *)supportedEvents
{
    return @[@"attitudeDidChange", @"headingDidChange"];
}

#pragma mark - React bridge methods

// Called when we have a new heading listener
RCT_EXPORT_METHOD(startObservingHeading) {
    hasHeadingListeners = YES;
    [self configure];
}

// Called when we have are removing the last heading listener
RCT_EXPORT_METHOD(stopObservingHeading) {
    hasHeadingListeners = NO;
    lastHeadingSent = FLT_MAX;
    [self configure];
}

// Called when we have a new attitude listener
RCT_EXPORT_METHOD(startObservingAttitude) {
    hasAttitudeListeners = YES;
    [self configure];
}

// Called when we have are removing the last attitude listener
RCT_EXPORT_METHOD(stopObservingAttitude) {
    hasAttitudeListeners = NO;
    lastRollSent = FLT_MAX;
    lastPitchSent = FLT_MAX;
    [self configure];
}

// Called when this module's last listener is removed, or on dealloc.
RCT_EXPORT_METHOD(stopObserving) {
     [motionManager stopDeviceMotionUpdates];
     hasAttitudeListeners = NO;
     hasHeadingListeners = NO;
     lastHeadingSent = FLT_MAX;
     lastRollSent = FLT_MAX;
     lastPitchSent = FLT_MAX;
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
    RCTLogInfo(@"RNAttitude reference attitude reset to default");
}

#pragma mark - The main configuration method

-(void)configure
{
    // the attitude update handler
    CMDeviceMotionHandler attitudeHandler = ^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
    {
        // get the current device orientation
        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
        
        // setup the 'default' heading and roll adjustment for portrait orientation
        int headingAdjustment = 0;
        int rollAdjustment = 0;
        
        // adjust if we are holding the device in either of the landscape orientations
        if(orientation == UIInterfaceOrientationLandscapeLeft) {
            headingAdjustment = -90;
            rollAdjustment = -90;
        }
        else if(orientation == UIInterfaceOrientationLandscapeRight) {
            headingAdjustment = 90;
            rollAdjustment = 90;
        }
        
        // Get the core IOS device motion quaternion and heading values (requires iOS 11 or above)
        CMQuaternion q = [[motion attitude] quaternion];
        double heading = 0;
        if (@available(iOS 11.0, *)) {
            heading = [motion heading];
        }
        
        // Create a quaternion representing an adjustment of 90 degrees to the core IOS
        // reference frame. This moves it from the reference being sitting flat on
        // the table to a frame where the user is holding looking 'through' the screen.
        quaternion = quaternionMultiply(q, getWorldTransformationQuaternion());
        
        // If we are using a pitch/roll reference 'offset' then apply the required transformation here.
        // This is doing the same as the built-in multiplyByInverseOfAttitude.
        if(inverseReferenceInUse) {
            CMQuaternion qRef = quaternionMultiply(inverseReferenceQuaternion, quaternion);
            computeEulerAnglesFromQuaternion(qRef, &roll, &pitch, &yaw);
        }
        else {
            computeEulerAnglesFromQuaternion(quaternion, &roll, &pitch, &yaw);
        }
        
        //RCTLogInfo(@"RNAttitude heading = %d, %d", (int)heading, headingAdjustment);
        
        // adjust roll and heading for orientation
        if(headingAdjustment != 0) {
            heading = normalizeRange(heading + headingAdjustment, 1, 360);
        }
        
        if(rollAdjustment != 0) {
            roll = normalizeRange(roll + rollAdjustment, -180, 180);
        }
        
        // Send change events to the Javascript side
        // To avoid flooding the bridge, we only send if we have listeners, and the data has significantly changed
        if(hasAttitudeListeners) {
            if((lastRollSent == FLT_MAX || (roll > (lastRollSent + MOTIONTRIGGER) || roll < (lastRollSent - MOTIONTRIGGER))) ||
               (lastPitchSent == FLT_MAX || (pitch > (lastPitchSent + MOTIONTRIGGER) || pitch < (lastPitchSent - MOTIONTRIGGER)))) {
                [self sendEventWithName:@"attitudeDidChange"
                                   body:@{
                                          @"attitude": @{
                                                  @"roll" : @(roll),
                                                  @"pitch": @(pitch),
                                                  }
                                          }
                 ];
                lastRollSent = roll;
                lastPitchSent = pitch;
            }
        }
        if(hasHeadingListeners) {
            if(lastHeadingSent == FLT_MAX || (heading > (lastHeadingSent + HEADINGTRIGGER) || heading < (lastHeadingSent - HEADINGTRIGGER))) {
                [self sendEventWithName:@"headingDidChange" body:@{@"heading": @(heading)}];
                lastHeadingSent = heading;
            }
        }
    };

    
    if((hasAttitudeListeners || hasHeadingListeners) && !motionManager.isDeviceMotionActive) {
        [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical toQueue:attitudeQueue withHandler:attitudeHandler];
        RCTLogInfo(@"RNAttitude has started DeviceMotion updates");
    }
    else if((!hasHeadingListeners && !hasAttitudeListeners) && motionManager.isDeviceMotionActive) {
        [motionManager stopDeviceMotionUpdates];
        RCTLogInfo(@"RNAttitude has stopped DeviceMotion updates");
    }

}

#pragma mark - Private methods

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

// limits a value between a maximum and minimum
float normalizeRange(float val, float min, float max) {
    const float step = max - min;
    while(val >= max) val -= step;
    while(val < min) val += step;
    return val;
}

@end

