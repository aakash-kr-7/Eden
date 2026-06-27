// FILE: screens/chat_screen.dart
// PURPOSE: Present the flagship conversation experience while preserving existing chat integrations.
// RESPONSIBILITIES: Render chat, stream provider-backed message state, and route profile and memory access.
// NEVER: Change backend contracts, provider interfaces, or global app bootstrap rules.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../models/models.dart';
import '../providers/chat_provider_v3.dart';
import '../providers/session_provider.dart';
import '../theme/nocturne.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isInitializing = true;
  bool _isSending = false;
  bool _noConnection = false;
  bool _showSendButton = false;
  String? _errorMessage;
  String? _lastSentText;
  int? _firstProactiveMessageId;
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
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final distanceFromBottom = maxScroll - offset;

    if (distanceFromBottom < 20.0) {
      _markLastMessageAsRead();
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
        _typingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          _sendTypingStatus(true);
        });
      }
    } else if (_typingTimer != null) {
      _typingTimer!.cancel();
      _typingTimer = null;
      _sendTypingStatus(false);
    }
  }

  Future<void> _sendTypingStatus(bool isTyping) async {
    if (isTyping == _lastSentTypingState) return;
    _lastSentTypingState = isTyping;

    try {
      final conversationId =
          ref.read(sessionProvider).valueOrNull?.conversationId;
      if (conversationId != null) {
        await ref
            .read(apiServiceProvider)
            .updateTypingStatus(conversationId, isTyping);
      }
    } catch (e) {
      debugPrint('Failed to send typing status: $e');
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

      final conversationId =
          ref.read(sessionProvider).valueOrNull?.conversationId;
      if (conversationId != null) {
        try {
          await ref
              .read(apiServiceProvider)
              .markRead(conversationId, lastMessageId);
        } catch (e) {
          debugPrint('Failed to mark messages as read: $e');
        }
      }
    }
  }

  Future<void> _initializeChat() async {
    try {
      await ref.read(messagesProvider.notifier).loadFromCache();
      _scrollToBottom(animated: false);
    } catch (e) {
      debugPrint('Error loading cache: $e');
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      final session = await ref.refresh(sessionProvider.future);
      final conversationId = session.conversationId;
      final fetchedMessages = await apiService.getMessages(conversationId);
      final mergedMessages = List<Message>.from(fetchedMessages);

      if (session.unreadProactive.isNotEmpty) {
        for (final pm in session.unreadProactive) {
          final pmId = int.tryParse(pm.id) ?? pm.id.hashCode;
          if (!mergedMessages.any((message) => message.id == pmId)) {
            mergedMessages.add(
              Message(
                id: pmId,
                conversationId: conversationId,
                role: MessageRole.partner,
                content: pm.message,
                sentAt: pm.sentAt,
              ),
            );
          }
        }

        mergedMessages.sort((a, b) => b.sentAt.compareTo(a.sentAt));

        final oldestProactive = session.unreadProactive.reduce(
          (a, b) => a.sentAt.isBefore(b.sentAt) ? a : b,
        );
        _firstProactiveMessageId =
            int.tryParse(oldestProactive.id) ?? oldestProactive.id.hashCode;
      }

      ref.read(messagesProvider.notifier).setMessages(mergedMessages);
      await ref.read(localCacheServiceProvider).saveMessages(mergedMessages);

      for (final pm in session.unreadProactive) {
        try {
          await apiService.acknowledgeProactive(pm.id);
        } catch (e) {
          debugPrint('Failed to acknowledge proactive: $e');
        }
      }

      setState(() {
        _noConnection = false;
        _errorMessage = null;
      });

      _scrollToBottom(animated: true);
    } catch (e) {
      debugPrint('Error initializing session: $e');
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
        for (final pm in proactive) {
          final pmId = int.tryParse(pm.id) ?? pm.id.hashCode;
          if (!messages.any((message) => message.id == pmId)) {
            final pmMessage = Message(
              id: pmId,
              conversationId:
                  ref.read(sessionProvider).valueOrNull?.conversationId ?? '',
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
    FocusScope.of(context).unfocus();

    setState(() {
      _isSending = true;
      _errorMessage = null;
      _noConnection = false;
    });

    try {
      final conversationId =
          ref.read(sessionProvider).valueOrNull?.conversationId;
      await ref
          .read(messagesProvider.notifier)
          .sendMessage(conversationId, text);
      _scrollToBottom(animated: true);
    } catch (e) {
      debugPrint('Error sending message: $e');
      setState(() {
        _errorMessage = 'Something went wrong. Tap to try again.';
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
      if (!_scrollController.hasClients) return;

      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController
            .animateTo(
          target,
          duration: Nocturne.durationStandard,
          curve: Curves.easeOut,
        )
            .then((_) {
          _markLastMessageAsRead();
        });
      } else {
        _scrollController.jumpTo(target);
        _markLastMessageAsRead();
      }
    });
  }

  bool _shouldShowTimestamp(List<Message> messages, int index) {
    if (index == 0) return true;
    final current = messages[messages.length - 1 - index];

    if (current.isPartOfBurst &&
        current.burstIndex != null &&
        current.burstIndex! > 0) {
      return false;
    }

    final previous = messages[messages.length - index];
    final difference = current.sentAt.difference(previous.sentAt).abs();
    return difference.inHours >= 4;
  }

  String _presenceLine(Partner? partner) {
    final partnerName = partner?.name ?? 'Eden';
    final combined =
        '${partner?.currentMood ?? ''} ${partner?.currentEnergy ?? ''}'
            .toLowerCase();

    if (combined.contains('sleep') ||
        combined.contains('rest') ||
        combined.contains('tired') ||
        combined.contains('quiet')) {
      return '$partnerName is sleeping.';
    }

    if (combined.contains('focus') ||
        combined.contains('curious') ||
        combined.contains('thought') ||
        combined.contains('calm')) {
      return '$partnerName is reading.';
    }

    if (combined.contains('bright') ||
        combined.contains('open') ||
        combined.contains('play') ||
        combined.contains('warm')) {
      return '$partnerName is outside.';
    }

    const fallbacks = ['sleeping', 'reading', 'outside'];
    final fallback = fallbacks[partnerName.length % fallbacks.length];
    return '$partnerName is $fallback.';
  }

  String _relationshipLine(Partner? partner) {
    final partnerName = partner?.name ?? 'Eden';
    final daysTogether = partner?.daysTogether ?? 0;
    if (daysTogether > 0) {
      return '$partnerName, day $daysTogether';
    }
    return 'A quiet place for the two of you';
  }

  String _typingActivityLabel({
    required String partnerName,
    required bool isFollowUp,
    required int? overrideDurationMs,
  }) {
    if (overrideDurationMs != null && overrideDurationMs > 1400) {
      return '$partnerName hesitates...';
    }
    if (isFollowUp) {
      return '$partnerName writing...';
    }
    return '$partnerName thinking...';
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
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Stack(
              children: [
                const _ChatBackdrop(),
                Column(
                  children: [
                    _buildHeader(partner),
                    Expanded(
                      child: _buildMessageList(
                        messages,
                        listCount,
                        showTyping,
                        showStreaming,
                        hasError,
                        partner,
                      ),
                    ),
                  ],
                ),
                if (_noConnection) _buildNoConnectionBanner(),
                _buildInputArea(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Partner? partner) {
    final partnerName = partner?.name ?? 'Eden';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Nocturne.space6,
        Nocturne.space5,
        Nocturne.space6,
        Nocturne.space6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderActionButton(
            icon: Icons.person_outline_rounded,
            tooltip: 'Profile',
            onPressed: () => context.push(AppRoute.profile),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  partnerName,
                  style: Nocturne.displayMd.copyWith(fontSize: 30),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Nocturne.space2),
                Text(
                  _presenceLine(partner),
                  style: Nocturne.label.copyWith(
                    color: Nocturne.textTertiary,
                    letterSpacing: 0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          _HeaderActionButton(
            icon: Icons.bookmark_border_rounded,
            tooltip: 'Memory',
            onPressed: () => context.push(AppRoute.memory),
          ),
        ],
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
    final partnerName = partner?.name ?? 'Eden';

    if (_isInitializing) {
      return const Center(
        child: _QuietLoadingState(label: 'Gathering presence...'),
      );
    }

    if (messages.isEmpty && !showTyping && !showStreaming && !hasError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          Nocturne.space8,
          Nocturne.space9,
          Nocturne.space8,
          180,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _presenceLine(partner),
              style: Nocturne.label.copyWith(color: Nocturne.textTertiary),
            ),
            const SizedBox(height: Nocturne.space7),
            Text(
              partnerName,
              style: Nocturne.displayXl,
            ),
            const SizedBox(height: Nocturne.space4),
            Text(
              'The conversation starts softly here.',
              style: Nocturne.bodyLg.copyWith(color: Nocturne.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Nocturne.space8,
        Nocturne.space5,
        Nocturne.space8,
        170,
      ),
      itemCount: listCount + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Nocturne.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _presenceLine(partner),
                  style: Nocturne.label.copyWith(color: Nocturne.textTertiary),
                ),
                const SizedBox(height: Nocturne.space2),
                Text(
                  _relationshipLine(partner),
                  style:
                      Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
                ),
              ],
            ),
          );
        }

        final adjustedIndex = index - 1;

        if (hasError && adjustedIndex == listCount - 1) {
          return Padding(
            padding: const EdgeInsets.only(top: Nocturne.space6),
            child: GestureDetector(
              onTap: _retrySendMessage,
              behavior: HitTestBehavior.opaque,
              child: Text(
                _errorMessage!,
                style: Nocturne.bodySm.copyWith(
                  color: Nocturne.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: Nocturne.textSecondary,
                ),
              ),
            ),
          );
        }

        if (showTyping || showStreaming) {
          final indicatorIndex = hasError ? listCount - 2 : listCount - 1;
          if (adjustedIndex == indicatorIndex) {
            if (showTyping) {
              final isFollowUp = ref.watch(currentBurstIndexProvider) > 0;
              final overrideDurationMs = ref.watch(typingDurationProvider);
              return Padding(
                padding: const EdgeInsets.only(top: Nocturne.space6),
                child: _TextualTypingIndicator(
                  label: _typingActivityLabel(
                    partnerName: partnerName,
                    isFollowUp: isFollowUp,
                    overrideDurationMs: overrideDurationMs,
                  ),
                ),
              );
            }

            final text = ref.read(streamingTextProvider);
            return _MessageBubble(
              message: Message(
                id: -1,
                role: MessageRole.partner,
                content: text,
                sentAt: DateTime.now(),
              ),
              showTimestamp: false,
            );
          }
        }

        final messageIndex = messages.length - 1 - adjustedIndex;
        final message = messages[messageIndex];
        final showTimestamp = _shouldShowTimestamp(messages, adjustedIndex);

        String? customTimestampText;
        if (message.id == _firstProactiveMessageId) {
          final diff = DateTime.now().difference(message.sentAt);
          if (diff.inDays >= 1) {
            customTimestampText =
                '${diff.inDays} ${diff.inDays == 1 ? "day" : "days"} ago';
          } else if (diff.inHours >= 1) {
            customTimestampText =
                '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
          } else {
            customTimestampText = 'just now';
          }
        }

        return _MessageBubble(
          key: ValueKey('bubble_${message.id}'),
          message: message,
          showTimestamp: showTimestamp || customTimestampText != null,
          customTimestampText: customTimestampText,
        );
      },
    );
  }

  Widget _buildNoConnectionBanner() {
    return Positioned(
      top: 108,
      left: Nocturne.space8,
      right: Nocturne.space8,
      child: IgnorePointer(
        ignoring: true,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Nocturne.space5,
              vertical: Nocturne.space3,
            ),
            decoration: BoxDecoration(
              color: Nocturne.bgOverlay,
              borderRadius: BorderRadius.circular(Nocturne.radiusPill),
              border: Border.all(color: Nocturne.borderSubtle),
            ),
            child: Text(
              'No connection',
              style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final isComposing = ref.watch(isComposingProvider);
    final isTyping = ref.watch(isTypingProvider);
    final currentBurstIndex = ref.watch(currentBurstIndexProvider);
    final typingDuration = ref.watch(typingDurationProvider);
    final partner = ref.watch(partnerProvider);
    final partnerName = partner?.name ?? 'Eden';

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          Nocturne.space6,
          Nocturne.space5,
          Nocturne.space6,
          MediaQuery.of(context).padding.bottom + Nocturne.space5,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.68),
              Colors.black.withValues(alpha: 0.92),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isComposing && isTyping)
              Padding(
                padding: const EdgeInsets.only(
                  left: Nocturne.space4,
                  bottom: Nocturne.space3,
                ),
                child: Text(
                  _typingActivityLabel(
                    partnerName: partnerName,
                    isFollowUp: currentBurstIndex > 0,
                    overrideDurationMs: typingDuration,
                  ),
                  style: Nocturne.bodySm.copyWith(
                    color: Nocturne.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0B0D),
                borderRadius: BorderRadius.circular(Nocturne.radiusLg),
                border: Border.all(color: Nocturne.borderSubtle),
                boxShadow: Nocturne.elevationMedium,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Nocturne.space5,
                  Nocturne.space3,
                  Nocturne.space3,
                  Nocturne.space3,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        readOnly: isComposing,
                        style: Nocturne.bodyXl.copyWith(
                          color: isComposing
                              ? Nocturne.textSecondary
                              : Nocturne.textPrimary,
                        ),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: Nocturne.accentCool,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Say what you mean',
                          hintStyle: Nocturne.bodyLg.copyWith(
                            color: Nocturne.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Nocturne.space3),
                    AnimatedContainer(
                      duration: Nocturne.durationFast,
                      curve: Curves.easeOut,
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _showSendButton && !isComposing
                            ? Nocturne.textPrimary
                            : Nocturne.bgSurface,
                        borderRadius:
                            BorderRadius.circular(Nocturne.radiusLg - 2),
                        border: Border.all(
                          color: _showSendButton && !isComposing
                              ? Colors.transparent
                              : Nocturne.borderSubtle,
                        ),
                      ),
                      child: IconButton(
                        onPressed: _showSendButton && !isComposing
                            ? () => _sendMessage()
                            : null,
                        tooltip: 'Send',
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          size: Nocturne.iconLg,
                          color: _showSendButton && !isComposing
                              ? Nocturne.black
                              : Nocturne.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBackdrop extends StatelessWidget {
  const _ChatBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          const ColoredBox(color: Colors.black),
          Positioned(
            top: -120,
            left: -40,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Nocturne.accentWarm.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 180,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Nocturne.accentCool.withValues(alpha: 0.09),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 20,
        icon: Icon(
          icon,
          size: Nocturne.iconLg,
          color: Nocturne.textSecondary,
        ),
      ),
    );
  }
}

class _QuietLoadingState extends StatelessWidget {
  const _QuietLoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            valueColor: AlwaysStoppedAnimation<Color>(
              Nocturne.textSecondary.withValues(alpha: 0.75),
            ),
          ),
        ),
        const SizedBox(height: Nocturne.space5),
        Text(
          label,
          style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
        ),
      ],
    );
  }
}

class _TextualTypingIndicator extends StatefulWidget {
  const _TextualTypingIndicator({required this.label});

  final String label;

  @override
  State<_TextualTypingIndicator> createState() =>
      _TextualTypingIndicatorState();
}

class _TextualTypingIndicatorState extends State<_TextualTypingIndicator> {
  static const _suffixes = ['', '.', '..', '...'];
  late Timer _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 480), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _suffixes.length;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = widget.label.replaceAll('...', '');

    return AnimatedSwitcher(
      duration: Nocturne.durationFast,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Text(
        '$normalized${_suffixes[_index]}',
        key: ValueKey('${widget.label}_${_suffixes[_index]}'),
        style: Nocturne.bodySm.copyWith(
          color: Nocturne.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.showTimestamp,
    this.customTimestampText,
  });

  final Message message;
  final bool showTimestamp;
  final String? customTimestampText;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubbleColor =
        isUser ? const Color(0xFFF1F3F6) : const Color(0xFF111317);
    final textColor = isUser ? Colors.black : Nocturne.textPrimary;
    final borderColor =
        isUser ? Colors.transparent : Colors.white.withValues(alpha: 0.08);

    return Padding(
      padding: EdgeInsets.only(
        top: showTimestamp ? Nocturne.space7 : Nocturne.space4,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTimestamp)
            Padding(
              padding: const EdgeInsets.only(bottom: Nocturne.space4),
              child: Text(
                customTimestampText ?? _formatTimestamp(message.sentAt),
                style: Nocturne.bodySm.copyWith(color: Nocturne.textTertiary),
              ),
            ),
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isUser ? 20 : 8),
                    bottomRight: Radius.circular(isUser ? 8 : 20),
                  ),
                  border: Border.all(color: borderColor),
                  boxShadow: isUser ? Nocturne.elevationLow : const [],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Nocturne.space5,
                    vertical: Nocturne.space4,
                  ),
                  child: Text(
                    message.content,
                    style:
                        Nocturne.bodyLg.copyWith(color: textColor, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'pm' : 'am';
    return '$hour:$minute $suffix';
  }
}
