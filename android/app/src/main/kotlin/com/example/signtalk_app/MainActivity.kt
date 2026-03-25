package com.example.signtalk_app

import java.nio.ByteBuffer
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever // THÊM IMPORT NÀY ĐỂ ĐỌC VIDEO
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker.HandLandmarkerOptions
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sqrt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity: FlutterActivity() {
    private val CHANNEL = "signtalk.dev/mediapipe"
    
    private var poseLandmarker: PoseLandmarker? = null
    private var handLandmarker: HandLandmarker? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initMediaPipe()
    }

    private fun initMediaPipe() {
        val poseBaseOptions = BaseOptions.builder().setModelAssetPath("pose_landmarker.task").build()
        val poseOptions = PoseLandmarkerOptions.builder()
            .setBaseOptions(poseBaseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setMinPoseDetectionConfidence(0.5f)
            .build()
        poseLandmarker = PoseLandmarker.createFromOptions(this, poseOptions)

        val handBaseOptions = BaseOptions.builder().setModelAssetPath("hand_landmarker.task").build()
        val handOptions = HandLandmarkerOptions.builder()
            .setBaseOptions(handBaseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumHands(2)
            .setMinHandDetectionConfidence(0.5f)
            .setMinHandPresenceConfidence(0.5f)
            .build()
        handLandmarker = HandLandmarker.createFromOptions(this, handOptions)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            
            // ==============================================================
            // NHÁNH 1: BẮT CAMERA THỜI GIAN THỰC (GIỮ NGUYÊN CỦA BẠN)
            // ==============================================================
            if (call.method == "extractFeatures") {
                val bytes = call.argument<ByteArray>("bytes")!!
                val width = call.argument<Int>("width")!!
                val height = call.argument<Int>("height")!!
                val rotation = call.argument<Int>("rotation")!!
                val isFrontCamera = call.argument<Boolean>("isFrontCamera") ?: false

                CoroutineScope(Dispatchers.Default).launch {
                    try {
                        val yuvImage = YuvImage(bytes, ImageFormat.NV21, width, height, null)
                        val out = ByteArrayOutputStream()
                        yuvImage.compressToJpeg(android.graphics.Rect(0, 0, width, height), 100, out)
                        val jpegBytes = out.toByteArray()
                        val originalBitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)

                        val matrix = Matrix()
                        if (rotation != 0) {
                            matrix.postRotate(rotation.toFloat())
                        }
                        if (isFrontCamera) {
                            matrix.postScale(-1f, 1f, originalBitmap.width / 2f, originalBitmap.height / 2f)
                        }
                        
                        val finalBitmap = Bitmap.createBitmap(originalBitmap, 0, 0, originalBitmap.width, originalBitmap.height, matrix, false)

                        val mpImage = BitmapImageBuilder(finalBitmap).build()
                        val poseResult = poseLandmarker?.detect(mpImage)
                        val handResult = handLandmarker?.detect(mpImage)

                        val featuresMap = extractAndNormalize(poseResult, handResult)
                        
                        withContext(Dispatchers.Main) {
                            if (featuresMap != null) {
                                result.success(featuresMap) 
                            } else {
                                result.success(null) 
                            }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("ML_ERROR", e.message, null)
                        }
                    }
                }
            } 
            // ==============================================================
            // NHÁNH 2: TÁCH FRAME TỪ VIDEO UPLOAD LÊN (THÊM MỚI)
            // ==============================================================
            else if (call.method == "processVideoFile") {
                val videoPath = call.argument<String>("videoPath")
                if (videoPath == null) {
                    result.error("INVALID_ARGUMENT", "No video path", null)
                    return@setMethodCallHandler
                }

                CoroutineScope(Dispatchers.Default).launch {
                    try {
                        val featuresSequence = mutableListOf<DoubleArray>()
                        val retriever = MediaMetadataRetriever()
                        
                        retriever.setDataSource(videoPath)
                        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durationMs = durationStr?.toLongOrNull() ?: 0L
                        
                        val intervalUs = 33333L // Lấy ~30 hình/giây
                        val durationUs = durationMs * 1000L

                        for (timeUs in 0 until durationUs step intervalUs) {
                            val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                            if (bitmap != null) {
                                val argbBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                val mpImage = BitmapImageBuilder(argbBitmap).build()
                                val poseResult = poseLandmarker?.detect(mpImage)
                                val handResult = handLandmarker?.detect(mpImage)

                                // Gọi hàm của bạn, nó trả về Map
                                val extractedMap = extractAndNormalize(poseResult, handResult)
                                
                                // Ta chỉ bóc lấy mảng "features" 96 con số để gửi lên Dart chạy AI
                                val features = extractedMap?.get("features")
                                if (features != null) {
                                    featuresSequence.add(features)
                                }
                                bitmap.recycle()
                            }
                        }
                        retriever.release()

                        withContext(Dispatchers.Main) {
                            result.success(featuresSequence) // Trả về List các DoubleArray
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("VIDEO_ERROR", e.message, null)
                        }
                    }
                }
            }
            else {
                result.notImplemented()
            }
        }
    }

    // --- HÀM CỦA BẠN (GIỮ NGUYÊN 100%, TRẢ VỀ MAP) ---
    private fun extractAndNormalize(
        poseResult: com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult?,
        handResult: com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult?
    ): Map<String, DoubleArray>? {
        val points = Array(48) { doubleArrayOf(0.0, 0.0) }
        var isPersonDetected = false

        if (poseResult != null && poseResult.landmarks().isNotEmpty()) {
            isPersonDetected = true
            val landmarks = poseResult.landmarks()[0]
            val indices = intArrayOf(11, 12, 13, 14, 15, 16)
            for (i in indices.indices) {
                val idx = indices[i]
                if (idx < landmarks.size) {
                    points[i][0] = landmarks[idx].x().toDouble()
                    points[i][1] = landmarks[idx].y().toDouble()
                }
            }
        }

        if (!isPersonDetected) return null 
        
        if (handResult == null || handResult.landmarks().isEmpty()) {
            return null 
        }

        if (handResult != null && handResult.landmarks().isNotEmpty()) {
            for (i in handResult.landmarks().indices) {
                val handMarks = handResult.landmarks()[i]
                val handedness = handResult.handednesses()[i][0].categoryName()
                val offset = if (handedness == "Left") 6 else 27
                
                for (j in 0 until 21) {
                    if (j < handMarks.size) {
                        points[offset + j][0] = handMarks[j].x().toDouble()
                        points[offset + j][1] = handMarks[j].y().toDouble()
                    }
                }
            }
        }

        val leftShoulder = points[0]
        val rightShoulder = points[1]
        val centerX = (leftShoulder[0] + rightShoulder[0]) / 2.0
        val centerY = (leftShoulder[1] + rightShoulder[1]) / 2.0

        var width = sqrt(
            (leftShoulder[0] - rightShoulder[0]).pow(2.0) +
            (leftShoulder[1] - rightShoulder[1]).pow(2.0)
        )
        width = max(width, 0.001)

       val normalizedFeatures = DoubleArray(96) 
        var index = 0
        for (p in points) {
            if (p[0] == 0.0 && p[1] == 0.0) {
                normalizedFeatures[index++] = 0.0
                normalizedFeatures[index++] = 0.0
            } else {
                normalizedFeatures[index++] = (p[0] - centerX) / width
                normalizedFeatures[index++] = (p[1] - centerY) / width
            }
        }

        val rawLandmarks = DoubleArray(96)
        var k = 0
        for (p in points) {
            rawLandmarks[k++] = p[0]
            rawLandmarks[k++] = p[1]
        }

        return mapOf(
            "features" to normalizedFeatures,
            "landmarks" to rawLandmarks
        )
    }
}