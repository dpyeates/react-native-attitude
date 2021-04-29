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

  private static final byte ROTATE_NONE = 0;
  private static final byte ROTATE_LEFT = 1;
  private static final byte ROTATE_RIGHT = 2;

  private final ReactApplicationContext reactContext;
  private final Sensor rotationSensor;
  private final SensorManager sensorManager;
  private int intervalMillis;
  private long nextSampleTime;
  private long rotation;
  private boolean isRunning;
  private float pitchOffset;
  private float rollOffset;
  private float[] eulerAngles = new float[2];

  public RNAttitudeModule(ReactApplicationContext reactContext) {
    super(reactContext);
    this.reactContext = reactContext;
    this.reactContext.addLifecycleEventListener(this);
    sensorManager = (SensorManager) reactContext.getSystemService(Context.SENSOR_SERVICE);
    rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
    isRunning = false;
    intervalMillis = 200;
    nextSampleTime = 0;
    rotation = ROTATE_NONE;
    pitchOffset = 0;
    rollOffset = 0;
  }

  @Override
  public String getName() {
    return NAME;
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {}

  @Override
  public void onHostResume() {
    if(isRunning) {
      sensorManager.registerListener(this, rotationSensor, intervalMillis * 1000);
    }
  }

  @Override
  public void onHostPause() {
    if(isRunning) {
      sensorManager.unregisterListener(this);
    }
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
    pitchOffset = -eulerAngles[0];
    rollOffset = -eulerAngles[1];
  }

  @ReactMethod
  // Resets the pitch and roll offsets
  public void reset() {
    pitchOffset = 0;
    rollOffset = 0;
  }

  @ReactMethod
  // Sets the interval between event samples
  public void setInterval(int interval) {
    intervalMillis = interval;
    boolean shouldStart = isRunning;
    stopObserving();
    if(shouldStart) {
      startObserving(null);
    }
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
    reset();
  }

  @ReactMethod
  public void startObserving(Promise promise) {
    if (rotationSensor == null) {
      promise.reject("-1", "Rotation vector sensor not available; will not provide orientation data.");
      return;
    }
    nextSampleTime = 0;
    sensorManager.registerListener(this, rotationSensor, intervalMillis * 1000);
    isRunning = true;
    if(promise != null) {
      promise.resolve(intervalMillis);
    }
  }

  @ReactMethod
  public void stopObserving() {
    sensorManager.unregisterListener(this);
    isRunning = false;
  }

  //------------------------------------------------------------------------------------------------
  // Internal methods

  @Override
  public void onSensorChanged(SensorEvent sensorEvent) {
    float[] rotationMatrix = new float[9];
    float[] remappedMatrix = new float[9];
    float[] orientation = new float[3];

    // Time to run?
    long currentTime = SystemClock.elapsedRealtime();
    if (currentTime < nextSampleTime) {
      return;
    }

    // Get the current attitude value as a rotation matrix
    SensorManager.getRotationMatrixFromVector(rotationMatrix, getVectorFromSensorEvent(sensorEvent));

    // Remap the coordinate system depending on screen orientation
    if (rotation == ROTATE_LEFT) {
      SensorManager.remapCoordinateSystem(rotationMatrix, SensorManager.AXIS_Z, SensorManager.AXIS_MINUS_X, remappedMatrix);
    } else if (rotation == ROTATE_RIGHT) {
      SensorManager.remapCoordinateSystem(rotationMatrix, SensorManager.AXIS_MINUS_Z, SensorManager.AXIS_X, remappedMatrix);
    } else {
      SensorManager.remapCoordinateSystem(rotationMatrix, SensorManager.AXIS_X, SensorManager.AXIS_Z, remappedMatrix);
    }

    float heading = (float) (((((Math.toDegrees(SensorManager.getOrientation(remappedMatrix, orientation)[0]) + 360) % 360) -
        (Math.toDegrees(SensorManager.getOrientation(remappedMatrix, orientation)[2]))) + 360) % 360);

    // apply any pitch and roll offsets
    if(pitchOffset != 0 || rollOffset != 0) {
      float[] offsetMatrix = applyPitchOffset(pitchOffset, remappedMatrix);
      offsetMatrix = applyRollOffset(rollOffset, offsetMatrix);
      eulerAngles = getOrientation(offsetMatrix);
    }
    else {
      eulerAngles = getOrientation(remappedMatrix);
    }

    WritableMap map = Arguments.createMap();
    map.putDouble("timestamp", sensorEvent.timestamp * NS2MS);
    map.putDouble("roll", eulerAngles[1]);
    map.putDouble("pitch", eulerAngles[0]);
    map.putDouble("heading", heading);
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

  // Rotates the supplied rotation matrix so it is expressed in a different coordinate system.
  private float[] remapCoordinateSystem(float[] inR, int X, int Y) {
    float[] outR = new float[9];
    // Z is "the other" axis, its sign is either +/- sign(X)*sign(Y)
    // this can be calculated by exclusive-or'ing X and Y; except for
    // the sign inversion (+/-) which is calculated below.
    int Z = X ^ Y;
    // extract the axis (remove the sign), offset in the range 0 to 2.
    int x = (X & 0x3) - 1;
    int y = (Y & 0x3) - 1;
    int z = (Z & 0x3) - 1;
    // compute the sign of Z (whether it needs to be inverted)
    int axis_y = (z + 1) % 3;
    int axis_z = (z + 2) % 3;
    if (((x ^ axis_y) | (y ^ axis_z)) != 0) {
      Z ^= 0x80;
    }
    boolean sx = (X >= 0x80);
    boolean sy = (Y >= 0x80);
    boolean sz = (Z >= 0x80);
    // Perform R * r, in avoiding actual muls and adds.
    for (int j = 0; j < 3; j++) {
      int offset = j * 3;
      for (int i = 0; i < 3; i++) {
        if (x == i) outR[offset + i] = sx ? -inR[offset + 0] : inR[offset + 0];
        if (y == i) outR[offset + i] = sy ? -inR[offset + 1] : inR[offset + 1];
        if (z == i) outR[offset + i] = sz ? -inR[offset + 2] : inR[offset + 2];
      }
    }
    return outR;
  }

  // Computes the device's orientation based on the rotation matrix.
  // R should be double[9] array representing a rotation matrix
  private float[] getOrientation(float[] R) {
    // /  R[ 0]   R[ 1]   R[ 2]  \
    // |  R[ 3]   R[ 4]   R[ 5]  |
    // \  R[ 6]   R[ 7]   R[ 8]  /
    float[] out = new float[2];
    out[0] = (float) Math.toDegrees(Math.asin(R[7])); // pitch
    out[1] = (float) Math.toDegrees(Math.atan2(-R[6], R[8])); // roll
    return out;
  }

  // Apply a rotation about the roll axis to this rotation matrix.
  // see http://planning.cs.uiuc.edu/node102.html
  private float[] applyRollOffset(float roll, float[] matrixIn) {
    float value = (float) Math.toRadians(roll);
    float[] rotateMatrix = {
        (float) Math.cos(value), 0, (float) Math.sin(value),
        0, 1, 0,
        (float) -Math.sin(value), 0, (float) Math.cos(value)
    };
    return matrixMultiply(matrixIn, rotateMatrix);
  }

  // Apply a rotation about the pitch axis to this rotation matrix.
  // see http://planning.cs.uiuc.edu/node102.html
  private float[] applyPitchOffset(float pitch, float[] matrixIn) {
    float value = (float) Math.toRadians(pitch);
    float[] rotateMatrix = {
        1, 0, 0,
        0, (float) Math.cos(value), (float) -Math.sin(value),
        0, (float) Math.sin(value), (float) Math.cos(value)
    };
    return matrixMultiply(matrixIn, rotateMatrix);
  }

  // multiplies two rotation matrix, A and B
  private float[] matrixMultiply(float[] A, float[] B) {
    float[] result = new float[9];;
    result[0] = A[0] * B[0] + A[1] * B[3] + A[2] * B[6];
    result[1] = A[0] * B[1] + A[1] * B[4] + A[2] * B[7];
    result[2] = A[0] * B[2] + A[1] * B[5] + A[2] * B[8];
    result[3] = A[3] * B[0] + A[4] * B[3] + A[5] * B[6];
    result[4] = A[3] * B[1] + A[4] * B[4] + A[5] * B[7];
    result[5] = A[3] * B[2] + A[4] * B[5] + A[5] * B[8];
    result[6] = A[6] * B[0] + A[7] * B[3] + A[8] * B[6];
    result[7] = A[6] * B[1] + A[7] * B[4] + A[8] * B[7];
    result[8] = A[6] * B[2] + A[7] * B[5] + A[8] * B[8];
    return result;
  }

}
