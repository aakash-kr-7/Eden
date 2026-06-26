import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../models/models.dart';
import '../providers/chat_provider_v3.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/glass_theme.dart';

class MessageBubble extends ConsumerWidget {
  final Message message;
  final bool showTimestamp;
  final String? customTimestampText;

  const MessageBubble({
    super.key,
    required this.message,
    required this.showTimestamp,
    this.customTimestampText,
  });

  String _formatMessageTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final timeString = DateFormat('h:mm a').format(dateTime).toLowerCase();

    if (dateToCheck == today) return 'today, $timeString';
    if (dateToCheck == yesterday) return 'yesterday, $timeString';
    final pattern = dateTime.year == now.year ? 'MMMM d' : 'MMMM d, yyyy';
    return '${DateFormat(pattern).format(dateTime).toLowerCase()}, $timeString';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.isUser;
    final messages = ref.watch(messagesProvider);
    final isPartnerTyping = ref.watch(isTypingProvider);
    final isOptimistic = message.id > 1000000000000;

    var isSeen = false;
    if (isUser) {
      isSeen = messages.any((m) =>
          m.role == MessageRole.partner && m.sentAt.isAfter(message.sentAt));
      if (!isSeen) isSeen = isPartnerTyping;
    }

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showTimestamp || customTimestampText != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                customTimestampText ?? _formatMessageTimestamp(message.sentAt),
                style: EdenTypography.bodySm.copyWith(
                  color: EdenColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              left: isUser ? 56 : 20,
              right: isUser ? 20 : 56,
              top: 4,
              bottom: 4,
            ),
            child: FakeGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 16),
              settings: isUser
                  ? const LiquidGlassSettings(
                      thickness: 18,
                      blur: 12,
                      glassColor: Color(0x20FFFFFF),
                      saturation: 1.3,
                      refractiveIndex: 1.45,
                      lightIntensity: 1.3,
                    )
                  : GlassTheme.card,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: EdenTypography.bodyLg.copyWith(
                        color: isUser
                            ? EdenColors.textPrimary
                            : EdenColors.textPartner,
                      ),
                    ),
                    if (isUser) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('h:mm a')
                                .format(message.sentAt)
                                .toLowerCase(),
                            style: EdenTypography.bodySm.copyWith(
                              color: EdenColors.textSecondary
                                  .withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isOptimistic ? Icons.done : Icons.done_all,
                            size: 14,
                            color: isSeen
                                ? EdenColors.presenceBlue
                                : EdenColors.textSecondary
                                    .withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
