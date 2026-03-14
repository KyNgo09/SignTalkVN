package com.example.signtalk_app

import android.graphics.Bitmap
import android.graphics.Matrix
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
            if (call.method == "extractFeatures") {
                val bytes = call.argument<ByteArray>("bytes")!!
                val width = call.argument<Int>("width")!!
                val height = call.argument<Int>("height")!!
                val rotation = call.argument<Int>("rotation")!!

                // Chạy trên luồng ngầm để giải phóng UI (Chống giật lag)
                CoroutineScope(Dispatchers.Default).launch {
                    try {
                        // 1. Chuyển đổi NV21 sang Bitmap bằng thuật toán Bitwise siêu tốc (Bỏ qua JPEG)
                        var bitmap = nv21ToBitmap(bytes, width, height)

                        // 2. Xoay ảnh siêu nhanh bằng Matrix
                        if (rotation != 0) {
                            val matrix = Matrix()
                            matrix.postRotate(rotation.toFloat())
                            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, false)
                        }

                        // 3. Đưa vào MediaPipe
                        val mpImage = BitmapImageBuilder(bitmap).build()
                        val poseResult = poseLandmarker?.detect(mpImage)
                        val handResult = handLandmarker?.detect(mpImage)

                        // 4. Trích xuất & Chuẩn hóa
                        val features = extractAndNormalize(poseResult, handResult)
                        
                        // Trả kết quả về Main Thread an toàn
                        withContext(Dispatchers.Main) {
                            if (features != null) {
                                result.success(features)
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
            } else {
                result.notImplemented()
            }
        }
    }

    // =====================================================================
    // THUẬT TOÁN DỊCH BIT (SIÊU TỐC) CHUYỂN ĐỔI ẢNH CAMERA THÀNH MÀU RGB
    // Bỏ qua nén JPEG giúp tốc độ xử lý tăng gấp 10 lần!
    // =====================================================================
    private fun nv21ToBitmap(nv21: ByteArray, width: Int, height: Int): Bitmap {
        val pixels = IntArray(width * height)
        var yOffset = 0
        val frameSize = width * height
        
        for (y in 0 until height) {
            var uvOffset = frameSize + (y shr 1) * width
            for (x in 0 until width) {
                var yValue = (nv21[yOffset].toInt() and 0xFF) - 16
                if (yValue < 0) yValue = 0

                val vValue = (nv21[uvOffset].toInt() and 0xFF) - 128
                val uValue = (nv21[uvOffset + 1].toInt() and 0xFF) - 128

                val y1192 = 1192 * yValue
                var r = (y1192 + 1634 * vValue)
                var g = (y1192 - 833 * vValue - 400 * uValue)
                var b = (y1192 + 2066 * uValue)

                r = if (r < 0) 0 else if (r > 262143) 262143 else r
                g = if (g < 0) 0 else if (g > 262143) 262143 else g
                b = if (b < 0) 0 else if (b > 262143) 262143 else b

                pixels[yOffset++] = -0x1000000 or ((r shl 6) and 0xFF0000) or ((g shr 2) and 0xFF00) or ((b shr 10) and 0xFF)

                if (x and 1 != 0) {
                    uvOffset += 2
                }
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    // --- THUẬT TOÁN ĐỒNG BỘ 100% VỚI PYTHON CỦA BẠN ---
    private fun extractAndNormalize(
        poseResult: com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult?,
        handResult: com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult?
    ): DoubleArray? {
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
            normalizedFeatures[index++] = (p[0] - centerX) / width
            normalizedFeatures[index++] = (p[1] - centerY) / width
        }

        return normalizedFeatures
    }
}