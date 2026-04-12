import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider kiểm tra kết nối mạng theo chu kỳ (mỗi 5 giây).
/// Trả về true nếu có mạng, false nếu không.
class NetworkStatusNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    // Bắt đầu kiểm tra ngay khi khởi tạo
    _checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
    ref.onDispose(() => _timer?.cancel());
    return true; // giả sử ban đầu có mạng
  }

  Future<void> _checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final hasConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (state != hasConnection) {
        state = hasConnection;
      }
    } on SocketException catch (_) {
      if (state != false) state = false;
    } on TimeoutException catch (_) {
      if (state != false) state = false;
    }
  }
}

final networkStatusProvider = NotifierProvider<NetworkStatusNotifier, bool>(
  NetworkStatusNotifier.new,
);
