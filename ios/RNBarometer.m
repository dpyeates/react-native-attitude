// Barometer.m
#import "RNBarometer.h"

#import <React/RCTAssert.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>

@implementation RNBarometer

RCT_EXPORT_MODULE();

- (id) init {
    self = [super init];
    if (self) {
        self->_altimeter = [[CMAltimeter alloc] init];
        self->_altimeterQueue = [[NSOperationQueue alloc] init];
        [self->_altimeterQueue setName:@"DeviceAltitude"];
        [self->_altimeterQueue setMaxConcurrentOperationCount:1];
        self->_lastPressure = FLT_MAX;
        self->_lastPressureTime = DBL_MAX;
        self->_isAltimeterActive = false;
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"barometerUpdate"];
}

// Called when we have a new listener
RCT_EXPORT_METHOD(startObserving) {
   self->_hasAltitudeListeners = YES;
   if(!self->_isAltimeterActive) {
       [self->_altimeter startRelativeAltitudeUpdatesToQueue:self->_altimeterQueue withHandler:^(CMAltitudeData * _Nullable altitudeData, NSError * _Nullable error) {
           if (error) {
               NSLog(@"error while getting sensor data");
           }
           if (altitudeData) {
               long relativeAltitude = altitudeData.relativeAltitude.longValue;
               float pressure = altitudeData.pressure.doubleValue * 10.0; // the x10 converts to millibar
               double currentTime = [[NSDate date] timeIntervalSince1970];
               double timeSinceLastUpdate = (currentTime - self->_lastPressureTime);
               float verticalSpeed = 0;
               // calculate vertical speed
               if(self->_lastPressure != FLT_MAX && self->_lastPressureTime != DBL_MAX) {
                   float altLast = getAltitude(self->_lastPressure);
                   float altNow = getAltitude(pressure);
                   verticalSpeed = ((altNow - altLast) / timeSinceLastUpdate) * 60;
               }
               [self sendEventWithName:@"barometerUpdate" body:@{
                                                                @"timeSinceLastUpdate": @(timeSinceLastUpdate),
                                                                @"relativeAltitude": @(relativeAltitude),
                                                                @"verticalSpeed": @(verticalSpeed),
                                                                @"pressure": @(pressure)
                                                                }
                ];
               self->_lastPressure = pressure;
               self->_lastPressureTime = currentTime;
           }
       }];
       self->_isAltimeterActive = true;
       RCTLogInfo(@"RNBarometer has started barometer updates");
   }
}

// Called when we have are removing the last altitude listener
RCT_EXPORT_METHOD(stopObserving) {
     [self->_altimeter stopRelativeAltitudeUpdates];
     self->_lastPressure = FLT_MAX;
     self->_lastPressureTime = DBL_MAX;
     RCTLogInfo(@"RNBarometer has stopped barometer updates");
}

RCT_REMAP_METHOD(isAvailable,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    return [self isAvailableWithResolver:resolve
                                rejecter:reject];
}

- (void) isAvailableWithResolver:(RCTPromiseResolveBlock) resolve
                        rejecter:(RCTPromiseRejectBlock) reject {
    resolve([CMAltimeter isRelativeAltitudeAvailable] ? @YES : @NO);
}

// Computes the Altitude in meters from the atmospheric pressure and the pressure at sea level.
// p0 pressure at sea level
// p atmospheric pressure
// returns an altitude in meters
float getAltitude(float pressure) {
    const float p0 = 1013.25;
    const float coef = 1.0f / 5.255;
    return 44330.0 * (1.0 - pow(pressure / p0, coef));
}

@end

