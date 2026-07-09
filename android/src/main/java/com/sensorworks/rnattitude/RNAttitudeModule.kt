package com.sensorworks.rnattitude

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.round
import kotlin.math.sin

class RNAttitudeModule(reactContext: ReactApplicationContext) :
  NativeRNAttitudeSpec(reactContext), LifecycleEventListener, SensorEventListener {

  private val sensorManager: SensorManager =
    reactContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
  private val rotationSensor: Sensor? =
    sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

  private var intervalMillis = 200
  private var nextSampleTime = 0L
  private var lastEmitTimeMs = 0L
  private var rotation = ROTATE_NONE
  private var output = OUTPUT_BOTH
  private var isRunning = false
  private var pitchOffset = 0f
  private var rollOffset = 0f
  private var headingLast = 0f
  private val eulerAngles = FloatArray(2)
  private val eulerAnglesLast = FloatArray(2)
  private val rotationMatrix = FloatArray(9)
  private val remappedMatrix = FloatArray(9)
  private val orientation = FloatArray(3)
  private val pitchAdjustedMatrix = FloatArray(9)
  private val rollAdjustedMatrix = FloatArray(9)

  init {
    reactContext.addLifecycleEventListener(this)
  }

  override fun getName(): String = NAME

  override fun isSupported(promise: Promise) {
    promise.resolve(rotationSensor != null)
  }

  override fun getAvailableSensors(promise: Promise) {
    val types =
      listOf(
        Sensor.TYPE_ACCELEROMETER to "accelerometer",
        Sensor.TYPE_GYROSCOPE to "gyroscope",
        Sensor.TYPE_MAGNETIC_FIELD to "magnetometer",
        Sensor.TYPE_ROTATION_VECTOR to "rotationVector",
      )
    val result = Arguments.createArray()
    for ((type, id) in types) {
      for (sensor in sensorManager.getSensorList(type)) {
        val map = Arguments.createMap()
        map.putString("id", id)
        map.putString("name", sensor.name)
        map.putString("vendor", sensor.vendor)
        map.putDouble("version", sensor.version.toDouble())
        map.putDouble("maxRange", sensor.maximumRange.toDouble())
        map.putDouble("resolution", sensor.resolution.toDouble())
        map.putDouble("minDelayUs", sensor.minDelay.toDouble())
        result.pushMap(map)
      }
    }
    promise.resolve(result)
  }

  override fun zero() {
    pitchOffset = -eulerAngles[0]
    rollOffset = -eulerAngles[1]
  }

  override fun reset() {
    pitchOffset = 0f
    rollOffset = 0f
  }

  override fun setOutput(outputIn: String) {
    val shouldStart = isRunning
    stopObserving()
    output =
      when (outputIn.lowercase()) {
        "both" -> OUTPUT_BOTH
        "attitude" -> OUTPUT_ATTITUDE
        "heading" -> OUTPUT_HEADING
        else -> {
          Log.e(
            TAG,
            "Unrecognised output passed to react-native-attitude, must be 'both', 'attitude' or 'heading' only"
          )
          output
        }
      }
    if (shouldStart) {
      startObserving()
    }
  }

  override fun setInterval(interval: Double) {
    intervalMillis = intervalMillisFor(interval)
    nextSampleTime = 0L
    lastEmitTimeMs = 0L
    val shouldStart = isRunning
    stopObserving()
    if (shouldStart) {
      startObserving()
    }
  }

  override fun setRotation(rotationIn: String) {
    rotation =
      when (rotationIn.lowercase()) {
        "none" -> ROTATE_NONE
        "left" -> ROTATE_LEFT
        "right" -> ROTATE_RIGHT
        else -> {
          Log.e(
            TAG,
            "Unrecognised rotation passed to react-native-attitude, must be 'none','left' or 'right' only"
          )
          rotation
        }
      }
    reset()
  }

  override fun startObserving() {
    if (rotationSensor == null) {
      return
    }
    nextSampleTime = 0L
    lastEmitTimeMs = 0L
    val samplingUs = samplingPeriodUs()
    sensorManager.registerListener(this, rotationSensor, samplingUs, samplingUs)
    isRunning = true
  }

  override fun stopObserving() {
    sensorManager.unregisterListener(this)
    isRunning = false
    eulerAngles[0] = 0f
    eulerAngles[1] = 0f
    eulerAnglesLast[0] = Float.NaN
    eulerAnglesLast[1] = Float.NaN
    headingLast = Float.NaN
    lastEmitTimeMs = 0L
  }

  override fun addListener(eventName: String) {}

  override fun removeListeners(count: Double) {}

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

  override fun onHostResume() {
    if (isRunning && rotationSensor != null) {
      val samplingUs = samplingPeriodUs()
      sensorManager.registerListener(this, rotationSensor, samplingUs, samplingUs)
    }
  }

  override fun onHostPause() {
    if (isRunning) {
      sensorManager.unregisterListener(this)
    }
  }

  override fun onHostDestroy() {
    stopObserving()
  }

  override fun onSensorChanged(event: SensorEvent) {
    val currentTime = SystemClock.elapsedRealtime()
    if (currentTime < nextSampleTime) {
      return
    }

    SensorManager.getRotationMatrixFromVector(
      rotationMatrix,
      getVectorFromSensorEvent(event)
    )

    when (rotation) {
      ROTATE_LEFT ->
        SensorManager.remapCoordinateSystem(
          rotationMatrix,
          SensorManager.AXIS_Z,
          SensorManager.AXIS_MINUS_X,
          remappedMatrix
        )
      ROTATE_RIGHT ->
        SensorManager.remapCoordinateSystem(
          rotationMatrix,
          SensorManager.AXIS_MINUS_Z,
          SensorManager.AXIS_X,
          remappedMatrix
        )
      else ->
        SensorManager.remapCoordinateSystem(
          rotationMatrix,
          SensorManager.AXIS_X,
          SensorManager.AXIS_Z,
          remappedMatrix
        )
    }

    var heading = 0f

    if (output == OUTPUT_BOTH || output == OUTPUT_ATTITUDE) {
      val computed =
        if (pitchOffset != 0f || rollOffset != 0f) {
          applyPitchOffset(pitchOffset, remappedMatrix, pitchAdjustedMatrix)
          applyRollOffset(rollOffset, pitchAdjustedMatrix, rollAdjustedMatrix)
          getOrientation(rollAdjustedMatrix)
        } else {
          getOrientation(remappedMatrix)
        }
      eulerAngles[0] = round(computed[0] * 10) / 10f
      eulerAngles[1] = round(computed[1] * 10) / 10f
    } else {
      eulerAngles[0] = 0f
      eulerAngles[1] = 0f
    }

    if (output == OUTPUT_BOTH || output == OUTPUT_HEADING) {
      val azimuth = SensorManager.getOrientation(remappedMatrix, orientation)[0]
      heading = round(((Math.toDegrees(azimuth.toDouble()) + 360) % 360)).toFloat()
    }

    val nowMs = System.currentTimeMillis()
    val changed =
      eulerAnglesLast[0].isNaN() ||
        eulerAngles[0] != eulerAnglesLast[0] ||
        eulerAngles[1] != eulerAnglesLast[1] ||
        heading != headingLast
    val heartbeatDue =
      !changed &&
        lastEmitTimeMs > 0 &&
        nowMs - lastEmitTimeMs >= HEARTBEAT_INTERVAL_MS

    if (changed || heartbeatDue) {
      val map: WritableMap =
        Arguments.createMap().apply {
          putDouble("timestamp", nowMs.toDouble())
          putDouble("roll", eulerAngles[1].toDouble())
          putDouble("pitch", eulerAngles[0].toDouble())
          putDouble("heading", heading.toDouble())
        }
      emitOnAttitudeUpdate(map)
      lastEmitTimeMs = nowMs
      if (changed) {
        eulerAnglesLast[0] = eulerAngles[0]
        eulerAnglesLast[1] = eulerAngles[1]
        headingLast = heading
      }
    }

    nextSampleTime = currentTime + intervalMillis
  }

  private fun intervalMillisFor(interval: Double): Int =
    when (interval.toInt()) {
      1000, 200, 100, 50, 25 -> interval.toInt()
      else -> 200
    }

  private fun samplingPeriodUs(): Int {
    val sensor = rotationSensor ?: return intervalMillis * 1000
    val requestedUs = intervalMillis * 1000
    val minDelayUs = sensor.minDelay.coerceAtLeast(1000)
    return maxOf(requestedUs, minDelayUs)
  }

  private fun getVectorFromSensorEvent(event: SensorEvent): FloatArray {
    return if (event.values.size > 4) {
      event.values.copyOf(4)
    } else {
      event.values
    }
  }

  private fun getOrientation(matrix: FloatArray): FloatArray {
    val pitch = Math.toDegrees(asin(matrix[7].coerceIn(-1f, 1f).toDouble())).toFloat()
    val roll =
      Math.toDegrees(atan2(-matrix[6].toDouble(), matrix[8].toDouble())).toFloat()
    return floatArrayOf(pitch, roll)
  }

  private fun applyRollOffset(
    roll: Float,
    matrixIn: FloatArray,
    matrixOut: FloatArray
  ) {
    val value = Math.toRadians(roll.toDouble()).toFloat()
    val rotateMatrix =
      floatArrayOf(
        cos(value),
        0f,
        sin(value),
        0f,
        1f,
        0f,
        -sin(value),
        0f,
        cos(value)
      )
    matrixMultiply(matrixIn, rotateMatrix, matrixOut)
  }

  private fun applyPitchOffset(
    pitch: Float,
    matrixIn: FloatArray,
    matrixOut: FloatArray
  ) {
    val value = Math.toRadians(pitch.toDouble()).toFloat()
    val rotateMatrix =
      floatArrayOf(
        1f,
        0f,
        0f,
        0f,
        cos(value),
        -sin(value),
        0f,
        sin(value),
        cos(value)
      )
    matrixMultiply(matrixIn, rotateMatrix, matrixOut)
  }

  private fun matrixMultiply(
    a: FloatArray,
    b: FloatArray,
    result: FloatArray
  ) {
    result[0] = a[0] * b[0] + a[1] * b[3] + a[2] * b[6]
    result[1] = a[0] * b[1] + a[1] * b[4] + a[2] * b[7]
    result[2] = a[0] * b[2] + a[1] * b[5] + a[2] * b[8]
    result[3] = a[3] * b[0] + a[4] * b[3] + a[5] * b[6]
    result[4] = a[3] * b[1] + a[4] * b[4] + a[5] * b[7]
    result[5] = a[3] * b[2] + a[4] * b[5] + a[5] * b[8]
    result[6] = a[6] * b[0] + a[7] * b[3] + a[8] * b[6]
    result[7] = a[6] * b[1] + a[7] * b[4] + a[8] * b[7]
    result[8] = a[6] * b[2] + a[7] * b[5] + a[8] * b[8]
  }

  companion object {
    const val NAME = NativeRNAttitudeSpec.NAME
    private const val TAG = "RNAttitude"
    private const val HEARTBEAT_INTERVAL_MS = 1000L
    private const val ROTATE_NONE = 0
    private const val ROTATE_LEFT = 1
    private const val ROTATE_RIGHT = 2
    private const val OUTPUT_BOTH = 0
    private const val OUTPUT_ATTITUDE = 1
    private const val OUTPUT_HEADING = 2
  }
}
