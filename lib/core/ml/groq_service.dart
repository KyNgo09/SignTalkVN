import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

final groqServiceProvider = Provider<GroqService>(
  (ref) => GroqService(),
);

class GroqService {
  late final String _apiKey;

  // DANH SÁCH MENU CÂU ĐÁP ÁN
  static const List<String> _allowedSentences = [
    "Tôi là giáo viên.",
    "Xin chào bác sĩ.",
    "Tôi đi học rất vui.",
    "Bạn ăn cơm chưa?",
    "Xin chào, bạn khỏe không?",
    "Tôi bị đau ở đâu?",
    "Hẹn gặp lại bạn.",
  ];

  GroqService() {
    _apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    debugPrint(
      "🔑 API Key OpenRouter đang dùng: ${_apiKey.isNotEmpty ? _apiKey.substring(0, 10) + '...' : 'RỖNG'}",
    );

    if (_apiKey.isEmpty) {
      debugPrint('❗ GROQ_API_KEY chưa được cấu hình trong .env');
    }
  }

  Future<String> translateGlossToSentence(List<String> glossList) async {
    if (glossList.isEmpty) return "";
    if (_apiKey.isEmpty) return "Thiếu khóa dịch thuật OpenRouter.";

    final glossText = glossList.join(", ");
    debugPrint("💬 Gửi chuỗi Gloss lên Groq: $glossText");

    // Tách riêng System Prompt (Luật lệ) và User Prompt (Dữ liệu)
    // Groq cực kỳ thông minh khi nhận diện luật lệ ở System Prompt
    final systemPrompt =
        """
Bạn là một chuyên gia ngôn ngữ học và biên dịch Ngôn ngữ Ký hiệu Việt Nam (VSL) cấp cao. 
Nhiệm vụ của bạn là nhận một chuỗi các từ khóa (Gloss) được trích xuất từ camera AI, sau đó chọn ra 1 câu khớp ý nghĩa nhất từ danh sách cho phép.

⚠️ ĐẶC ĐIỂM DỮ LIỆU ĐẦU VÀO (RẤT QUAN TRỌNG):
- Do AI nhận diện qua video, chuỗi từ khóa chắc chắn sẽ chứa các "từ nhiễu" (bắt nhầm khoảnh khắc).
- Ví dụ: Chuỗi [XIN_CHAO, AN, KHOE] thì chữ "AN" là nhiễu, ý chính vẫn là hỏi thăm sức khỏe.

🧠 NHIỆM VỤ CỦA BẠN:
1. Đọc chuỗi đầu vào, phân tích ngữ cảnh để TỰ ĐỘNG BỎ QUA các từ nhiễu.
2. Nắm bắt "ý nghĩa cốt lõi" của các từ khóa chính.
3. Đối chiếu ý nghĩa cốt lõi đó với DANH SÁCH CÂU CHO PHÉP bên dưới.
4. Chọn ra ĐÚNG 1 CÂU phù hợp nhất. Tuyệt đối KHÔNG tự sáng tác câu mới.
5. Nếu chuỗi đầu vào hoàn toàn là từ vô nghĩa, hãy trả về chính xác câu: "Không thể nhận diện rõ ý nghĩa."

---
DANH SÁCH CÂU CHO PHÉP (MENU):
${_allowedSentences.map((s) => "- $s").join("\n")}
---
""";

    final userPrompt =
        "Chuỗi từ khóa đầu vào: [$glossText]\nCâu dịch kết quả (Chỉ in ra câu, không giải thích):";

    try {
      final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: utf8.encode(
          jsonEncode({
            "model": "llama-3.3-70b-versatile",
            "messages": [
              {"role": "system", "content": systemPrompt},
              {"role": "user", "content": userPrompt},
            ],
            "temperature": 0.1,
          }),
        ),
      );

      if (response.statusCode == 200) {
        // Ép kiểu utf8 để tiếng Việt không bị lỗi font chữ
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        // Bóc tách kết quả từ mảng JSON của OpenRouter
        final finalSentence = data['choices'][0]['message']['content']
            .toString()
            .trim();

        debugPrint("✅ Groq chốt câu cuối cùng: $finalSentence");
        return finalSentence;
      } else {
        debugPrint(
          "❌ Máy chủ OpenRouter báo lỗi (${response.statusCode}): ${response.body}",
        );
        return "Lỗi API máy chủ (${response.statusCode}).";
      }
    } catch (e) {
      debugPrint("❌ Lỗi mạng cục bộ chi tiết: $e");
      return "Lỗi mạng hoặc kết nối dịch thuật.";
    }
  }
}
