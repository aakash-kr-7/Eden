import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final burstPlaybackServiceProvider = Provider<BurstPlaybackService>((ref) {
  return BurstPlaybackService();
});

class BurstPlaybackService {
  Future<void> playBurst(
    List<String> messages,
    List<double> delays,
    void Function(String) onMessage,
    void Function(bool) onTyping,
  ) async {
    if (messages.isEmpty) return;

    // Shows typing indicator
    onTyping(true);

    for (int i = 0; i < messages.length; i++) {
      // Get delay in seconds, fallback to 1.5 seconds if index is out of bounds
      final delaySeconds = i < delays.length ? delays[i] : 1.5;
      
      // Wait for its delay
      await Future.delayed(Duration(milliseconds: (delaySeconds * 1000).toInt()));

      // Hide typing indicator
      onTyping(false);

      // Call onMessage(text)
      onMessage(messages[i]);

      // If not last: show typing indicator again and wait briefly (1-2s)
      if (i < messages.length - 1) {
        onTyping(true);
        // Wait briefly (1-2s), using 1.2 seconds here
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }

    // On complete: ensure typing indicator is hidden
    onTyping(false);
  }
}
