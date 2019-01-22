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
#define MOTIONTRIGGER 0.25
#define PRESSURETRIGGER 0.0366 // approx 1ft


@implementation RNAttitude
{
    // all angles are in degrees
    // speed in metres per second
    // altitude in metres
    // pressure in millibars
    bool hasAttitudeListeners;
    bool hasHeadingListeners;
    bool hasAltitudeListeners;
    bool inverseReferenceInUse;
    bool isAltimeterActive;
    float roll;
    float pitch;
    float yaw;
    float heading;
    float refPitch;
    float refRoll;
    float lastHeadingSent;
    float lastRollSent;
    float lastPitchSent;
    float lastPressure;
    double lastTime;
    CMQuaternion quaternion;
    CMQuaternion inverseReferenceQuaternion;
    CMMotionManager *motionManager;
    CMAltimeter *altimeterManager;
    NSOperationQueue *attitudeQueue;
    NSOperationQueue *altimeterQueue;
}

// To export a module named RNAttitude
RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"attitudeDidChange", @"headingDidChange", @"altitudeDidChange"];
}

- (id)init {
    self = [super init];
    if (self) {
        altimeterManager = 0;
        hasAttitudeListeners = false;
        hasHeadingListeners = false;
        hasAltitudeListeners = false;
        isAltimeterActive = false;
        lastHeadingSent = FLT_MAX;
        lastRollSent = FLT_MAX;
        lastPitchSent = FLT_MAX;
        lastPressure = FLT_MAX;
        lastTime = 0;
        inverseReferenceInUse = false;
        refPitch = 0;
        refRoll = 0;
        
        // Allocate and initialize the motion manager.
        motionManager = [[CMMotionManager alloc] init];
        [motionManager setShowsDeviceMovementDisplay:YES];
        [motionManager setDeviceMotionUpdateInterval:1.0/30];
       
        // Allocate and initialize the operation queue for attitude updates.
        attitudeQueue = [[NSOperationQueue alloc] init];
        [attitudeQueue setName:@"DeviceMotion"];
        [attitudeQueue setMaxConcurrentOperationCount:1];
        
        // Allocate and initialize the altimeter if available on this device
        if ([CMAltimeter isRelativeAltitudeAvailable]) {
            altimeterManager = [[CMAltimeter alloc] init];
            
            // Allocate and initialize the operation queue for altitude updates.
            altimeterQueue = [[NSOperationQueue alloc] init];
            [altimeterQueue setName:@"DeviceAltitude"];
            [altimeterQueue setMaxConcurrentOperationCount:1];
        }
    }
    return self;
}

#pragma mark - Public API

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

// Called when we have a new altitude listener
RCT_EXPORT_METHOD(startObservingAltitude) {
    if (altimeterManager) {
        hasAltitudeListeners = YES;
        [self configure];
    }
}

// Called when we have are removing the last altitude listener
RCT_EXPORT_METHOD(stopObservingAltitude) {
     if (altimeterManager) {
         hasAltitudeListeners = NO;
         lastPressure = FLT_MAX;
         lastTime = DBL_MAX;
         [self configure];
     }
}

// Will be called when this module's last listener is removed, or on dealloc.
RCT_EXPORT_METHOD(stopObserving) {
     [motionManager stopDeviceMotionUpdates];
     if (altimeterManager) {
         [altimeterManager stopRelativeAltitudeUpdates];
     }
     hasAttitudeListeners = NO;
     hasHeadingListeners = NO;
     hasAltitudeListeners = NO;
     isAltimeterActive = false;
     lastHeadingSent = FLT_MAX;
     lastRollSent = FLT_MAX;
     lastPitchSent = FLT_MAX;
     lastPressure = FLT_MAX;
     lastTime = DBL_MAX;
     RCTLogInfo(@"RNAttitude has stopped all attitude, heading and altitude updates");
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

// Called to indicate if this device offers barometric altitude updates
RCT_REMAP_METHOD(hasBarometer,
                 hasBarometerWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if (altimeterManager) {
        resolve([NSNumber numberWithBool:true]);
    } else {
        resolve([NSNumber numberWithBool:false]);
    }
}

// Called to reset any in use reference attitudes and start using the baseline attitude reference
RCT_EXPORT_METHOD(reset)
{
    inverseReferenceInUse = false;
    RCTLogInfo(@"RNAttitude reference attitude reset");
}

#pragma mark - Private API

// Kicks off the motion processing
-(void)configure
{
    // the attitude update handler
    CMDeviceMotionHandler attitudeHandler = ^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error)
    {
        //UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
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
            if((lastRollSent == FLT_MAX || (roll > (lastRollSent+MOTIONTRIGGER) || roll < (lastRollSent-MOTIONTRIGGER))) ||
               (lastPitchSent == FLT_MAX || (pitch > (lastPitchSent+MOTIONTRIGGER) || pitch < (lastPitchSent-MOTIONTRIGGER)))) {
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
            if(lastHeadingSent == FLT_MAX || (heading > (lastHeadingSent+MOTIONTRIGGER) || heading < (lastHeadingSent-MOTIONTRIGGER))) {
                [self sendEventWithName:@"headingDidChange" body:@{@"heading": @(heading)}];
                lastHeadingSent = heading;
            }
        }
    };
    
    // the altimeter update handler
    CMAltitudeHandler altimeterHandler = ^(CMAltitudeData *altitudeData, NSError *error) {
        long relativeAltitude = altitudeData.relativeAltitude.longValue;
        float pressure = altitudeData.pressure.doubleValue * 10.0; // the x10 converts to millibar
        double currentTime = [[NSDate date] timeIntervalSince1970];
        double timeSinceLastUpdate = (currentTime - lastTime);
        float verticalSpeed = 0;
        // calculate vertical speed
        if(lastPressure != FLT_MAX && lastTime != DBL_MAX) {
            verticalSpeed = (getAltitude(lastPressure) - getAltitude(pressure)) / timeSinceLastUpdate;
        }
        // is any one listening? We don't want to send over the bridge if not.
        if(hasAltitudeListeners) {
            [self sendEventWithName:@"altitudeDidChange" body:@{
                                                                @"timeSinceLastUpdate": @(timeSinceLastUpdate),
                                                                @"relativeAltitude": @(relativeAltitude),
                                                                @"verticalSpeed": @(verticalSpeed),
                                                                @"pressure": @(pressure)
                                                            }
             ];
        }
        lastPressure = pressure;
        lastTime = currentTime;
    };
    
    if((hasAttitudeListeners || hasHeadingListeners) && !motionManager.isDeviceMotionActive) {
        [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical toQueue:attitudeQueue withHandler:attitudeHandler];
        RCTLogInfo(@"RNAttitude has started DeviceMotion updates");
    }
    else if((!hasHeadingListeners && !hasAttitudeListeners) && motionManager.isDeviceMotionActive) {
        [motionManager stopDeviceMotionUpdates];
        RCTLogInfo(@"RNAttitude has stopped DeviceMotion updates");
    }
    
    if(altimeterManager && hasAltitudeListeners && !isAltimeterActive) {
        isAltimeterActive = true;
        [altimeterManager startRelativeAltitudeUpdatesToQueue:altimeterQueue withHandler:altimeterHandler];
        RCTLogInfo(@"RNAttitude has started Altimeter updates");
    }
    else if(altimeterManager && !hasAltitudeListeners && isAltimeterActive) {
        [altimeterManager stopRelativeAltitudeUpdates];
        isAltimeterActive = false;
        RCTLogInfo(@"RNAttitude has stopped Altimeter updates");
    }
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

// limits a value between a maximum and minimum
float normalizeRange(float val, float min, float max) {
    const float step = max - min;
    while(val >= max) val -= step;
    while(val < min) val += step;
    return val;
}

// Computes the Altitude in meters from the atmospheric pressure and the pressure at sea level.
// p0 pressure at sea level
// p atmospheric pressure
// returns an altitude in meters
float getAltitude(float p) {
    const float p0 = 1013.25;
    const float coef = 1.0f / 5.255;
    return 44330.0 * (1.0 - pow(p / p0, coef));
}

@end

