
# react-native-attitude

Provides Attitude (Roll, Pitch & Heading) in degrees for iOS. (Android in the future)

## Getting started

`$ npm install react-native-attitude --save`

### Mostly automatic installation

`$ react-native link react-native-attitude`

### Manual installation

#### iOS

1. In XCode, in the project navigator, right click `Libraries` ➜ `Add Files to [your project's name]`
2. Go to `node_modules` ➜ `react-native-attitude` and add `RNAttitude.xcodeproj`
3. In XCode, in the project navigator, select your project. Add `libRNAttitude.a` to your project's `Build Phases` ➜ `Link Binary With Libraries`
4. Run your project (`Cmd+R`)<

#### Android

1. Open up `android/app/src/main/java/[...]/MainActivity.java`
  - Add `import com.reactlibrary.RNAttitudePackage;` to the imports at the top of the file
  - Add `new RNAttitudePackage()` to the list returned by the `getPackages()` method
2. Append the following lines to `android/settings.gradle`:
  	```
  	include ':react-native-attitude'
  	project(':react-native-attitude').projectDir = new File(rootProject.projectDir, 	'../node_modules/react-native-attitude/android')
  	```
3. Insert the following lines inside the dependencies block in `android/app/build.gradle`:
  	```
      compile project(':react-native-attitude')
  	```
## Usage
```javascript
import {Attitude, Barometer} from 'react-native-attitude';
```

### Attitude (Pitch, Roll and Heading in degrees)
```js
attitudeWatchID = Attitude.watchAttitude((update) => {
    /**
     * update.roll (in degrees -180 (left) +180 (right))
     * update.pitch (in degrees  -90 (down) +90 (up))
    **/
    });
```
```js
Attitude.clearWatchAttitude(attitudeWatchID);
```
```js
headingWatchID = Attitude.watchHeading((update) => {
    /**
     * update.heading (in degrees 0-360 referenced to magnetic north)
    **/
    });
```
```js
Attitude.clearWatchHeading(headingWatchID);
```
```js
Attitude.stopObserving();
```

### Barometer/Altitude
```js
altitudeWatchID = Barometer.watch((update) => {
    /**
     * update.timeSinceLastUpdate (in seconds)
     * update.relativeAltitude (+/- deviation in m since the start of watch - will be 0 on start)
     * update.verticalSpeed (in metres per minute)
     * update.presure (current air pressure in millibars)
    **/
    });
```
```js
Barometer.clearWatch(altitudeWatchID);
```
```js
Barometer.stopObserving();
```
