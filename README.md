  
# react-native-attitude

Provides Attitude (Roll, Pitch & Heading) in degrees for iOS and Android.
  
## Getting started

`yarn add react-native-attitude`

or

`npm install react-native-attitude --save`

### Mostly automatic installation (react-native 0.59 and lower)

`react-native link react-native-attitude`

### Manual installation (react-native 0.59 and lower)

<details>
<summary>Manually link the library on iOS</summary>

### `Open RNAttitude.xcodeproj in Xcode`

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
implementation project(':react-native-attitude')
}

```

#### `android/app/src/main/.../MainApplication.java`

On top, where imports are:

```java

import com.sensorworks.RNAttitudePackage;

```

Add the `RNAttitudePackage` class to your list of exported packages.

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

Since ****react-native 0.60**** and higher, [autolinking](https://github.com/react-native-community/cli/blob/master/docs/autolinking.md) makes the installation process simpler

## Usage

### Example
 
```javascript

import Attitude from 'react-native-attitude';

Attitude.watch((payload => {});

```

## Methods

### Summary

*  [`isSupported`](#issupported)

*  [`setInterval`](#setinterval)

*  [`zero`](#zero)

*  [`reset`](#reset)

*  [`watch`](#watch)

*  [`clearWatch`](#clearwatch)

*  [`stopObserving`](#stopobserving)

---

### Details

#### `isSupported()`

Before using, check to see if attitude updates are supported on the device.

```javascript

const isSupported = Attitude.isSupported();

```
---

#### `setInterval()`

Optionally request an update interval in ms. The default update rate is (approx) 40ms, i.e. 25Hz.

```javascript

// request updates once every second

Attitude.setInterval(1000);

```
---

#### `zero()`

Levels pitch and roll according to the current attitude. This can be used to null the device if it is oriented away from level.

```javascript

// level both pitch and roll 

Attitude.zero();

```
---

#### `reset()`

Resets any previous calls to `zero()`.

```javascript

Attitude.reset();

```
---

#### `watch()`

```javascript

Attitude.watch(success);

```
Invokes the success callback whenever the attitude changes. 
The payload delivered via the callback is defined in the example below.

Returns a `watchId` (number).

****Parameters:****

| Name  | Type | Required | Description |
| ------- | -------- | -------- | ----------------------------------------- |
| success | function | Yes  | Invoked at a default interval of 25hz This can be changed by using the setInterval method.  |

****Example:****

```javascript

const watchId = Attitude.watch((payload) =>{

/*

payload.timestamp - sample time in ms referenced to January 1, 1970 UTC

payload.roll - roll in degrees -180<-->180

payload.pitch - pitch in degrees -90<-->90

payload.heading - heading in degrees 0-->360

*/

);

```
---

#### `clearWatch()`

```javascript

Attitude.clearWatch(watchID);

```

****Parameters:****

| Name  | Type | Required | Description  |
| ------- | ------ | -------- | ------------------------------------ |
| watchID | number | Yes  | Id as returned by `watch()`. |
---

#### `stopObserving()`

```javascript

Attitude.stopObserving();

```

Stops observing for all attitude updates.

In addition, it removes all listeners previously registered.

Note that this method does nothing if the `Attitude.watch(successCallback)` method has not previously been called.

