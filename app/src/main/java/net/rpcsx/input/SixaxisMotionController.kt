package net.rpcsx.input

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import net.rpcsx.RPCSX
import net.rpcsx.utils.SixaxisMotionPrefs

class SixaxisMotionController(context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val accel = FloatArray(3)
    private val gyro = FloatArray(3)
    private var hasAccel = false
    private var hasGyro = false
    private var isRunning = false
    private var lastSendNanos = 0L

    val hasDeviceMotionSensors: Boolean
        get() = accelerometer != null

    fun start() {
        if (isRunning || !SixaxisMotionPrefs.isEnabled()) {
            return
        }

        if (!RPCSX.instance.supportsPadMotionData()) {
            Log.i(TAG, "Sixaxis motion is enabled, but the active RPCSX core has no Android motion bridge")
            return
        }

        val accelSensor = accelerometer
        if (accelSensor == null) {
            Log.i(TAG, "Sixaxis motion is enabled, but this device has no accelerometer")
            return
        }

        hasAccel = false
        hasGyro = false
        lastSendNanos = 0L
        if (!sensorManager.registerListener(this, accelSensor, SensorManager.SENSOR_DELAY_GAME)) {
            Log.i(TAG, "Sixaxis motion is enabled, but the accelerometer listener could not start")
            return
        }
        gyroscope?.let { sensor ->
            sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        }
        isRunning = true
    }

    fun stop() {
        if (!isRunning) {
            return
        }

        sensorManager.unregisterListener(this)
        isRunning = false
        hasAccel = false
        hasGyro = false
        lastSendNanos = 0L
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                event.values.copyInto(accel, endIndex = 3)
                hasAccel = true
            }
            Sensor.TYPE_GYROSCOPE -> {
                event.values.copyInto(gyro, endIndex = 3)
                hasGyro = true
            }
            else -> return
        }

        if (!hasAccel || event.timestamp - lastSendNanos < MIN_SEND_INTERVAL_NANOS) {
            return
        }

        lastSendNanos = event.timestamp
        RPCSX.instance.overlayPadMotionData(
            accel[0],
            accel[1],
            accel[2],
            if (hasGyro) gyro[0] else 0f,
            if (hasGyro) gyro[1] else 0f,
            if (hasGyro) gyro[2] else 0f
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private companion object {
        private const val TAG = "SixaxisMotion"
        private const val MIN_SEND_INTERVAL_NANOS = 8_000_000L
    }
}
