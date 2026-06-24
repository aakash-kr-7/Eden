import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../theme/eden_theme.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool showTimestamp;

  const MessageBubble({
    super.key,
    required this.message,
    required this.showTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;
    final String formattedTime = DateFormat('jm').format(message.sentAt);

    if (!isUser) {
      // Partner message
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Text(
                message.content,
                style: EdenTheme.bodyLarge,
              ),
            ),
            if (showTimestamp)
              Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                child: Text(
                  formattedTime,
                  style: EdenTheme.labelSmall.copyWith(color: EdenTheme.textTertiary),
                ),
              ),
          ],
        ),
      );
    } else {
      // User message
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
              decoration: const BoxDecoration(
                color: EdenTheme.bgElevated,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4.0),
                  topRight: Radius.circular(18.0),
                  bottomLeft: Radius.circular(18.0),
                  bottomRight: Radius.circular(18.0),
                ),
              ),
              child: Text(
                message.content,
                style: EdenTheme.bodyLarge,
              ),
            ),
            if (showTimestamp)
              Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                child: Text(
                  formattedTime,
                  style: EdenTheme.labelSmall.copyWith(color: EdenTheme.textTertiary),
                ),
              ),
          ],
        ),
      );
    }
  }
}
