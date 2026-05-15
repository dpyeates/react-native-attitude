#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <RNAttitudeSpec/RNAttitudeSpec.h>

typedef NS_ENUM(NSUInteger, RNAttitudeOutput) {
  RNAttitudeOutputHeading,
  RNAttitudeOutputAttitude,
  RNAttitudeOutputBoth,
};

@interface RNAttitude : NativeRNAttitudeSpecBase <NativeRNAttitudeSpec, CLLocationManagerDelegate>

@end
