
# react-native-attitude

Provides Attitude (Roll, Pitch & Heading) in degrees for iOS. (Android in the future)

## Getting started

`yarn add react-native-attitude`

or

`npm install react-native-attitude --save`

### Mostly automatic installation (react-native 0.59 and lower)

`react-native link react-native-attitude`

### Manual installation (react-native 0.59 and lower)

<details>
<summary>Manually link the library on iOS</summary>

### `Open project.xcodeproj in Xcode`

Drag `RNAttitude.xcodeproj` to your project on Xcode (usually under the Libraries group on Xcode):

![xcode-add](https://facebook.github.io/react-native/docs/assets/AddToLibraries.png)

### Link `libRNAttitude.a` binary with libraries

Click on your main project file (the one that represents the `.xcodeproj`) select `Build Phases` and drag the static library from the `Products` folder inside the Library you are importing to `Link Binary With Libraries` (or use the `+` sign and choose library from the list):

![xcode-link](https://facebook.github.io/react-native/docs/assets/AddToBuildPhases.png)

### Using CocoaPods

Update your `Podfile`

```
pod 'react-native-attitude', path: '../node_modules/react-native-attitude'
```

</details>

<details>
<summary>Manually link the library on Android</summary>

#### `android/settings.gradle`
```groovy
include ':react-native-attitude'
project(':react-native-attitude').projectDir = new File(rootProject.projectDir, '../node_modules/react-native-attitude/android')
```

#### `android/app/build.gradle`
```groovy
dependencies {
   ...
   implementation project(':react-native-community-geolocation')
}
```

#### `android/app/src/main/.../MainApplication.java`
On top, where imports are:

```java
import com.sensorworks.RNAttitudePackage;
```

Add the `GeolocationPackage` class to your list of exported packages.

```java
@Override
protected List<ReactPackage> getPackages() {
    return Arrays.asList(
            new MainReactPackage(),
            new RNAttitudePackage()
    );
}
```
</details>

Since **react-native 0.60** and higher, [autolinking](https://github.com/react-native-community/cli/blob/master/docs/autolinking.md) makes the installation process simpler

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
     * update.pressure (current air pressure in millibars)
    **/
    });
```
```js
Barometer.clearWatch(altitudeWatchID);
```
```js
Barometer.stopObserving();
```
