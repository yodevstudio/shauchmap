package com.shauchmap.app

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.content.Context
import androidx.annotation.NonNull
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.shauchmap.app/haptics"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAsymmetricChoice" -> {
                    val isChecking = call.argument<Boolean>("isChecking") ?: true
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val composition = VibrationEffect.startComposition()
                        if (isChecking && vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1.0f)
                        } else if (!isChecking && vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_LOW_TICK)) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_LOW_TICK, 0.5f, 15)
                        } else {
                            executeNativeVibration(longArrayOf(0, if (isChecking) 20 else 10), intArrayOf(0, 150))
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        vibrator.vibrate(composition.compose())
                    } else {
                        executeNativeVibration(longArrayOf(0, if (isChecking) 20 else 10), intArrayOf(0, 150))
                    }
                    result.success(null)
                }
                "playRubberBandBounce" -> {
                    // Maximum impact boundary crash thud
                    executeNativeVibration(longArrayOf(0, 80), intArrayOf(0, 255))
                    result.success(null)
                }
                "playRewardCrescendo" -> {
                    // Maximum duration celebratory vibration block that lasts half a second
                    executeNativeVibration(longArrayOf(0, 80, 40, 80, 40, 120, 30, 150), intArrayOf(0, 200, 0, 220, 0, 245, 0, 255))
                    result.success(null)
                }
                "playHollowDecay" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_THUD)) {
                        val effect = VibrationEffect.startComposition()
                            .addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 0.7f)
                            .addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 0.3f, 120)
                            .compose()
                        vibrator.vibrate(effect)
                    } else {
                        executeNativeVibration(longArrayOf(0, 15, 100, 10), intArrayOf(0, 180, 0, 90))
                    }
                    result.success(null)
                }
                "playWaveform" -> {
                    val timings = call.argument<List<Long>>("timings")
                    val amplitudes = call.argument<List<Int>>("amplitudes")
                    if (timings != null && amplitudes != null) {
                        executeNativeVibration(timings.toLongArray(), amplitudes.toIntArray())
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Timings or amplitudes arrays were null", null)
                    }
                }
                "playStepTransition" -> {
                    executeNativeVibration(longArrayOf(0, 10, 40, 15), intArrayOf(0, 120, 0, 180))
                    result.success(null)
                }
                "playTileSelect" -> {
                    executeNativeVibration(longArrayOf(0, 25), intArrayOf(0, 220))
                    result.success(null)
                }
                "playToggleSnap" -> {
                    executeNativeVibration(longArrayOf(0, 12), intArrayOf(0, 90))
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun executeNativeVibration(timings: LongArray, amplitudes: IntArray) {
        if (vibrator.hasVibrator()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(timings, -1)
            }
        }
    }
}
