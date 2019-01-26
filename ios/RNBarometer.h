#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreMotion/CoreMotion.h>

@interface RNBarometer : RCTEventEmitter <RCTBridgeModule> {
    CMAltimeter *_altimeter;
    NSOperationQueue *_altimeterQueue;
    bool _isAltimeterActive;
    bool _hasAltitudeListeners;
    float _lastPressure;
    double _lastPressureTime;
}

- (void) isAvailableWithResolver:(RCTPromiseResolveBlock) resolve
                        rejecter:(RCTPromiseRejectBlock) reject;

@end

  
