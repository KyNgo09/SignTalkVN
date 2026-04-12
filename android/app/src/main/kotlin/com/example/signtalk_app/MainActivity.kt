package com.example.signtalk_app

import java.nio.ByteBuffer
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
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
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll

class MainActivity: FlutterActivity() {
    private val CHANNEL = "signtalk.dev/mediapipe"
    
    // ── Landmarker dành cho CAMERA realtime (RunningMode.IMAGE) ──
    private var poseLandmarker: PoseLandmarker? = null
    private var handLandmarker: HandLandmarker? = null

    // ── Landmarker riêng cho VIDEO (RunningMode.VIDEO) ──
    // VIDEO mode dùng tracking liên tục giữa các frame kế tiếp
    // → Không cần re-detect từ đầu mỗi frame → Nhanh hơn IMAGE mode ~40-50%
    private var videoPoseLandmarker: PoseLandmarker? = null
    private var videoHandLandmarker: HandLandmarker? = null

    // ── Offset timestamp để không cần recreate landmarkers mỗi video ──
    // VIDEO mode yêu cầu timestamp STRICTLY INCREASING.
    // Thay vì tạo lại 2 model (~1-2s mỗi lần), ta tích lũy offset liên tục.
    // Video 1: timestamp 0..4000ms → Video 2: timestamp 5000..9000ms → ...
    private var videoTimestampOffsetMs = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initMediaPipe()
    }

    private fun initMediaPipe() {
        // ── CAMERA MODE (IMAGE) - Giữ nguyên ──
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

        // Khởi tạo video landmarkers lần đầu
        initVideoLandmarkers()
    }

    // ── ✅ [Giải pháp 3] VIDEO MODE ──
    // Tách thành hàm riêng vì cần GỌI LẠI mỗi lần xử lý video mới.
    // Lý do: VIDEO mode yêu cầu timestamp TĂNG LIÊN TỤC (strictly increasing).
    // Khi upload video lần 2, timestamp reset về 0 → MediaPipe từ chối vì nhỏ hơn
    // timestamp cuối của video trước → phải tạo lại instance mới để reset.
    private fun initVideoLandmarkers() {
        // Đóng instance cũ (nếu có) để giải phóng bộ nhớ
        videoPoseLandmarker?.close()
        videoHandLandmarker?.close()

        val videoPoseBaseOptions = BaseOptions.builder().setModelAssetPath("pose_landmarker.task").build()
        val videoPoseOptions = PoseLandmarkerOptions.builder()
            .setBaseOptions(videoPoseBaseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setMinPoseDetectionConfidence(0.5f)
            .build()
        videoPoseLandmarker = PoseLandmarker.createFromOptions(this, videoPoseOptions)

        val videoHandBaseOptions = BaseOptions.builder().setModelAssetPath("hand_landmarker.task").build()
        val videoHandOptions = HandLandmarkerOptions.builder()
            .setBaseOptions(videoHandBaseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setNumHands(2)
            .setMinHandDetectionConfidence(0.5f)
            .setMinHandPresenceConfidence(0.5f)
            .build()
        videoHandLandmarker = HandLandmarker.createFromOptions(this, videoHandOptions)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            
            // ==============================================================
            // NHÁNH 1: BẮT CAMERA THỜI GIAN THỰC (GIỮ NGUYÊN)
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
            // NHÁNH 2: XỬ LÝ VIDEO UPLOAD
            // ✅ [Giải pháp 1] Trả vector zero thay vì bỏ frame → giữ đúng timeline
            // ✅ [Giải pháp 3] VIDEO mode MediaPipe → detect nhanh hơn 40-50%
            // + Thu nhỏ ảnh 480px + getScaledFrameAtTime → tiết kiệm RAM & CPU
            // ==============================================================
            else if (call.method == "processVideoFile") {
                val videoPath = call.argument<String>("videoPath")
                if (videoPath == null) {
                    result.error("INVALID_ARGUMENT", "No video path", null)
                    return@setMethodCallHandler
                }

                CoroutineScope(Dispatchers.Default).launch {
                    try {
                        val startTime = System.currentTimeMillis()

                        // ✅ Tăng offset thêm 10s để timestamp luôn tăng giữa các video
                        // Thay vì recreate 2 model MediaPipe (~1-2s), chỉ cần shift timestamp
                        videoTimestampOffsetMs += 10000L

                        val featuresSequence = mutableListOf<DoubleArray>()
                        val retriever = MediaMetadataRetriever()
                        
                        retriever.setDataSource(videoPath)
                        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durationMs = durationStr?.toLongOrNull() ?: 0L
                        
                        // ✅ EXTRACT ở 10fps thay vì 30fps → giảm 3x số frame cần seek
                        // Mỗi lần getFrameAtTime tốn ~250ms (từ log thực tế)
                        // 30fps: 150 frames × 250ms = ~37s | 10fps: 50 frames × 250ms = ~12s
                        // Phía Dart sẽ NỘI SUY lên 30fps để khớp model BiLSTM
                        val intervalUs = 100000L // 10fps = 100000μs/frame (100ms)
                        val durationUs = durationMs * 1000L

                        // Lấy kích thước video để tính scale thu nhỏ
                        val videoWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toFloatOrNull() ?: 1080f
                        val videoHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toFloatOrNull() ?: 1920f
                        
                        // Ép ảnh về tối đa 320px → MediaPipe chạy nhanh hơn ~30%
                        // MediaPipe chỉ cần ~256px để detect chính xác
                        val maxDimension = 320f
                        val scale = if (videoWidth > videoHeight) maxDimension / videoWidth else maxDimension / videoHeight
                        val targetWidth = (videoWidth * scale).toInt()
                        val targetHeight = (videoHeight * scale).toInt()

                        android.util.Log.d("SignTalk", "📹 Video: ${durationMs}ms, ${videoWidth}x${videoHeight} → ${targetWidth}x${targetHeight}")

                        // ── Timestamp cho VIDEO mode MediaPipe (phải tăng đều) ──
                        // Dùng offset tích lũy để không cần recreate landmarkers
                        var timestampMs = videoTimestampOffsetMs

                        for (timeUs in 0 until durationUs step intervalUs) {
                            // Dùng getScaledFrameAtTime trên Android 8.1+ (nhanh hơn get + scale thủ công)
                            val bitmap = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
                                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, targetWidth, targetHeight)
                            } else {
                                val rawBitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                                if (rawBitmap != null) {
                                    val scaled = Bitmap.createScaledBitmap(rawBitmap, targetWidth, targetHeight, true)
                                    rawBitmap.recycle()
                                    scaled
                                } else null
                            }

                            if (bitmap != null) {
                                val argbBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                val mpImage = BitmapImageBuilder(argbBitmap).build()

                                // ✅ Chạy Pose + Hand detect SONG SONG
                                // Thay vì tuần tự (pose 100ms rồi hand 100ms = 200ms),
                                // chạy 2 coroutine đồng thời → overlap → ~120ms/frame
                                val poseDeferred = async { videoPoseLandmarker?.detectForVideo(mpImage, timestampMs) }
                                val handDeferred = async { videoHandLandmarker?.detectForVideo(mpImage, timestampMs) }
                                val poseResult = poseDeferred.await()
                                val handResult = handDeferred.await()

                                // ✅ [Giải pháp 1] Trả vector zero thay vì bỏ frame
                                // Khi không detect được tay → điền 96 số 0 → giữ đúng timeline 30fps
                                // Lý do: Nếu bỏ frame, sliding window bị "xé rách" ranh giới ký hiệu
                                // → model chỉ bắt được 1 từ thay vì cả câu
                                val extractedMap = extractAndNormalize(poseResult, handResult)
                                val features = extractedMap?.get("features") ?: DoubleArray(96) { 0.0 }
                                featuresSequence.add(features)

                                bitmap.recycle()
                                if (argbBitmap !== bitmap) argbBitmap.recycle()
                            } else {
                                // Ngay cả khi bitmap null → vẫn thêm zero-vector để giữ timeline
                                featuresSequence.add(DoubleArray(96) { 0.0 })
                            }

                            timestampMs += intervalUs / 1000 // Tăng timestamp cho VIDEO mode
                        }
                        retriever.release()
                        
                        val elapsed = System.currentTimeMillis() - startTime
                        android.util.Log.d("SignTalk", "✅ Xử lý video xong trong ${elapsed}ms, tổng ${featuresSequence.size} frames")

                        withContext(Dispatchers.Main) {
                            result.success(featuresSequence)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("SignTalk", "❌ Lỗi xử lý video: ${e.message}", e)
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

    // --- HÀM EXTRACT & NORMALIZE (GIỮ NGUYÊN) ---
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