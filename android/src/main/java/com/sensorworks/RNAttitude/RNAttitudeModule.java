// Useful info:
// http://plaw.info/articles/sensorfusion/
// https://dev.opera.com/articles/w3c-device-orientation-usage/
// http://bediyap.com/programming/convert-quaternion-to-euler-rotations/
// https://stackoverflow.com/questions/19239482/using-quaternion-instead-of-roll-pitch-and-yaw-to-track-device-motion
// https://stackoverflow.com/questions/11103683/euler-angle-to-quaternion-then-quaternion-to-euler-angle
// https://stackoverflow.com/questions/14482518/how-multiplybyinverseofattitude-cmattitude-class-is-implemented
// https://stackoverflow.com/questions/5782658/extracting-yaw-from-a-quaternion
package com.sensorworks.RNAttitude;

import android.content.Context;
import android.os.SystemClock;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorManager;
import android.hardware.SensorEventListener;
import android.util.Log;

import java.util.Arrays;

import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.BaseActivityEventListener;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.Callback;
import com.facebook.react.module.annotations.ReactModule;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.facebook.react.modules.core.RCTNativeAppEventEmitter;

@ReactModule(name = RNAttitudeModule.NAME)
public class RNAttitudeModule extends ReactContextBaseJavaModule implements LifecycleEventListener,
    SensorEventListener {
  public static final String NAME = "RNAttitude";
  private static final double NS2MS = 0.000001;
  private static final byte YAW = 0;
  private static final byte PITCH = 1;
  private static final byte ROLL = 2;
  private static final byte ROTATE_NONE = 0;
  private static final byte ROTATE_LEFT = 1;
  private static final byte ROTATE_RIGHT = 2;

  private final ReactApplicationContext reactContext;
  private final Sensor rotationSensor;
  private final SensorManager sensorManager;
  private boolean inverseReferenceInUse;
  private int intervalMillis;
  private long nextSampleTime;
  private int rotation;
  private float[] inverseAngles = new float[3];
  private final float[] refAngles = new float[3];

  public RNAttitudeModule(ReactApplicationContext reactContext) {
    super(reactContext);
    this.reactContext = reactContext;
    this.reactContext.addLifecycleEventListener(this);
    sensorManager = (SensorManager) reactContext.getSystemService(Context.SENSOR_SERVICE);
    rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
    inverseReferenceInUse = false;
    intervalMillis = 200;
    nextSampleTime = 0;
    rotation = ROTATE_NONE;
  }

  @Override
  public String getName() {
    return NAME;
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {}

  @Override
  public void onHostResume() {
    sensorManager.registerListener(this, rotationSensor, intervalMillis * 1000);
  }

  @Override
  public void onHostPause() {
    sensorManager.unregisterListener(this);
  }

  @Override
  public void onHostDestroy() {
    stopObserving();
  }

  //------------------------------------------------------------------------------------------------
  // React interface

  @ReactMethod
  // Determines if this device is capable of providing attitude updates
  public void isSupported(Promise promise) {
    promise.resolve(rotationSensor != null);
  }

  @ReactMethod
  // Applies an inverse to core data and compensates for any non-zero installations.
  // Basically it makes a new 'zero' position for both pitch and roll.
  public void zero() {
    inverseAngles = Arrays.copyOf(refAngles, 3);
    inverseReferenceInUse = true;
  }

  @ReactMethod
  // Resets the inverse quaternion in use and goes back to using the default 'zero' position
  public void reset() {
    inverseReferenceInUse = false;
  }

  @ReactMethod
  // Sets the interval between event samples
  public void setInterval(int interval) {
    intervalMillis = interval;
  }

  @ReactMethod
  // Sets the device rotation to either 'none', 'left' or 'right'
  // If this isn't called then we assume 'portrait'/no rotation orientation
  public void setRotation(String rotation) {
    String lowercaseRotation = rotation.toLowerCase();
    switch (lowercaseRotation) {
      case "none":
        this.rotation = ROTATE_NONE;
        break;
      case "left":
        this.rotation = ROTATE_LEFT;
        break;
      case "right":
        this.rotation = ROTATE_RIGHT;
        break;
      default:
        Log.e("ERROR", "Unrecognised rotation passed to react-native-attitude, must be 'none','left' or 'right' only");
        break;
    }
  }

  @ReactMethod
  public void startObserving(Promise promise) {
    if (rotationSensor == null) {
      promise.reject("-1", "Rotation vector sensor not available; will not provide orientation data.");
      return;
    }
    nextSampleTime = 0;
    sensorManager.registerListener(this, rotationSensor, intervalMillis * 1000);
    promise.resolve(intervalMillis);
  }

  @ReactMethod
  public void stopObserving() {
    sensorManager.unregisterListener(this);
  }

  //------------------------------------------------------------------------------------------------
  // Internal methods

  @Override
  public void onSensorChanged(SensorEvent sensorEvent) {
    float[] rotationMatrix = new float[9];
    float[] remappedRotationMatrix = new float[9];

    // Time to run?
    long currentTime = SystemClock.elapsedRealtime();
    if (currentTime < nextSampleTime) {
      return;
    }

    SensorManager.getRotationMatrixFromVector(rotationMatrix, getVectorFromSensorEvent(sensorEvent));

    if (rotation == ROTATE_LEFT) {
      SensorManager.remapCoordinateSystem(rotationMatrix, SensorManager.AXIS_Z, SensorManager.AXIS_MINUS_X, remappedRotationMatrix);
    } else if (rotation == ROTATE_RIGHT) {
      SensorManager.remapCoordinateSystem(rotationMatrix, SensorManager.AXIS_MINUS_Z, SensorManager.AXIS_X, remappedRotationMatrix);
    } else {
      SensorManager.remapCoordinateSystem(rotationMatrix, SensorManager.AXIS_X, SensorManager.AXIS_Z, remappedRotationMatrix);
    }

    SensorManager.getOrientation(remappedRotationMatrix, refAngles);

    float[] eulerAngles;
    if (inverseReferenceInUse) {
      eulerAngles = getInvertedAngles(refAngles, inverseAngles);
    }
    else {
      eulerAngles = Arrays.copyOf(refAngles, 3);
    }

    // Convert radians to degrees, inverse correction needed for pitch to make 'up' positive
    eulerAngles[PITCH] = (float)-Math.toDegrees(eulerAngles[PITCH]);
    eulerAngles[ROLL] = (float)Math.toDegrees(eulerAngles[ROLL]);
    eulerAngles[YAW] = (float)Math.toDegrees(eulerAngles[YAW]);

    // Convert -180<-->180 yaw values to 0-->360
    eulerAngles[YAW] = eulerAngles[YAW] < 0 ? eulerAngles[YAW] + 360 : eulerAngles[YAW];

    WritableMap map = Arguments.createMap();
    map.putDouble("timestamp", sensorEvent.timestamp * NS2MS);
    map.putDouble("roll", eulerAngles[ROLL]);
    map.putDouble("pitch", eulerAngles[PITCH]);
    map.putDouble("heading", eulerAngles[YAW]);
    try {
      reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class).emit("attitudeUpdate", map);
    } catch (RuntimeException e) {
      Log.e("ERROR", "Error sending event over the React bridge");
    }

    // Calculate the next time we should run
    nextSampleTime = currentTime + intervalMillis;
  }

  private float[] getVectorFromSensorEvent(SensorEvent event) {
    if (event.values.length > 4) {
      // On some Samsung devices SensorManager.getRotationMatrixFromVector
      // appears to throw an exception if rotation vector has length > 4.
      // For the purposes of this class the first 4 values of the
      // rotation vector are sufficient (see crbug.com/335298 for details).
      // Only affects Android 4.3
      return Arrays.copyOf(event.values, 4);
    } else {
      return event.values;
    }
  }

  private float[] getInvertedAngles(float[] a, float[] b) {
    a[ROLL] = a[ROLL] - b[ROLL];
    if (a[ROLL] < -180) {
      a[ROLL] *= -1;
    }
    a[PITCH] = a[PITCH] - b[PITCH];
    if (a[PITCH] < -90) {
      a[PITCH] *= -1;
    }
    return a;
  }

}
