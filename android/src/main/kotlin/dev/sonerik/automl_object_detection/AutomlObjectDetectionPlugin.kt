package dev.sonerik.automl_object_detection

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.Size
import androidx.annotation.NonNull
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.objects.ObjectDetection
import com.google.mlkit.vision.objects.ObjectDetector
import com.google.mlkit.vision.objects.defaults.ObjectDetectorOptions
//import com.google.mlkit.common.model.LocalModel
//import com.google.mlkit.vision.common.InputImage
//import com.google.mlkit.vision.objects.ObjectDetection
//import com.google.mlkit.vision.objects.ObjectDetector
//import com.google.mlkit.vision.objects.custom.CustomObjectDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.*

/** AutomlObjectDetectionPlugin */
class AutomlObjectDetectionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private var lifecycle: Lifecycle? = null

    private var lastDetectorId = 0
    private val detectors = mutableMapOf<Int, ObjectDetector>()
    private val detectorBitmaps = mutableMapOf<Int, Bitmap>()
    private val detectorBitmapBuffers = mutableMapOf<Int, IntArray>()
    private val executors = mutableMapOf<Int, Executor>()

    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        binding = flutterPluginBinding
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.sonerik.automl_object_detection")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "prepareDetector" -> {
                val bitmapWidth = call.argument<Int>("bitmapWidth")!!
                val bitmapHeight = call.argument<Int>("bitmapHeight")!!

                val enableClassification = call.argument<Boolean>("enableClassification")!!
                val enableMultipleObjects = call.argument<Boolean>("enableMultipleObjects")!!

                val id = initDetector(
                        bitmapSize = Size(bitmapWidth, bitmapHeight),
                        enableClassification = enableClassification,
                        enableMultipleObjects = enableMultipleObjects
                )
                result.success(id)
            }
            "disposeDetector" -> {
                val id = call.argument<Int>("id")!!
                disposeDetector(id)
                result.success(null)
            }
            "processImage" -> {
                val id = call.argument<Int>("detectorId")!!
                val imageRgbBytes = call.argument<ByteArray>("rgbBytes")!!
                executors[id]!!.execute {
                    val bitmap = detectorBitmaps[id]!!
                    writeRgbByteArrayToBitmap(imageRgbBytes, detectorBitmapBuffers[id]!!, bitmap)
                    val inputImage = InputImage.fromBitmap(bitmap, 0)
                    detectors[id]!!.process(inputImage).addOnSuccessListener { objects ->
                        val results = objects.map {
                            mapOf(
                                    "boundingBox" to mapOf(
                                            "left" to it.boundingBox.left.toFloat(),
                                            "top" to it.boundingBox.top.toFloat(),
                                            "right" to it.boundingBox.right.toFloat(),
                                            "bottom" to it.boundingBox.bottom.toFloat()
                                    ),
                                    "trackingId" to it.trackingId,
                                    "labels" to it.labels.map { label ->
                                        mapOf(
                                                "index" to label.index,
                                                "text" to label.text,
                                                "confidence" to label.confidence
                                        )
                                    }
                            )
                        }
                        Handler(Looper.getMainLooper()).post {
                            result.success(results)
                        }
                    }.addOnFailureListener {
                        Handler(Looper.getMainLooper()).post {
                            result.error("", it.localizedMessage, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun initDetector(
            enableClassification: Boolean,
            enableMultipleObjects: Boolean,
            bitmapSize: Size
    ): Int {
        val id = lastDetectorId++

        val executor = Executors.newSingleThreadExecutor()
        executors[id] = executor

        var options = ObjectDetectorOptions.Builder()
                .setDetectorMode(ObjectDetectorOptions.STREAM_MODE)

        if (enableClassification) {
            options = options.enableClassification()
        }

        if (enableMultipleObjects) {
            options = options.enableMultipleObjects()
        }

        val detector = ObjectDetection.getClient(options.build())
        lifecycle?.addObserver(detector)

        detectors[id] = detector
        detectorBitmaps[id] = Bitmap.createBitmap(bitmapSize.width, bitmapSize.height, Bitmap.Config.ARGB_8888)
        detectorBitmapBuffers[id] = IntArray(bitmapSize.width * bitmapSize.height)

        return id
    }

    private fun disposeDetector(id: Int) {
        detectors[id]?.let {
            lifecycle?.removeObserver(it)
            it.close()
        }
        detectors.remove(id)

        detectorBitmaps[id]?.recycle()
        detectorBitmaps.remove(id)

        detectorBitmapBuffers.remove(id)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        lifecycle = (binding.activity as LifecycleOwner).lifecycle
    }

    override fun onDetachedFromActivity() {
        lifecycle = null
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
}

private fun writeRgbByteArrayToBitmap(bytes: ByteArray, pixels: IntArray, bitmap: Bitmap) {
    val nrOfPixels: Int = bytes.size / 3 // Three bytes per pixel
    for (i in 0 until nrOfPixels) {
        val r = 0xFF and bytes[3 * i].toInt()
        val g = 0xFF and bytes[3 * i + 1].toInt()
        val b = 0xFF and bytes[3 * i + 2].toInt()

        pixels[i] = Color.rgb(r, g, b)
    }
    bitmap.setPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
}