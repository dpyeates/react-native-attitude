package com.sensorworks.RNAttitude;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorManager;
import android.hardware.SensorEventListener;

import androidx.annotation.Nullable;

import android.util.Log;
import android.view.WindowManager;
import android.view.Surface;

import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.BaseActivityEventListener;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.module.annotations.ReactModule;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.facebook.react.modules.core.RCTNativeAppEventEmitter;

@ReactModule(name = RNAttitudeModule.NAME)
public class RNAttitudeModule extends ReactContextBaseJavaModule implements SensorEventListener {
  public static final String NAME = "RNAttitude";
  private static final int SENSOR_DELAY_MICROS = 16 * 1000; // 16ms
  private static final float MOTIONTRIGGER = 0.25f;
  private static final float HEADINGTRIGGER = 0.5f;

  private final SensorManager mSensorManager;
  @Nullable
  private final Sensor mRotationSensor;

 // private final WindowManager mWindowManager;

  private final ReactApplicationContext reactContext;


  private double lastRollSent = Double.MAX_VALUE;
  private double lastPitchSent = Double.MAX_VALUE;
  private double lastYawSent = Double.MAX_VALUE;

  private int mLastAccuracy;

  private float[] referenceQuaternion = new float[4];

  private boolean inverseReferenceInUse = false;
  private float[] inverseReferenceQuaternion = new float[4];

  public RNAttitudeModule(ReactApplicationContext reactContext) {
    super(reactContext);
    this.reactContext = reactContext;
   // this.mWindowManager = getCurrentActivity().getWindow().getWindowManager();
    this.mSensorManager = (SensorManager) reactContext.getSystemService(reactContext.SENSOR_SERVICE);
    this.mRotationSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
  }

  @Override
  public String getName() {
    return NAME;
  }

  // React interface

  @ReactMethod
  public void startObserving() {
    mSensorManager.registerListener(this, mRotationSensor, SENSOR_DELAY_MICROS);
    Log.i(RNAttitudeModule.NAME, "RNAttitude has started updates");
  }

  @ReactMethod
  public void stopObserving() {
    mSensorManager.unregisterListener(this);
    Log.i(RNAttitudeModule.NAME, "RNAttitude has stopped updates");
    lastPitchSent = lastRollSent = lastYawSent = Double.MAX_VALUE;
  }

  @ReactMethod
  public void zero() {
    inverseReferenceQuaternion[3] = referenceQuaternion[3];
    inverseReferenceQuaternion[0] = -referenceQuaternion[0];
    inverseReferenceQuaternion[1] = -referenceQuaternion[1];
    inverseReferenceQuaternion[2] = -referenceQuaternion[2];
    inverseReferenceInUse = true;
    Log.i(RNAttitudeModule.NAME, "RNAttitude is taking a new reference attitude");
  }

  @ReactMethod
  public void reset() {
    inverseReferenceInUse = true;
    Log.i(RNAttitudeModule.NAME, "RNAttitude reference attitude reset to default");
  }

  // Internal methods

  @Override
  public void onSensorChanged(SensorEvent sensorEvent) {
    if (mLastAccuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) {
      return;
    }
    if (sensorEvent.sensor.getType() == Sensor.TYPE_ROTATION_VECTOR) {

      referenceQuaternion = sensorEvent.values.clone();
      float[] rotationMatrix = new float[9];

      // If we are using a pitch/roll reference 'offset' then apply the required transformation here.
      // This is doing the same as the built-in multiplyByInverseOfAttitude.
      if(inverseReferenceInUse) {
        SensorManager.getRotationMatrixFromVector(rotationMatrix, quaternionMultiply(inverseReferenceQuaternion, referenceQuaternion));
      }
      else {
        SensorManager.getRotationMatrixFromVector(rotationMatrix, referenceQuaternion);
      }

      final int worldAxisForDeviceAxisX;
      final int worldAxisForDeviceAxisY;

      // Remap the axes as if the device screen was the instrument panel,
      // and adjust the rotation matrix for the device orientation.
      switch (getCurrentActivity().getWindow().getWindowManager().getDefaultDisplay().getRotation()) {
        case Surface.ROTATION_0:
        default:
          worldAxisForDeviceAxisX = SensorManager.AXIS_X;
          worldAxisForDeviceAxisY = SensorManager.AXIS_Z;
          break;
        case Surface.ROTATION_90:
          worldAxisForDeviceAxisX = SensorManager.AXIS_Z;
          worldAxisForDeviceAxisY = SensorManager.AXIS_MINUS_X;
          break;
        case Surface.ROTATION_180:
          worldAxisForDeviceAxisX = SensorManager.AXIS_MINUS_X;
          worldAxisForDeviceAxisY = SensorManager.AXIS_MINUS_Z;
          break;
        case Surface.ROTATION_270:
          worldAxisForDeviceAxisX = SensorManager.AXIS_MINUS_Z;
          worldAxisForDeviceAxisY = SensorManager.AXIS_X;
          break;
      }

      float[] adjustedRotationMatrix = new float[9];
      SensorManager.remapCoordinateSystem(rotationMatrix, worldAxisForDeviceAxisX,
          worldAxisForDeviceAxisY, adjustedRotationMatrix);

      // Transform rotation matrix into azimuth/pitch/roll
      float[] orientation = new float[3];
      SensorManager.getOrientation(adjustedRotationMatrix, orientation);

      double pitch = Math.toDegrees(orientation[0]);
      double roll = Math.toDegrees(orientation[1]);
      double yaw = Math.toDegrees(orientation[2]);

      // Send change events to the Javascript side
      // To avoid flooding the bridge, we only send if data has significantly changed
      if ((lastRollSent == Double.MAX_VALUE || (roll > (lastRollSent + MOTIONTRIGGER) || roll < (lastRollSent - MOTIONTRIGGER))) ||
          (lastPitchSent == Double.MAX_VALUE || (pitch > (lastPitchSent + MOTIONTRIGGER) || pitch < (lastPitchSent - MOTIONTRIGGER))) ||
          (lastYawSent == Double.MAX_VALUE || (yaw > (lastYawSent + HEADINGTRIGGER) || yaw < (lastYawSent - HEADINGTRIGGER)))) {
        WritableMap map = Arguments.createMap();
        map.putDouble("roll", roll);
        map.putDouble("pitch", pitch);
        map.putDouble("heading", yaw);
        sendEvent("attitudeDidChange", map);
        lastRollSent = roll;
        lastPitchSent = pitch;
        lastYawSent = yaw;
      }
    }
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {
    if (mLastAccuracy != accuracy) {
      mLastAccuracy = accuracy;
    }
  }

  private void sendEvent(String eventName, @Nullable WritableMap params) {
    try {
      this.reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
          .emit(eventName, params);
    } catch (RuntimeException e) {
      Log.e("ERROR", "java.lang.RuntimeException: Trying to invoke Javascript before CatalystInstance has been set!");
    }
  }

  private float[] quaternionMultiply(float[] a, float[] b) {
    float[] q = new float[4];
    int w = 3;
    int x = 0;
    int y = 1;
    int z = 2;
    q[w] = a[w] * b[w] - a[x] * b[x] - a[y] * b[y] - a[z] * b[z];
    q[x] = a[x] * b[w] + a[w] * b[x] + a[y] * b[z] - a[z] * b[y];
    q[y] = a[y] * b[w] + a[w] * b[y] + a[z] * b[x] - a[x] * b[z];
    q[z] = a[z] * b[w] + a[w] * b[z] + a[x] * b[y] - a[y] * b[x];
    return q;
  }
}