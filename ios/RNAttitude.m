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

#define UPDATERATEHZ 25
#define DEGTORAD 0.017453292
#define RADTODEG 57.29577951
#define PITCHTRIGGER 0.5
#define ROLLTRIGGER 0.5
#define YAWTRIGGER 1.0

@implementation RNAttitude

RCT_EXPORT_MODULE();

- (id)init {
    self = [super init];
    if (self) {
        inverseReferenceInUse = false;
        intervalMillis = (int)(1000 / UPDATERATEHZ);
        lastHeading = 0;
        lastRoll = 0;
        lastPitch = 0;
        lastSampleTime = 0;
        
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

// Zeros the current roll and pitch values as the reference attitude
RCT_EXPORT_METHOD(zero)
{
    inverseReferenceQuaternion.w = quaternion.w;
    inverseReferenceQuaternion.x = -quaternion.x;
    inverseReferenceQuaternion.y = -quaternion.y;
    inverseReferenceQuaternion.z = -quaternion.z;
    inverseReferenceInUse = true;
}

// Resets any in use reference attitudes and start using the baseline attitude reference
RCT_EXPORT_METHOD(reset)
{
    inverseReferenceInUse = false;
}

// Sets the interval between event samples
RCT_EXPORT_METHOD(setInterval:(NSInteger)interval)
{
    intervalMillis = interval;
    [motionManager setDeviceMotionUpdateInterval:intervalMillis * 0.001];
}

// Starts observing pitch and roll
RCT_EXPORT_METHOD(startObserving) {
    if(!motionManager.isDeviceMotionActive) {
        // the attitude update handler
        CMDeviceMotionHandler attitudeHandler = ^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
        {
            long long tempMs = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
            long long timeSinceLastUpdate = (tempMs - lastSampleTime);
            if(timeSinceLastUpdate >= intervalMillis){
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
                // adjust roll and heading for orientation
                if(headingAdjustment != 0) {
                    heading = normalizeRange(heading + headingAdjustment, 1, 360);
                }
                if(rollAdjustment != 0) {
                    roll = normalizeRange(roll + rollAdjustment, -180, 180);
                }
                // Send change events to the Javascript side via the React Native bridge
                // To avoid flooding the bridge, we only send if the values have changed
                if ((pitch > (lastPitch + PITCHTRIGGER)) || (pitch < (lastPitch - PITCHTRIGGER)) ||
                     (roll > (lastRoll + ROLLTRIGGER)) || (roll < (lastRoll - ROLLTRIGGER)) ||
                     (heading > (lastHeading + YAWTRIGGER)) || (heading < (lastHeading - YAWTRIGGER))) {
                    [self sendEventWithName:@"attitudeUpdate"
                        body:@{
                            @"timestamp" : @(tempMs),
                            @"roll" : @(roll),
                            @"pitch": @(pitch),
                            @"heading": @(heading),
                        }
                    ];
                    lastRoll = roll;
                    lastPitch = pitch;
                    lastHeading = heading;
                }
                lastSampleTime = tempMs;
            }
        };
        
        [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical toQueue:attitudeQueue withHandler:attitudeHandler];
    }
}

// Stops observing pitch and roll
RCT_EXPORT_METHOD(stopObserving) {
    [motionManager stopDeviceMotionUpdates];
    lastSampleTime = lastHeading = lastRoll = lastPitch = 0;
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

