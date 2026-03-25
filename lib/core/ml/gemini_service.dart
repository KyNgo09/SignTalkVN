import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) => GeminiService());

class GeminiService {
  late final String _apiKey;
  GenerativeModel? _model;

  // DANH SÁCH 50 CÂU THẦN CHÚ CÓ NGHĨA CÓ SẴN
  static const List<String> _allowedSentences = [
    "Tôi là giáo viên.",
    "Xin chào bác sĩ.",
    "Tôi đi học rất vui.",
    "Bạn ăn cơm chưa?",
    "Mẹ tôi rất yêu tôi.",
    "Tôi thích uống nước.",
    "Hẹn gặp lại bạn.",
    "Tôi bị đau ở đâu?",
    "Xin chào, bạn khỏe không?",
    // ... hãy thêm tiếp các câu của bạn vào đây ...
  ];

  GeminiService() {
    _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (_apiKey.isEmpty) {
      debugPrint('❗ GEMINI_API_KEY chưa được cấu hình trong .env');
      return;
    }

    // ĐƯA SYSTEM PROMPT LÊN ĐÂY VÀ TRUYỀN VÀO LÚC KHỞI TẠO MODEL
    final systemPrompt =
        """
Bạn là một hệ thống biên dịch Ngôn ngữ Ký hiệu Việt Nam (VSL) chuyên nghiệp. Nhiệm vụ của bạn là nhận một chuỗi các từ khóa (Gloss) và **DỰA VÀO ĐÓ ĐỂ CHỌN RA 1 CÂU** chính xác nhất từ danh sách câu được cho phép dưới đây.

**Lưu ý sinh tử:**
- Chuỗi từ khóa đầu vào có thể bị sai lệch nhỏ. Hãy dùng ngữ cảnh để suy luận.
- **TUYỆT ĐỐI KHÔNG TỰ SÁNG TÁC CÂU MỚI.**
- Chỉ được phép trả về **DUY NHẤT** một câu nằm trong danh sách dưới đây, không kèm theo giải thích gì thêm.

---
**DANH SÁCH CÂU ĐƯỢC PHÉP CHỌN (MENU):**
${_allowedSentences.map((s) => "- $s").join("\n")}
---
""";

    // Khởi tạo model với systemInstruction chuẩn của SDK
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      systemInstruction: Content.system(systemPrompt),
    );
  }

  Future<String> translateGlossToSentence(List<String> glossList) async {
    if (glossList.isEmpty) return "";
    if (_model == null) return "Thiếu khóa dịch thuật.";

    final glossText = glossList.join(", ");
    debugPrint("💬 Gửi chuỗi Gloss lên Gemini: $glossText");

    // PROMPT NGƯỜI DÙNG CHỈ CÒN ĐƠN GIẢN LÀ TRUYỀN DATA
    final userPrompt = "Chuỗi từ khóa đầu vào: [$glossText]";

    try {
      final content = [Content.text(userPrompt)];

      final response = await _model!.generateContent(content);
      final finalSentence = response.text?.trim() ?? "";

      debugPrint("✅ Gemini chốt câu cuối cùng: $finalSentence");
      return finalSentence;
    } catch (e) {
      // IN RA MÃ LỖI CHI TIẾT ĐỂ BẮT BỆNH
      debugPrint("❌ Lỗi gọi API Gemini chi tiết: $e");
      return "Lỗi kết nối dịch thuật.";
    }
  }
}
