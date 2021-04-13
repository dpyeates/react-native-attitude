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
  private static final byte W = 0;
  private static final byte X = 1;
  private static final byte Y = 2;
  private static final byte Z = 3;

  private final ReactApplicationContext mReactContext;
  private final Sensor mRotationSensor;
  private final SensorManager mSensorManager;
  private boolean mInverseReferenceInUse;
  private int mIntervalMillis;
  private long mNextSampleTime;
  private int rotation;

  private final float[] coreQuaternion = new float[4];
  private final float[] inverseReferenceQuaternion = new float[4];
  private final float[] baseWorldQuaternion;
  private float[] worldQuaternion = new float[4];

  public RNAttitudeModule(ReactApplicationContext reactContext) {
    super(reactContext);
    this.mReactContext = reactContext;
    this.mReactContext.addLifecycleEventListener(this);
    mSensorManager = (SensorManager) reactContext.getSystemService(Context.SENSOR_SERVICE);
    mRotationSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
    baseWorldQuaternion = getWorldTransformationQuaternion();
    mInverseReferenceInUse = false;
    mIntervalMillis = 200;
    mNextSampleTime = 0;
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
    mSensorManager.registerListener(this, mRotationSensor, mIntervalMillis * 1000);
  }

  @Override
  public void onHostPause() {
    mSensorManager.unregisterListener(this);
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
    promise.resolve(mRotationSensor != null);
  }

  @ReactMethod
  // Applies an inverse to core data and compensates for any non-zero installations.
  // Basically it makes a new 'zero' position for both pitch and roll.
  public void zero() {
    inverseReferenceQuaternion[W] = worldQuaternion[W];
    inverseReferenceQuaternion[X] = -worldQuaternion[X];
    inverseReferenceQuaternion[Y] = -worldQuaternion[Y];
    inverseReferenceQuaternion[Z] = -worldQuaternion[Z];
    mInverseReferenceInUse = true;
  }

  @ReactMethod
  // Resets the inverse quaternion in use and goes back to using the default 'zero' position
  public void reset() {
    mInverseReferenceInUse = false;
    inverseReferenceQuaternion[W] = 0;
    inverseReferenceQuaternion[X] = 0;
    inverseReferenceQuaternion[Y] = 0;
    inverseReferenceQuaternion[Z] = 0;
  }

  @ReactMethod
  // Sets the interval between event samples
  public void setInterval(int interval) {
    mIntervalMillis = interval;
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
    // reset any inverse rotation as any device rotation will render it incorrect
    if (mInverseReferenceInUse) {
      reset();
    }
  }

  @ReactMethod
  public void startObserving(Promise promise) {
    if (mRotationSensor == null) {
      promise.reject("-1", "Rotation vector sensor not available; will not provide orientation data.");
      return;
    }
    mNextSampleTime = 0;
    mSensorManager.registerListener(this, mRotationSensor, mIntervalMillis * 1000);
    promise.resolve(mIntervalMillis);
  }

  @ReactMethod
  public void stopObserving() {
    mSensorManager.unregisterListener(this);
  }

  //------------------------------------------------------------------------------------------------
  // Internal methods

  @Override
  public void onSensorChanged(SensorEvent sensorEvent) {
    // Time to run?
    long currentTime = SystemClock.elapsedRealtime();
    if (currentTime < mNextSampleTime) {
      return;
    }

    // Extract the quaternion
    SensorManager.getQuaternionFromVector(coreQuaternion, sensorEvent.values);

    // Adjust the core motion quaternion and heading result for left/right screen orientations
    float[] screenQuaternion;
    if (rotation == ROTATE_LEFT) {
      screenQuaternion = quaternionMultiply(coreQuaternion, getScreenTransformationQuaternion(90));
    } else if (rotation == ROTATE_RIGHT) {
      screenQuaternion = quaternionMultiply(coreQuaternion, getScreenTransformationQuaternion(-90));
    } else {
      screenQuaternion = coreQuaternion; // no adjustment needed
    }

    // Adjust the screen quaternion for our 'real-world' viewport.
    // This is an adjustment of 90 degrees to the core reference frame.
    // This moves the reference from sitting flat on the table to a frame where
    // the user is holding looking 'through' the screen.
    worldQuaternion = quaternionMultiply(screenQuaternion, baseWorldQuaternion);

    // Extract heading from world quaternion before we apply any inverse reference offset
    double heading = computeYawEulerAngleFromQuaternion(worldQuaternion);

    // If we are using a inverse reference offset then apply the required transformation
    if (mInverseReferenceInUse) {
      worldQuaternion = quaternionMultiply(inverseReferenceQuaternion, worldQuaternion);
    }

    // Extract the roll and pitch euler angles from the world quaternion
    double[] eulerAngles = computeRollPitchEulerAnglesFromQuaternion(worldQuaternion);

    // Send change events to the Javascript side via the React Native bridge
    WritableMap map = Arguments.createMap();
    map.putDouble("timestamp", sensorEvent.timestamp * NS2MS);
    map.putDouble("roll", eulerAngles[ROLL]);
    map.putDouble("pitch", eulerAngles[PITCH]);
    map.putDouble("heading", heading);
    try {
      mReactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class).emit("attitudeUpdate", map);
    } catch (RuntimeException e) {
      Log.e("ERROR", "Error sending event over the React bridge");
    }

    // Calculate the next time we should run
    mNextSampleTime = currentTime + mIntervalMillis;
  }

  private float[] getScreenTransformationQuaternion(float screenOrientation) {
    float orientationAngle = (float) Math.toRadians(screenOrientation);
    float minusHalfAngle = -orientationAngle / 2;
    float[] q_s = new float[4];
    q_s[W] = (float) Math.cos(minusHalfAngle);
    q_s[X] = 0;
    q_s[Y] = 0;
    q_s[Z] = (float) Math.sin(minusHalfAngle);
    return q_s;
  }

  private float[] getWorldTransformationQuaternion() {
    float worldAngle = (float) Math.toRadians(90.0);
    float minusHalfAngle = -worldAngle / 2;
    float[] q_w = new float[4];
    q_w[W] = (float) Math.cos(minusHalfAngle);
    q_w[X] = (float) Math.sin(minusHalfAngle);
    q_w[Y] = 0;
    q_w[Z] = 0;
    return q_w;
  }

  private float[] quaternionMultiply(float[] a, float[] b) {
    float[] q = new float[4];
    q[W] = a[W] * b[W] - a[X] * b[X] - a[Y] * b[Y] - a[Z] * b[Z];
    q[X] = a[X] * b[W] + a[W] * b[X] + a[Y] * b[Z] - a[Z] * b[Y];
    q[Y] = a[Y] * b[W] + a[W] * b[Y] + a[Z] * b[X] - a[X] * b[Z];
    q[Z] = a[Z] * b[W] + a[W] * b[Z] + a[X] * b[Y] - a[Y] * b[X];
    return q;
  }

  // Calculates the roll and pitch euler angles from quaternion.
  // See http://www.euclideanspace.com/maths/geometry/rotations/conversions/quaternionToEuler/
  private double[] computeRollPitchEulerAnglesFromQuaternion(float[] q) {
    double[] euler = new double[3];
    double w2 = q[W] * q[W];
    double x2 = q[X] * q[X];
    double y2 = q[Y] * q[Y];
    double z2 = q[Z] * q[Z];
    double unitLength = w2 + x2 + y2 + z2; // Normalised == 1, otherwise correction divisor.
    double abcd = q[W] * q[X] + q[Y] * q[Z];
    double eps = 1e-7;
    if (abcd > (0.5 - eps) * unitLength) {
      // singularity at north pole
      euler[ROLL] = 0.0;
      euler[PITCH] = Math.PI;
      euler[YAW] = 0; // calculated independently
    } else if (abcd < (-0.5 + eps) * unitLength) {
      // singularity at south pole
      euler[ROLL] = 0.0;
      euler[PITCH] = -Math.PI;
      euler[YAW] = 0; // calculated independently
    } else {
      double acbd = q[W] * q[Y] - q[X] * q[Z];
      euler[ROLL] = Math.toDegrees(Math.atan2(2.0 * acbd, 1.0 - 2.0 * (y2 + x2)));
      euler[PITCH] = Math.toDegrees(Math.asin(2.0 * abcd / unitLength));
      euler[YAW] = 0; // calculated independently
    }
    return euler;
  }

  // Calculates the yaw (heading) euler angle only from a quaternion.
  private double computeYawEulerAngleFromQuaternion(float[] q) {
    double x2 = q[X] * q[X];
    double z2 = q[Z] * q[Z];
    double adbc = q[W] * q[Z] - q[X] * q[Y];
    double y = Math.toDegrees(-Math.atan2(2.0 * adbc, 1.0 - 2.0 * (z2 + x2)));
    if (y < 0) {
      y += 360;
    }
    return y;
  }
}
