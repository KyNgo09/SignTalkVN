import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

final groqServiceProvider = Provider<GroqService>(
  (ref) => GroqService(),
);

class GroqService {
  late final String _apiKey;

  // --- BỔ SUNG: BẢNG TỪ ĐIỂN MAPPING ---
  static const Map<String, String> _vnLabelMap = {
    'AN': 'Ăn', 'BAC_SI': 'Bác sĩ', 'BAN': 'Bạn', 'BAO_NHIEU': 'Bao nhiêu',
    'BUON': 'Buồn', 'CAM_ON': 'Cảm ơn', 'CHA': 'Cha', 'DAU': 'Đau',
    'DI': 'Đi', 'GHET': 'Ghét', 'GI': 'Gì', 'GIAO_VIEN': 'Giáo viên',
    'HEN_GAP_LAI': 'Hẹn gặp lại', 'HIEU': 'Hiểu', 'HOC': 'Học',
    'KHI_NAO': 'Khi nào', 'KHOE': 'Khỏe', 'LAM': 'Làm', 'ME': 'Mẹ',
    'MET': 'Mệt', 'NGU': 'Ngủ', 'O_DAU': 'Ở đâu', 'TAM_BIET': 'Tạm biệt',
    'THICH': 'Thích', 'TOI': 'Tôi', 'UONG': 'Uống', 'VE': 'Về',
    'VUI': 'Vui', 'XIN_CHAO': 'Xin chào', 'XIN_LOI': 'Xin lỗi', 'YEU': 'Yêu',
  };

  // DANH SÁCH MENU CÂU ĐÁP ÁN (Tối ưu từ 31 nhãn)
  static const List<String> _allowedSentences = [
    "Xin chào, bạn khỏe không?",
    "Tôi khỏe, cảm ơn bạn.",
    "Tạm biệt, hẹn gặp lại.",
    "Tôi cảm thấy rất vui.",
    "Hôm nay tôi thấy buồn.",
    "Tôi đang cảm thấy mệt.",
    "Tôi đi học rất vui.",
    "Tôi bị đau.",
    "Tôi yêu mẹ tôi.",
    "Tôi yêu cha tôi.",
    "Bạn đang làm gì?",
    "Tôi đi về.",
    "Mời bạn ăn uống.",
    "Tôi buồn ngủ ngủ.",
    "Cái này giá bao nhiêu?",
    "Bạn đi đâu?",
    "Khi nào bạn đi?",
    "Tôi hiểu.",
    "Tôi xin lỗi.",
    "Mẹ tôi là giáo viên.",
    "Cha tôi là bác sĩ."
  ];

  GroqService() {
    _apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    debugPrint(
      "🔑 API Key Groq đang dùng: ${_apiKey.isNotEmpty ? _apiKey.substring(0, 10) + '...' : 'RỖNG'}",
    );

    if (_apiKey.isEmpty) {
      debugPrint('❗ GROQ_API_KEY chưa được cấu hình trong .env');
    }
  }

  // --- CƠ CHẾ DỰ PHÒNG NGOẠI TUYẾN (OFFLINE FALLBACK) ---
  String _removeVietnameseDiacritics(String str) {
    const withDiacritics = 'aăâáắấàằầảẳẩãẵẫạặậeêéếèềẻểẽễẹệiíìỉĩịoôơóốớòồờỏổởõỗỡọộợuưúứùừủửũữụựyýỳỷỹỵđ';
    const withoutDiacritics = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuuyyyyyyd';
    str = str.toLowerCase();
    for (int i = 0; i < withDiacritics.length; i++) {
      str = str.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return str;
  }

  String _processOfflineFallback(List<String> inputWords) {
    debugPrint("⚠️ Kích hoạt cơ chế Dịch Ngoại Tuyến (Offline Fallback).");
    if (inputWords.isEmpty) return "";

    // 1. Loại bỏ gạch dưới (_) và viết thường cho từ khóa đầu vào
    final normalizedInputs = inputWords.map((e) => e.replaceAll('_', ' ').toLowerCase()).toList();

    int maxScore = 0;
    String bestMatchedSentence = "";

    // 2. Thuật toán so khớp: Quét qua toàn bộ danh sách câu cho phép
    for (String sentence in _allowedSentences) {
      int currentScore = 0;
      // Chuyển toàn bộ câu mẫu về không dấu để dễ so sánh với từ khóa không dấu
      String unaccentedSentence = _removeVietnameseDiacritics(sentence);

      // Kiểm tra xem câu này chứa bao nhiêu từ khóa đầu vào
      for (String word in normalizedInputs) {
        String unaccentedWord = _removeVietnameseDiacritics(word);
        if (unaccentedSentence.contains(unaccentedWord)) {
          currentScore++;
        }
      }

      // Cập nhật câu có điểm cao nhất
      if (currentScore > maxScore) {
        maxScore = currentScore;
        bestMatchedSentence = sentence;
      }
    }

    // 3. Nếu tìm thấy câu khớp (ít nhất 1 từ) -> Trả về câu chuẩn trong Menu
    if (maxScore > 0) {
      debugPrint("🔍 Offline so khớp thành công với điểm số: $maxScore");
      return "[Ngoại tuyến] $bestMatchedSentence";
    }

    // 4. Fallback cấp 2: Nếu không khớp bất kỳ câu nào -> Nối chuỗi cơ bản loại bỏ nhiễu
    debugPrint("🔍 Offline không khớp câu nào, dùng cơ chế nối chuỗi.");
    String fallbackSentence = normalizedInputs.join(" ");
    if (fallbackSentence.isNotEmpty) {
      fallbackSentence = fallbackSentence[0].toUpperCase() + fallbackSentence.substring(1) + ".";
    }
    return "[Ngoại tuyến] $fallbackSentence";
  }

  Future<String> translateGlossToSentence(List<String> inputList) async {
    if (inputList.isEmpty) return "";
    
    // Nếu không có API Key, chạy luôn chế độ Offline
    if (_apiKey.isEmpty) {
      return _processOfflineFallback(inputList);
    }

    final inputText = inputList.join(", ");
    debugPrint("💬 Gửi chuỗi dữ liệu lên Groq: $inputText");

    // --- BỔ SUNG: CHUẨN BỊ CHUỖI MAP CHO PROMPT ---
    final mapContext = _vnLabelMap.entries.map((e) => "- ${e.key} nghĩa là: ${e.value}").join("\n");

    final systemPrompt =
        """
Bạn là một chuyên gia ngôn ngữ học và biên dịch Ngôn ngữ Ký hiệu Việt Nam (VSL) cấp cao. 
Nhiệm vụ của bạn là nhận một chuỗi các từ khóa được trích xuất từ camera AI, sau đó chọn ra 1 câu khớp ý nghĩa nhất từ danh sách cho phép.

📖 BẢNG TỪ ĐIỂN ĐỐI CHIẾU Ý NGHĨA (QUAN TRỌNG):
Dưới đây là ý nghĩa tiếng Việt của các mã từ khóa AI có thể trả về:
$mapContext

⚠️ ĐẶC ĐIỂM DỮ LIỆU ĐẦU VÀO:
- Do AI nhận diện qua video, chuỗi từ khóa chắc chắn sẽ chứa các "từ nhiễu".
- Ví dụ: Chuỗi [XIN_CHAO, AN, KHOE] thì chữ "AN" là nhiễu, ý chính vẫn là "Xin chào, bạn khỏe không?".

🧠 NHIỆM VỤ CỦA BẠN:
1. Đọc chuỗi đầu vào, phân tích ngữ cảnh để TỰ ĐỘNG BỎ QUA các từ nhiễu.
2. Nắm bắt "ý nghĩa cốt lõi" của các từ khóa chính dựa vào BẢNG TỪ ĐIỂN ở trên.
3. Đối chiếu ý nghĩa đó với DANH SÁCH CÂU CHO PHÉP bên dưới.
4. Chọn ra ĐÚNG 1 CÂU phù hợp nhất. Tuyệt đối KHÔNG tự sáng tác câu mới.
5. Nếu chuỗi hoàn toàn vô nghĩa, hãy trả về: "Không thể nhận diện rõ ý nghĩa."

---
DANH SÁCH CÂU CHO PHÉP:
${_allowedSentences.map((s) => "- $s").join("\n")}
---
""";

    final userPrompt =
        "Chuỗi từ khóa đầu vào: [$inputText]\nCâu dịch kết quả (Chỉ in ra câu, không giải thích):";

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
      ).timeout(const Duration(seconds: 10)); 

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final finalSentence = data['choices'][0]['message']['content']
            .toString()
            .trim();

        debugPrint("✅ Groq chốt câu cuối cùng: $finalSentence");
        return finalSentence;
      } else {
        debugPrint("❌ Máy chủ Groq báo lỗi (${response.statusCode}): ${response.body}");
        return _processOfflineFallback(inputList);
      }
    } on SocketException catch (_) {
      debugPrint("❌ Không có kết nối mạng (SocketException).");
      return _processOfflineFallback(inputList);
    } catch (e) {
      debugPrint("❌ Lỗi ngoại lệ: $e");
      return _processOfflineFallback(inputList);
    }
  }
}