# react-native-attitude

`react-native-attitude` provides real-time device orientation for React Native apps:

- **Roll** and **pitch** in degrees (for horizon/level style UIs)
- **Heading** in degrees (0-360)
- Configurable update rate: 1, 5, 10, 20, or 40 Hz; unchanged values are re-sent at 1 Hz minimum
- Runtime controls for `zero()` and `reset()` calibration

The module is designed for sensor-driven experiences such as camera overlays, horizon indicators, motion dashboards, and instrumentation UIs where low-latency orientation updates matter.

Version 3.x requires **React Native 0.82+** with the **New Architecture** enabled. It is implemented as a Turbo Module, using Core Motion + compass on iOS and the rotation vector sensor on Android.

## Install

```sh
npm install react-native-attitude
# or
yarn add react-native-attitude
```

Autolinking applies from RN 0.60+. Rebuild the native app after installing.

### iOS

Add to your app `Info.plist` when using heading:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Heading uses the device compass.</string>
```

When calling `requestMotionAuthorization()`, also add:

```xml
<key>NSMotionUsageDescription</key>
<string>Motion access is used to read device orientation.</string>
```

Then `cd ios && pod install`.

## Usage

```javascript
import Attitude from 'react-native-attitude';

const watchId = Attitude.watch((payload) => {
  // payload.timestamp — ms wall clock time
  // payload.roll      — degrees, -180 to 180, negative left wing down
  // payload.pitch     — degrees, -90 to 90, positive nose up
  // payload.heading   — degrees, 0 to 360
});

Attitude.setInterval(5);         // 1 | 5 | 10 | 20 | 40 (Hz)
Attitude.setRotation('auto');    // 'none' | 'left' | 'right' | 'upsidedown' | 'auto'
Attitude.setOutput('both');      // 'both' | 'attitude' | 'heading'
Attitude.zero();
Attitude.reset();
Attitude.clearWatch(watchId);
Attitude.stopObserving();

const authorized = await Attitude.requestMotionAuthorization();
// iOS: prompts for Motion & Fitness if needed; true when Authorized
// Android: always true (no OS dialog)
const supported = await Attitude.isSupported();
const sensors = await Attitude.getAvailableSensors();
// sensors[].id — accelerometer | gyroscope | magnetometer | rotationVector (Android)
//                 accelerometer | gyroscope | magnetometer | deviceMotion | heading (iOS)
```

### Rotation baseline

`setRotation()` tells the module which screen orientation is "level", so that pitch stays
nose up/down and roll stays wing left/right regardless of how the device is mounted:

- `'none'` — portrait (default)
- `'left'` / `'right'` — landscape, device rotated left/right from portrait
- `'upsidedown'` — portrait, upside down
- `'auto'` — track the current interface orientation natively and update the baseline
  whenever the screen rotates

`'auto'` is the recommended mode on iPadOS 26+ and Android 16+, where apps can no longer
force a fixed screen orientation on tablets: attitude output stays correct even if the OS
rotates the interface. Changing the baseline (including automatic changes in `'auto'` mode)
clears any offsets applied with `zero()`.

## Example app

```sh
cd example
npm install
cd ios && bundle exec pod install && cd ..
npm run android
# or
npm run ios
```

The example shows live roll/pitch/heading, an artificial horizon, controls for zero/reset plus update-rate presets (1/5/10/20/40 Hz), rotation baseline selection (none/left/right/upside down/auto), and the list from `getAvailableSensors()`.

## License

MIT
