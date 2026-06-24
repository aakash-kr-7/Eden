// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/message_bubble.dart
// PURPOSE: Renders user and partner messages per Eden design system.
// CONTEXT: Used by chat screen's message list. Two variants: user and partner.
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/eden_animations.dart';

class MessageBubble extends StatelessWidget {
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

    if (dateToCheck == today) {
      return 'today, $timeString';
    } else if (dateToCheck == yesterday) {
      return 'yesterday, $timeString';
    } else {
      if (dateTime.year == now.year) {
        final dateStr = DateFormat('MMMM d').format(dateTime).toLowerCase();
        return '$dateStr, $timeString';
      } else {
        final dateStr = DateFormat('MMMM d, yyyy').format(dateTime).toLowerCase();
        return '$dateStr, $timeString';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showTimestamp || customTimestampText != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
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
        FadeSlideIn(
          key: ValueKey('message_fade_${message.id}'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offsetY: 8.0,
          child: Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: isUser
                  ? const EdgeInsets.only(right: 20.0, left: 8.0, top: 4.0, bottom: 4.0)
                  : const EdgeInsets.only(left: 20.0, right: 8.0, top: 4.0, bottom: 4.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.75 : 0.85),
                ),
                child: isUser
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6.0),
                          topRight: Radius.circular(20.0),
                          bottomLeft: Radius.circular(20.0),
                          bottomRight: Radius.circular(20.0),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
                            decoration: BoxDecoration(
                              color: EdenColors.glassStrong,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6.0),
                                topRight: Radius.circular(20.0),
                                bottomLeft: Radius.circular(20.0),
                                bottomRight: Radius.circular(20.0),
                              ),
                              border: Border.all(
                                color: EdenColors.glassBorder,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              message.content,
                              style: EdenTypography.bodyXl.copyWith(color: EdenColors.textPrimary),
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          message.content,
                          style: EdenTypography.bodyXl.copyWith(color: EdenColors.textPartner),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
