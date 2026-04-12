import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  final bool showSkeleton;
  
  const SettingsState({
    this.showSkeleton = true,
  });

  SettingsState copyWith({
    bool? showSkeleton,
  }) {
    return SettingsState(
      showSkeleton: showSkeleton ?? this.showSkeleton,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void toggleSkeleton() {
    state = state.copyWith(showSkeleton: !state.showSkeleton);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
