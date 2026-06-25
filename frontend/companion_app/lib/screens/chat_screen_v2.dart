// ═══════════════════════════════════════════════════════════════════
// FILE: screens/chat_screen_v2.dart
// PURPOSE: Primary conversation screen — the heart of Eden.
// CONTEXT: Replaces chat_screen.dart with human texting support.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/eden_animations.dart';
import '../models/models.dart';
import '../main.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator_v2.dart';
import '../widgets/glass_card.dart';
import '../providers/chat_provider_v3.dart';
import '../providers/session_provider.dart';

class ChatScreenV2 extends ConsumerStatefulWidget {
  const ChatScreenV2({super.key});

  @override
  ConsumerState<ChatScreenV2> createState() => _ChatScreenV2State();
}

class _ChatScreenV2State extends ConsumerState<ChatScreenV2> with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isInitializing = true;
  bool _isSending = false;
  String? _errorMessage;
  String? _lastSentText;
  double _headerOpacity = 0.0;
  bool _noConnection = false;
  int? _firstProactiveMessageId;
  bool _showSendButton = false;
  Timer? _typingTimer;
  bool _lastSentTypingState = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onInputChanged);
    _inputFocusNode.addListener(_updateUserTypingState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeChat());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _inputController.removeListener(_onInputChanged);
    _inputFocusNode.removeListener(_updateUserTypingState);
    _typingTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollProactiveMessages();
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final distanceFromBottom = maxScroll - offset;

      // Fades in when user scrolls > 100px up from the bottom
      final double targetOpacity = (distanceFromBottom > 100) ? 1.0 : 0.0;
      if (_headerOpacity != targetOpacity) {
        setState(() {
          _headerOpacity = targetOpacity;
        });
      }

      if (distanceFromBottom < 20.0) {
        _markLastMessageAsRead();
      }
    }
  }

  void _onInputChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (_showSendButton != hasText) {
      setState(() {
        _showSendButton = hasText;
      });
    }
    _updateUserTypingState();
  }

  void _updateUserTypingState() {
    final hasFocus = _inputFocusNode.hasFocus;
    final hasText = _inputController.text.trim().isNotEmpty;
    final isTyping = hasFocus && hasText && !_isSending;

    final currentTypingState = ref.read(isUserTypingProvider);
    if (currentTypingState != isTyping) {
      ref.read(isUserTypingProvider.notifier).state = isTyping;
    }

    if (isTyping) {
      if (_typingTimer == null) {
        _sendTypingStatus(true);
        _typingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _sendTypingStatus(true);
        });
      }
    } else {
      if (_typingTimer != null) {
        _typingTimer!.cancel();
        _typingTimer = null;
        _sendTypingStatus(false);
      }
    }
  }

  Future<void> _sendTypingStatus(bool isTyping) async {
    if (isTyping == _lastSentTypingState) return;
    _lastSentTypingState = isTyping;

    try {
      final conversationId = ref.read(sessionProvider).valueOrNull?.conversationId;
      if (conversationId != null) {
        await ref.read(apiServiceProvider).updateTypingStatus(conversationId, isTyping);
      }
    } catch (e) {
      debugPrint("Failed to send typing status: $e");
    }
  }

  Future<void> _markLastMessageAsRead() async {
    final messages = ref.read(messagesProvider);
    if (messages.isEmpty) return;

    final newestMsg = messages.first;
    final lastMessageId = newestMsg.id;
    final currentLastSeen = ref.read(lastSeenMessageIdProvider);

    if (lastMessageId != currentLastSeen) {
      ref.read(lastSeenMessageIdProvider.notifier).state = lastMessageId;
      
      final conversationId = ref.read(sessionProvider).valueOrNull?.conversationId;
      if (conversationId != null) {
        try {
          await ref.read(apiServiceProvider).markRead(conversationId, lastMessageId);
        } catch (e) {
          debugPrint("Failed to mark messages as read: $e");
        }
      }
    }
  }

  Future<void> _initializeChat() async {
    try {
      // 1. Load messages from local Isar cache immediately (zero loading time)
      await ref.read(messagesProvider.notifier).loadFromCache();
      _scrollToBottom(animated: false);
    } catch (e) {
      debugPrint("Error loading cache: $e");
    }

    // 2. Load session from backend in parallel
    try {
      final apiService = ref.read(apiServiceProvider);
      final session = await ref.refresh(sessionProvider.future);
      final conversationId = session.conversationId;

      // Fetch latest messages from backend
      final fetchedMessages = await apiService.getMessages(conversationId);
      final List<Message> mergedMessages = List.from(fetchedMessages);

      // 3. Handle unread proactive messages
      if (session.unreadProactive.isNotEmpty) {
        for (var pm in session.unreadProactive) {
          final pmId = int.tryParse(pm.id) ?? pm.id.hashCode;
          if (!mergedMessages.any((m) => m.id == pmId)) {
            mergedMessages.add(Message(
              id: pmId,
              conversationId: conversationId,
              role: MessageRole.partner,
              content: pm.message,
              sentAt: pm.sentAt,
            ));
          }
        }

        // Sort chronologically (newest first for provider list representation)
        mergedMessages.sort((a, b) => b.sentAt.compareTo(a.sentAt));

        // Track the first proactive message to display "X days/hours ago"
        final oldestProactive = session.unreadProactive.reduce(
          (a, b) => a.sentAt.isBefore(b.sentAt) ? a : b,
        );
        _firstProactiveMessageId = int.tryParse(oldestProactive.id) ?? oldestProactive.id.hashCode;
      }

      // Initialize provider state
      ref.read(messagesProvider.notifier).setMessages(mergedMessages);

      // Save messages to local cache
      await ref.read(localCacheServiceProvider).saveMessages(mergedMessages);

      // Acknowledge proactive messages
      for (var pm in session.unreadProactive) {
        try {
          await apiService.acknowledgeProactive(pm.id);
        } catch (e) {
          debugPrint("Failed to acknowledge proactive: $e");
        }
      }

      setState(() {
        _noConnection = false;
        _errorMessage = null;
      });

      _scrollToBottom(animated: true);
    } catch (e) {
      debugPrint("Error initializing session: $e");
      setState(() {
        _noConnection = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _pollProactiveMessages() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final proactive = await apiService.getPendingProactive();
      if (proactive.isNotEmpty && mounted) {
        final messages = ref.read(messagesProvider);
        for (var pm in proactive) {
          final pmId = int.tryParse(pm.id) ?? pm.id.hashCode;
          if (!messages.any((m) => m.id == pmId)) {
            final pmMessage = Message(
              id: pmId,
              conversationId: ref.read(sessionProvider).valueOrNull?.conversationId ?? '',
              role: MessageRole.partner,
              content: pm.message,
              sentAt: pm.sentAt,
            );
            await ref.read(messagesProvider.notifier).addMessage(pmMessage);
          }
          await apiService.acknowledgeProactive(pm.id);
        }
        _scrollToBottom(animated: true);
      }
    } catch (_) {}
  }

  Future<void> _sendMessage({String? retryText}) async {
    final text = retryText ?? _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    if (retryText == null) {
      _inputController.clear();
      _showSendButton = false;
      _updateUserTypingState();
    }

    _lastSentText = text;
    HapticFeedback.lightImpact();

    // Clear and unfocus
    FocusScope.of(context).unfocus();

    setState(() {
      _isSending = true;
      _errorMessage = null;
      _noConnection = false;
    });

    try {
      final conversationId = ref.read(sessionProvider).valueOrNull?.conversationId;
      await ref.read(messagesProvider.notifier).sendMessage(conversationId, text);
      _scrollToBottom(animated: true);
    } catch (e) {
      debugPrint("Error sending message: $e");
      setState(() {
        _errorMessage = "something went wrong — tap to retry";
        _noConnection = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _retrySendMessage() {
    if (_lastSentText != null) {
      _sendMessage(retryText: _lastSentText);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        if (animated) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ).then((_) {
            _markLastMessageAsRead();
          });
        } else {
          _scrollController.jumpTo(target);
          _markLastMessageAsRead();
        }
      }
    });
  }

  bool _shouldShowTimestamp(List<Message> messages, int index) {
    if (index == 0) {
      return true; // oldest message
    }
    final current = messages[messages.length - 1 - index];
    
    // Sub-bursts shouldn't get individual timestamps to match clean flow (e.g. WhatsApp)
    if (current.isPartOfBurst && current.burstIndex != null && current.burstIndex! > 0) {
      return false;
    }
    
    final prev = messages[messages.length - index];
    final difference = current.sentAt.difference(prev.sentAt).abs();
    return difference.inHours >= 4;
  }

  String _formatMood(String? mood) {
    if (mood == null || mood.trim().isEmpty) return 'present';
    final firstMood = mood.split(',').first.trim().toLowerCase();
    if (firstMood == 'neutral' || firstMood == 'peaceful') {
      return 'present';
    }
    return '$firstMood today';
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    final isTyping = ref.watch(isTypingProvider);
    final streamingText = ref.watch(streamingTextProvider);
    final partner = ref.watch(partnerProvider);

    final showTyping = isTyping && streamingText.isEmpty;
    final showStreaming = isTyping && streamingText.isNotEmpty;
    final hasError = _errorMessage != null;

    final listCount = messages.length +
        (showTyping || showStreaming ? 1 : 0) +
        (hasError ? 1 : 0);

    return KeyboardVisibilityBuilder(
      builder: (context, isKeyboardVisible) {
        if (isKeyboardVisible) {
          _scrollToBottom(animated: true);
        }
        return Scaffold(
          backgroundColor: EdenColors.edenVoid,
          resizeToAvoidBottomInset: true,
          body: BreathingBackground(
            baseColor: EdenColors.edenVoid,
            child: SafeArea(
              child: Stack(
                children: [
                  _buildMessageList(messages, listCount, showTyping, showStreaming, hasError, partner),
                  _buildPartnerHeader(partner, showTyping),
                  if (_noConnection) _buildNoConnectionBanner(),
                  _buildInputArea(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPartnerHeader(Partner? partner, bool showTyping) {
    final partnerName = partner?.name ?? 'Eden';
    final partnerMood = _formatMood(partner?.currentMood);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: _headerOpacity == 0.0,
        child: AnimatedOpacity(
          opacity: _headerOpacity,
          duration: const Duration(milliseconds: 200),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
              child: Container(
                height: 80.0,
                decoration: const BoxDecoration(
                  color: EdenColors.glassLight,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          partnerName,
                          style: EdenTypography.displayMd.copyWith(color: EdenColors.textPrimary),
                        ),
                        const SizedBox(height: 2.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!showTyping) ...[
                              Container(
                                width: 6.0,
                                height: 6.0,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: EdenColors.semanticSuccess,
                                ),
                              ),
                              const SizedBox(width: 6.0),
                            ],
                            Text(
                              showTyping ? "typing..." : "$partnerName · $partnerMood",
                              style: EdenTypography.bodySm.copyWith(
                                color: showTyping ? EdenColors.presenceBlue : EdenColors.textSecondary,
                                fontStyle: showTyping ? FontStyle.italic : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                            color: EdenColors.textSecondary.withValues(alpha: 0.6),
                            onPressed: () => context.push('/memories'),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, size: 20),
                            color: EdenColors.textSecondary.withValues(alpha: 0.6),
                            onPressed: () => context.push('/settings'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(
    List<Message> messages,
    int listCount,
    bool showTyping,
    bool showStreaming,
    bool hasError,
    Partner? partner,
  ) {
    if (_isInitializing) {
      return Center(
        child: FadeSlideIn(
          duration: const Duration(milliseconds: 300),
          child: Text(
            "gathering presence…",
            style: EdenTypography.bodySm.copyWith(
              color: EdenColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    if (messages.isEmpty && !showTyping && !showStreaming && !hasError) {
      final partnerName = partner?.name ?? 'Eden';
      return Center(
        child: FadeSlideIn(
          delay: const Duration(milliseconds: 400),
          duration: const Duration(milliseconds: 300),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                partnerName,
                style: EdenTypography.displayLg.copyWith(color: EdenColors.textPrimary),
              ),
              const SizedBox(height: 8.0),
              Text(
                "say something",
                style: EdenTypography.bodySm.copyWith(color: EdenColors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: false,
      padding: const EdgeInsets.only(
        top: 80.0,
        bottom: 120.0,
      ),
      itemCount: listCount,
      itemBuilder: (context, index) {
        // Error state centered link at very bottom
        if (hasError && index == listCount - 1) {
          return FadeSlideIn(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: GestureDetector(
              onTap: _retrySendMessage,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    _errorMessage!,
                    style: EdenTypography.bodySm.copyWith(
                      color: EdenColors.textTertiary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // Typing indicator or streaming text bubble
        if (showTyping || showStreaming) {
          final indicatorIndex = hasError ? listCount - 2 : listCount - 1;
          if (index == indicatorIndex) {
            if (showTyping) {
              final isFollowUp = ref.watch(currentBurstIndexProvider) > 0;
              final overrideDurationMs = ref.watch(typingDurationProvider);
              final overrideDuration = overrideDurationMs != null 
                  ? Duration(milliseconds: overrideDurationMs) 
                  : null;
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20.0, top: 12.0, bottom: 12.0),
                  child: TypingIndicatorV2(
                    isActive: true,
                    isFollowUp: isFollowUp,
                    overrideDuration: overrideDuration,
                    dotSize: 8.0,
                    spacing: 6.0,
                  ),
                ),
              );
            } else {
              final streamingText = ref.read(streamingTextProvider);
              return Container(
                margin: const EdgeInsets.only(left: 20.0, right: 8.0, top: 4.0, bottom: 4.0),
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                  ),
                  child: FadeSlideIn(
                    key: const ValueKey('streaming_text_bubble'),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    offsetY: 8.0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        streamingText,
                        style: EdenTypography.bodyXl.copyWith(color: EdenColors.textPartner),
                      ),
                    ),
                  ),
                ),
              );
            }
          }
        }

        // Regular message rendering
        final msgIndex = messages.length - 1 - index;
        final msg = messages[msgIndex];
        final showTimestamp = _shouldShowTimestamp(messages, index);

        String? customTimestampText;
        if (msg.id == _firstProactiveMessageId) {
          final diff = DateTime.now().difference(msg.sentAt);
          if (diff.inDays >= 1) {
            customTimestampText = '${diff.inDays} ${diff.inDays == 1 ? "day" : "days"} ago';
          } else if (diff.inHours >= 1) {
            customTimestampText = '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
          } else {
            customTimestampText = 'just now';
          }
        }

        return MessageBubble(
          key: ValueKey('bubble_${msg.id}'),
          message: msg,
          showTimestamp: showTimestamp || customTimestampText != null,
          customTimestampText: customTimestampText,
        );
      },
    );
  }

  Widget _buildNoConnectionBanner() {
    return Positioned(
      top: 90.0,
      left: 20.0,
      right: 20.0,
      child: IgnorePointer(
        ignoring: true,
        child: FadeSlideIn(
          duration: const Duration(milliseconds: 300),
          child: Center(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              borderRadius: 14.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 16.0, color: EdenColors.textSecondary),
                  const SizedBox(width: 8.0),
                  Text(
                    "no connection",
                    style: EdenTypography.bodySm.copyWith(color: EdenColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final isComposing = ref.watch(isComposingProvider);
    final isTyping = ref.watch(isTypingProvider);
    final partner = ref.watch(partnerProvider);
    final partnerName = partner?.name.toLowerCase() ?? 'partner';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: Container(
            color: EdenColors.glassLight,
            padding: EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 8.0,
              bottom: MediaQuery.of(context).padding.bottom + 8.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isComposing && isTyping)
                  Padding(
                    padding: const EdgeInsets.only(left: 20.0, bottom: 6.0),
                    child: FadeSlideIn(
                      duration: const Duration(milliseconds: 150),
                      offsetY: 4.0,
                      child: Text(
                        '$partnerName is typing...',
                        style: EdenTypography.bodySm.copyWith(
                          color: EdenColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: EdenColors.edenElevated,
                          borderRadius: BorderRadius.circular(28.0),
                        ),
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          readOnly: isComposing, // Disable editing while composing
                          style: EdenTypography.bodyXl.copyWith(
                            color: isComposing ? EdenColors.textSecondary : EdenColors.textPrimary,
                          ),
                          maxLines: 4,
                          minLines: 1,
                          cursorColor: EdenColors.edenIris,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: EdenColors.edenElevated,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                            hintText: '',
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: EdenColors.edenIris, width: 1.0),
                              borderRadius: BorderRadius.circular(28.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
                              borderRadius: BorderRadius.circular(28.0),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
                              borderRadius: BorderRadius.circular(28.0),
                            ),
                            border: OutlineInputBorder(
                              borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
                              borderRadius: BorderRadius.circular(28.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    AnimatedOpacity(
                      opacity: (_showSendButton && !isComposing) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_showSendButton || isComposing,
                        child: GestureDetector(
                          onTap: () => _sendMessage(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: EdenColors.edenIris,
                            ),
                            child: const Icon(
                              Icons.arrow_upward,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
