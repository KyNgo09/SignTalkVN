import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) => GeminiService());

class GeminiService {
  late final String _apiKey;
  GenerativeModel? _model;

  // DANH SÁCH MENU CÂU ĐÁP ÁN (Bạn nhớ cập nhật lại danh sách của bạn nhé)
  static const List<String> _allowedSentences = [
    "Tôi là giáo viên.",
    "Xin chào bác sĩ.",
    "Tôi đi học rất vui.",
    "Bạn ăn cơm chưa?",
    "Xin chào, bạn khỏe không?",
    "Tôi bị đau ở đâu?",
    "Hẹn gặp lại bạn.",
  ];

  GeminiService() {
    _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    debugPrint("🔑 API Key đang dùng: ${_apiKey.substring(0, 10)}...");
    if (_apiKey.isEmpty) {
      debugPrint('❗ GEMINI_API_KEY chưa được cấu hình trong .env');
      return;
    }

    _model = GenerativeModel(
      model:
          'gemini-2.0-flash', 
      apiKey: _apiKey,
    );
  }

  Future<String> translateGlossToSentence(List<String> glossList) async {
    if (glossList.isEmpty) return "";
    if (_model == null) return "Thiếu khóa dịch thuật.";

    final glossText = glossList.join(", ");
    debugPrint("💬 Gửi chuỗi Gloss lên Gemini: $glossText");

    final fullPrompt =
        """
Bạn là một chuyên gia ngôn ngữ học và biên dịch Ngôn ngữ Ký hiệu Việt Nam (VSL) cấp cao. 
Nhiệm vụ của bạn là nhận một chuỗi các từ khóa (Gloss) được trích xuất từ camera AI, sau đó chọn ra 1 câu khớp ý nghĩa nhất từ danh sách cho phép.

⚠️ ĐẶC ĐIỂM DỮ LIỆU ĐẦU VÀO (RẤT QUAN TRỌNG):
- Do AI nhận diện qua video, chuỗi từ khóa chắc chắn sẽ chứa các "từ nhiễu" (những từ lọt chỏm, không liên quan, do AI bắt nhầm khoảnh khắc chuyển động tay).
- Ví dụ: Chuỗi [XIN_CHAO, AN, KHOE] thì chữ "AN" là nhiễu, ý chính vẫn là hỏi thăm sức khỏe.

🧠 NHIỆM VỤ CỦA BẠN:
1. Đọc chuỗi đầu vào, phân tích ngữ cảnh để TỰ ĐỘNG BỎ QUA các từ nhiễu, từ sai lệch lô-gic.
2. Nắm bắt "ý nghĩa cốt lõi" của các từ khóa chính còn lại.
3. Đối chiếu ý nghĩa cốt lõi đó với DANH SÁCH CÂU CHO PHÉP bên dưới.
4. Chọn ra ĐÚNG 1 CÂU phù hợp nhất. Tuyệt đối KHÔNG tự sáng tác câu mới.
5. Nếu chuỗi đầu vào hoàn toàn là từ nhiễu vô nghĩa, không thể liên hệ tới bất kỳ câu nào, hãy trả về chính xác câu: "Không thể nhận diện rõ ý nghĩa."

---
DANH SÁCH CÂU CHO PHÉP (MENU):
${_allowedSentences.map((s) => "- $s").join("\n")}
---

Chuỗi từ khóa đầu vào: [$glossText]
Câu dịch kết quả (Chỉ in ra câu, không giải thích):
""";

    try {
      // Gọi API bằng hàm gửi Text cơ bản nhất (Tương thích mọi model)
      final content = [Content.text(fullPrompt)];

      final response = await _model!.generateContent(content);
      final finalSentence = response.text?.trim() ?? "";

      debugPrint("✅ Gemini chốt câu cuối cùng: $finalSentence");
      return finalSentence;
    } catch (e) {
      debugPrint("❌ Lỗi gọi API Gemini chi tiết: $e");
      return "Lỗi kết nối dịch thuật.";
    }
  }
}
