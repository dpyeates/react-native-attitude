package com.sensorworks.RNAttitude;

// FYI, nice article here: http://plaw.info/articles/sensorfusion/

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
  private static final float PITCHTRIGGER = 0.5f;
  private static final float ROLLTRIGGER = 0.5f;
  private static final float YAWTRIGGER = 1.0f;
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
  private int mIntervalMillis = 40;
  private long mLastSampleTime;
  private float[] mRotationMatrix = new float[9];
  private float[] mRemappedRotationMatrix = new float[9];
  private float[] mAngles = new float[3];
  private double mLastRoll = 0;
  private double mLastPitch = 0;
  private double mLastYaw = 0;

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
    //inverseReferenceQuaternion[3] = referenceQuaternion[3];
    //inverseReferenceQuaternion[0] = -referenceQuaternion[0];
    //inverseReferenceQuaternion[1] = -referenceQuaternion[1];
    //inverseReferenceQuaternion[2] = -referenceQuaternion[2];
    mInverseReferenceInUse = true;
    Log.i(RNAttitudeModule.NAME, "RNAttitude is taking a new reference attitude");
  }

  @ReactMethod
  // Resets any in use reference attitudes and start using the baseline attitude reference
  public void reset() {
    mInverseReferenceInUse = false;
    Log.i(RNAttitudeModule.NAME, "RNAttitude reference attitude reset to default");
  }

  @ReactMethod
  // Starts observing pitch and roll
  public void startObserving(Promise promise) {
    if (mRotationSensor == null) {
      promise.reject("-1",
          "Rotation vector sensor not available; will not provide orientation data.");
      return;
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
    mLastPitch = mLastRoll = mLastYaw = 0;
  }

  //------------------------------------------------------------------------------------------------
  // Internal methods

  @Override
  public void onSensorChanged(SensorEvent sensorEvent) {
    long tempMs = System.currentTimeMillis();
    long timeSinceLastUpdate = tempMs - mLastSampleTime;
    if (timeSinceLastUpdate >= mIntervalMillis) {
      final int worldAxisForDeviceAxisX;
      final int worldAxisForDeviceAxisY;

      Log.i(RNAttitudeModule.NAME, "UPDATE");

      // convert latest values from rotation vectors into matrix
      SensorManager.getRotationMatrixFromVector(mRotationMatrix, sensorEvent.values);

      if (mWindowManager == null) {
        mWindowManager = getCurrentActivity().getWindow().getWindowManager();
      }

      // remap the axes as if the device screen was the instrument panel,
      // by adjusting the rotation matrix for the device/screen orientation.
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
      SensorManager.remapCoordinateSystem(mRotationMatrix, worldAxisForDeviceAxisX,
          worldAxisForDeviceAxisY, mRemappedRotationMatrix);

      // Transform rotation matrix into azimuth/pitch/roll
      SensorManager.getOrientation(mRemappedRotationMatrix, mAngles);

      // Convert radians to degrees, inverse correction needed for pitch to make 'up' positive
      double pitch = -Math.toDegrees(mAngles[PITCH]);
      double roll = Math.toDegrees(mAngles[ROLL]);
      double yaw = Math.toDegrees(mAngles[YAW]);

      // convert -180<-->180 yaw values to 0-->360
      yaw = yaw < 0 ? yaw + 360 : yaw;

      // Send change events to the Javascript side via the React Native bridge
      // To avoid flooding the bridge, we only send if the values have changed
      if ((pitch > (mLastPitch + PITCHTRIGGER)) || (pitch < (mLastPitch - PITCHTRIGGER)) ||
          (roll > (mLastRoll + ROLLTRIGGER)) || (roll < (mLastRoll - ROLLTRIGGER)) ||
          (yaw > (mLastYaw + YAWTRIGGER)) || (yaw < (mLastYaw - YAWTRIGGER))) {
        WritableMap map = Arguments.createMap();
        map.putDouble("timestamp", tempMs);
        map.putDouble("roll", roll);
        map.putDouble("pitch", pitch);
        map.putDouble("heading", yaw);
        try {
          mReactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
              .emit("attitudeDidChange", map);
        } catch (RuntimeException e) {
          Log.e("ERROR", "Error sending event over the React bridge");
        }

        Log.i(RNAttitudeModule.NAME, "roll = " + roll + ", pitch = " + pitch + ", yaw = " + yaw);

        mLastPitch = pitch;
        mLastRoll = roll;
        mLastYaw = yaw;
        mLastSampleTime = tempMs;
      }
    }
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {
  }

  @Override
  public void onHostResume() {
    if(mObserving) {
      mSensorManager.registerListener(this, mRotationSensor, mIntervalMillis * 1000);
    }
  }

  @Override
  public void onHostPause() {
    if(mObserving) {
      mSensorManager.unregisterListener(this);
    }
  }

  @Override
  public void onHostDestroy() {
    stopObserving();
  }
}