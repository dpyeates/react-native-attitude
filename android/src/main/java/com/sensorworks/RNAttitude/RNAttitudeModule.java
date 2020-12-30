package com.sensorworks.RNAttitude;

// FYI, nice article here: http://plaw.info/articles/sensorfusion/

import java.util.Arrays;

import android.os.SystemClock;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorManager;
import android.hardware.SensorEventListener;

import androidx.annotation.Nullable;

import android.view.WindowManager;
import android.view.Surface;
import android.util.Log;

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
public class RNAttitudeModule extends ReactContextBaseJavaModule implements LifecycleEventListener, SensorEventListener {
  public static final String NAME = "RNAttitude";
  private static final float NS2MS = 0.000001f;
  private static final byte ROLL = 2;
  private static final byte PITCH = 1;
  private static final byte YAW = 0;

  private final ReactApplicationContext mReactContext;

  @Nullable
  private Sensor mRotationSensor;
  private SensorManager mSensorManager;
  private WindowManager mWindowManager = null;
  private boolean mInverseReferenceInUse = false;
  private boolean mObserving = false;
  private int mIntervalMillis = 200;
  private long mNextSampleTime = 0;
  private float[] mRotationMatrix = new float[9];
  private float[] mRemappedRotationMatrix = new float[9];
  private float[] mRefAngles = new float[3];
  private float[] mInverseAngles = new float[3];

  public RNAttitudeModule(ReactApplicationContext reactContext) {
    super(reactContext);
    this.mReactContext = reactContext;
    this.mReactContext.addLifecycleEventListener(this);
    mSensorManager = (SensorManager) reactContext.getSystemService(reactContext.SENSOR_SERVICE);
    // mRotationSensor is set to null if the sensor hardware is not available on the device
    mRotationSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
  }

  @Override
  public String getName() {
    return NAME;
  }

  //------------------------------------------------------------------------------------------------
  // React interface

  @ReactMethod
  // Sets the interval between event samples
  public void setInterval(int interval) {
    mIntervalMillis = interval;
  }

  @ReactMethod
  // Determines if this device is capable of providing attitude updates - defaults to yes on IOS
  public void isSupported(Promise promise) {
    promise.resolve(mRotationSensor != null);
  }

  @ReactMethod
  // Zeros the current roll and pitch values as the reference attitude
  public void zero() {
    mInverseAngles = Arrays.copyOf(mRefAngles, 3);
    mInverseReferenceInUse = true;
  }

  @ReactMethod
  // Resets any in use reference attitudes and start using the baseline attitude reference
  public void reset() {
    mInverseReferenceInUse = false;
  }

  @ReactMethod
  // Starts observing pitch and roll
  public void startObserving(Promise promise) {
    if (mRotationSensor == null) {
      promise.reject("-1",
          "Rotation vector sensor not available; will not provide orientation data.");
      return;
    }
    if (mWindowManager == null) {
      mWindowManager = getCurrentActivity().getWindow().getWindowManager();
    }
    mSensorManager.registerListener(this, mRotationSensor, mIntervalMillis * 1000);
    mObserving = true;
    promise.resolve(mIntervalMillis);
  }

  @ReactMethod
  // Stops observing pitch and roll
  public void stopObserving() {
    mSensorManager.unregisterListener(this);
    mObserving = false;
    mLastPitch = mLastRoll = mLastYaw = mNextSampleTime = 0;
  }

  //------------------------------------------------------------------------------------------------
  // Internal methods

  @Override
  public void onSensorChanged(SensorEvent sensorEvent) {
    long currentTime = SystemClock.elapsedRealtime();
    if (currentTime < mNextSampleTime) {
      return;
    }

    SensorManager.getRotationMatrixFromVector(mRotationMatrix, getVectorFromSensorEvent(sensorEvent));

    // remap the axes as if the device screen was the instrument panel,
    // by adjusting the rotation matrix for the device/screen orientation.
    final int worldAxisForDeviceAxisX;
    final int worldAxisForDeviceAxisY;

    switch (mWindowManager.getDefaultDisplay().getRotation()) {
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

    SensorManager.remapCoordinateSystem(
        mRotationMatrix,
        worldAxisForDeviceAxisX,
        worldAxisForDeviceAxisY,
        mRemappedRotationMatrix
    );

    SensorManager.getOrientation(mRemappedRotationMatrix, mRefAngles);

    float[] angles;
    if(mInverseReferenceInUse) {
      angles = getInvertedAngles(mRefAngles, mInverseAngles);
    }
    else {
      angles = Arrays.copyOf(mRefAngles, 3);
    }

    // Convert radians to degrees, inverse correction needed for pitch to make 'up' positive
    double pitch = -Math.toDegrees(angles[PITCH]);
    double roll = Math.toDegrees(angles[ROLL]);
    double yaw = Math.toDegrees(angles[YAW]);

    // convert -180<-->180 yaw values to 0-->360
    yaw = yaw < 0 ? yaw + 360 : yaw;

    // Send change events to the Javascript side via the React Native bridge
    WritableMap map = Arguments.createMap();
    map.putDouble("timestamp", sensorEvent.timestamp * NS2MS);
    map.putDouble("roll", roll);
    map.putDouble("pitch", pitch);
    map.putDouble("heading", yaw);
    mReactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class).emit("attitudeUpdate", map);

    mNextSampleTime = currentTime + mIntervalMillis;
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
    if(a[ROLL] < -180) {
      a[ROLL] *= -1;
    }
    a[PITCH] = a[PITCH] - b[PITCH];
    if(a[PITCH] < -90) {
      a[PITCH] *= -1;
    }
    return a;
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {
  }

  @Override
  public void onHostResume() {
    if (mObserving) {
      mSensorManager.registerListener(this, mRotationSensor, mIntervalMillis * 1000);
    }
  }

  @Override
  public void onHostPause() {
    if (mObserving) {
      mSensorManager.unregisterListener(this);
    }
  }

  @Override
  public void onHostDestroy() {
    stopObserving();
  }
}