
# react-native-attitude

** UNDER DEVELOPMENT - DO NOT USE **

Provides Attitude (Roll, Pitch & Heading) in degrees for both iOS and Android.

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
import RNAttitude from 'react-native-attitude';

// TODO: What to do with the module?
RNAttitude;
```
