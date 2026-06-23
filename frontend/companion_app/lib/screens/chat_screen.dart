import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_theme.dart';
import '../models/models.dart';
import '../main.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../services/burst_playback_service.dart';

// --- Riverpod State Management Providers ---

class ConversationState {
  final String? conversationId;
  final List<Message> messages;
  final bool hasMore;
  final bool isLoadingMore;

  const ConversationState({
    this.conversationId,
    this.messages = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  ConversationState copyWith({
    String? conversationId,
    List<Message>? messages,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return ConversationState(
      conversationId: conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class ConversationNotifier extends StateNotifier<ConversationState> {
  ConversationNotifier() : super(const ConversationState());

  void init(String? conversationId, List<Message> messages) {
    state = ConversationState(
      conversationId: conversationId,
      messages: messages,
      hasMore: messages.length >= 20,
      isLoadingMore: false,
    );
  }

  void setConversationId(String conversationId) {
    state = state.copyWith(conversationId: conversationId);
  }

  void addMessage(Message message) {
    state = state.copyWith(messages: [message, ...state.messages]);
  }

  void addMessagesAtEnd(List<Message> oldMessages) {
    state = state.copyWith(messages: [...state.messages, ...oldMessages]);
  }

  void setLoadingMore(bool loading) {
    state = state.copyWith(isLoadingMore: loading);
  }

  void setHasMore(bool hasMore) {
    state = state.copyWith(hasMore: hasMore);
  }

  void clear() {
    state = const ConversationState();
  }
}

final conversationProvider = StateNotifierProvider<ConversationNotifier, ConversationState>((ref) {
  return ConversationNotifier();
});

final partnerStateProvider = StateProvider<Partner?>((ref) => null);

final sessionProvider = StateProvider<SessionData?>((ref) => null);

final typingProvider = StateProvider<bool>((ref) => false);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isInitializing = true;
  bool _isSending = false;
  String? _errorMessage;
  String? _proactiveIntroText;
  double _headerOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeChat());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
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
      final position = _scrollController.position;
      
      // Pull to load more when reaching the top boundary
      if (position.pixels >= position.maxScrollExtent - 100 &&
          !position.outOfRange) {
        _loadOlderMessages();
      }

      // Subtle partner name header fades in as user scrolls up
      final offset = _scrollController.offset;
      final double newOpacity = (offset / 80.0).clamp(0.0, 1.0);
      if (newOpacity != _headerOpacity) {
        setState(() {
          _headerOpacity = newOpacity;
        });
      }
    }
  }

  Future<void> _initializeChat() async {
    try {
      final apiService = ref.read(apiServiceProvider);

      // 1. Load Session
      final session = await apiService.startSession();
      ref.read(sessionProvider.notifier).state = session;
      ref.read(partnerStateProvider.notifier).state = session.partner;

      // 2. Fetch conversations to resolve current conversation ID
      final conversations = await apiService.getConversations();
      String? conversationId;
      List<Message> fetchedMessages = [];

      if (conversations.isNotEmpty) {
        final mostRecent = conversations.first as Map<String, dynamic>;
        conversationId = mostRecent['id']?.toString();
        
        // 3. Load recent messages
        if (conversationId != null) {
          fetchedMessages = await apiService.getMessages(conversationId);
        }
      }

      // Handle unread proactive messages first
      if (session.pendingProactive.isNotEmpty) {
        // Briefly show "[partner name] sent you something"
        setState(() {
          _proactiveIntroText = "${session.partner.name} sent you something";
          _isInitializing = false;
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          setState(() {
            _proactiveIntroText = null;
          });
        }

        // Merge proactive messages inline in the conversation with their original timestamps
        final List<Message> mergedMessages = List.from(fetchedMessages);
        for (var pm in session.pendingProactive) {
          if (!mergedMessages.any((m) => m.id == pm.id)) {
            mergedMessages.add(Message(
              id: pm.id,
              role: 'assistant',
              content: pm.message,
              sentAt: pm.sentAt,
            ));
          }
        }
        
        // Sort descending (newest first for reverse list representation)
        mergedMessages.sort((a, b) => b.sentAt.compareTo(a.sentAt));
        ref.read(conversationProvider.notifier).init(conversationId, mergedMessages);

        // Acknowledge proactive messages
        for (var pm in session.pendingProactive) {
          try {
            await apiService.acknowledgeProactive(pm.id);
          } catch (e) {
            debugPrint("Failed to acknowledge proactive message: $e");
          }
        }
      } else {
        ref.read(conversationProvider.notifier).init(conversationId, fetchedMessages);
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
      }

      // 4. Focus input field
      _inputFocusNode.requestFocus();
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error starting chat session: $e');
      setState(() {
        _errorMessage = 'could not connect to Eden. try again.';
        _isInitializing = false;
      });
    }
  }

  Future<void> _pollProactiveMessages() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final proactive = await apiService.getPendingProactive();
      if (proactive.isNotEmpty && mounted) {
        final convState = ref.read(conversationProvider);
        for (var pm in proactive) {
          if (!convState.messages.any((m) => m.id == pm.id)) {
            ref.read(conversationProvider.notifier).addMessage(
              Message(
                id: pm.id,
                role: 'assistant',
                content: pm.message,
                sentAt: pm.sentAt,
              ),
            );
          }
          await apiService.acknowledgeProactive(pm.id);
        }
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _loadOlderMessages() async {
    final state = ref.read(conversationProvider);
    if (state.conversationId == null || !state.hasMore || state.isLoadingMore) {
      return;
    }

    ref.read(conversationProvider.notifier).setLoadingMore(true);

    try {
      final apiService = ref.read(apiServiceProvider);
      final oldestMessageId = state.messages.isNotEmpty ? state.messages.last.id : null;
      
      final olderMessages = await apiService.getMessages(
        state.conversationId!,
        beforeId: oldestMessageId,
        limit: 20,
      );

      if (olderMessages.isEmpty) {
        ref.read(conversationProvider.notifier).setHasMore(false);
      } else {
        ref.read(conversationProvider.notifier).addMessagesAtEnd(olderMessages);
        if (olderMessages.length < 20) {
          ref.read(conversationProvider.notifier).setHasMore(false);
        }
      }
    } catch (e) {
      debugPrint("Error loading older messages: $e");
    } finally {
      ref.read(conversationProvider.notifier).setLoadingMore(false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    _inputFocusNode.requestFocus();
    HapticFeedback.lightImpact();

    final userMessage = Message(
      id: UniqueKey().toString(),
      role: 'user',
      content: text,
      sentAt: DateTime.now(),
    );

    // 1. Add user message to list immediately (optimistic UI)
    ref.read(conversationProvider.notifier).addMessage(userMessage);
    _scrollToBottom();

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final convState = ref.read(conversationProvider);
      
      // 2. Show typing indicator
      ref.read(typingProvider.notifier).state = true;

      // 3. Call api.sendMessage()
      final response = await apiService.sendMessage(convState.conversationId, text);
      
      if (response.conversationId.isNotEmpty && convState.conversationId == null) {
        ref.read(conversationProvider.notifier).setConversationId(response.conversationId);
      }

      // 4. If burst response, display them with natural delays
      final bursts = response.bursts;
      if (bursts.isNotEmpty) {
        final messages = bursts.map((b) => b.text).toList();
        final delays = bursts.map((b) => b.preBurstDelayMs / 1000.0).toList();

        final burstService = ref.read(burstPlaybackServiceProvider);
        await burstService.playBurst(
          messages,
          delays,
          (msgText) {
            // Display one by one
            final partnerMessage = Message(
              id: UniqueKey().toString(),
              role: 'assistant',
              content: msgText,
              sentAt: DateTime.now(),
            );
            ref.read(conversationProvider.notifier).addMessage(partnerMessage);
            _scrollToBottom();
          },
          (isTyping) {
            // Typing indicator shows between each burst message
            ref.read(typingProvider.notifier).state = isTyping;
          },
        );
      } else {
        // Fallback for single reply message
        ref.read(typingProvider.notifier).state = false;
        final partnerMessage = Message(
          id: UniqueKey().toString(),
          role: 'assistant',
          content: response.reply,
          sentAt: DateTime.now(),
        );
        ref.read(conversationProvider.notifier).addMessage(partnerMessage);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error sending message: $e");
      setState(() {
        _errorMessage = 'failed to send message. check your network.';
      });
      // Hide typing on error
      ref.read(typingProvider.notifier).state = false;
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _shouldShowTimestamp(List<Message> messages, int index) {
    if (index == messages.length - 1) {
      return true; // oldest message
    }
    final current = messages[index];
    final next = messages[index + 1];
    final difference = current.sentAt.difference(next.sentAt).abs();
    return difference.inHours >= 1;
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
    // Render transient proactive introduction state
    if (_proactiveIntroText != null) {
      return Scaffold(
        backgroundColor: EdenTheme.bgPrimary,
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeIn,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Text(
                  _proactiveIntroText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: EdenTheme.fontDisplay,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    color: EdenTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final partner = ref.watch(partnerStateProvider);
    final conversationState = ref.watch(conversationProvider);

    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: _buildMessageList(conversationState)),
                if (_errorMessage != null) _buildErrorBanner(),
                _buildInputArea(partner),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopHeader(partner),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(Partner? partner) {
    return Container(
      height: 56,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: _headerOpacity,
            child: Text(
              partner != null ? "${partner.name} · ${_formatMood(partner.currentMood)}" : "",
              style: const TextStyle(
                fontFamily: EdenTheme.fontDisplay,
                fontSize: 18,
                fontWeight: FontWeight.w300,
                color: EdenTheme.textPrimary,
              ),
            ),
          ),
          Positioned(
            right: 0,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                  color: EdenTheme.textSecondary.withValues(alpha: 0.6),
                  onPressed: () => context.push('/memories'),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  color: EdenTheme.textSecondary.withValues(alpha: 0.6),
                  onPressed: () => context.push('/settings'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ConversationState conversationState) {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary),
        ),
      );
    }

    final messages = conversationState.messages;
    final isTyping = ref.watch(typingProvider);

    if (messages.isEmpty && !isTyping) {
      final partnerName = ref.read(partnerStateProvider)?.name ?? 'Eden';
      return Center(
        child: Text(
          'connection established.\nsay hello to ${partnerName.toLowerCase()}.',
          textAlign: TextAlign.center,
          style: EdenTheme.bodyMedium.copyWith(
            color: EdenTheme.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16.0, 72.0, 16.0, 16.0),
      itemCount: messages.length + (isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (isTyping && index == 0) {
          return _buildTypingIndicator();
        }
        
        final msgIndex = isTyping ? index - 1 : index;
        final msg = messages[msgIndex];
        final showTimestamp = _shouldShowTimestamp(messages, msgIndex);

        return MessageBubble(
          message: msg,
          showTimestamp: showTimestamp,
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 16.0, top: 12.0, bottom: 12.0),
        child: TypingIndicator(
          dotSize: 6.0,
          spacing: 4.0,
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
      color: EdenTheme.destructive.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: EdenTheme.destructive, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: EdenTheme.bodySmall.copyWith(color: EdenTheme.destructive),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: EdenTheme.destructive, size: 16),
            onPressed: () => setState(() => _errorMessage = null),
          )
        ],
      ),
    );
  }

  Widget _buildInputArea(Partner? partner) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: EdenTheme.bgPrimary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              decoration: BoxDecoration(
                color: EdenTheme.bgElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: EdenTheme.textSecondary.withValues(alpha: 0.1),
                  width: 1.0,
                ),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                style: EdenTheme.bodyLarge,
                cursorColor: EdenTheme.accentPrimary,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: partner != null ? 'message ${partner.name.toLowerCase()}...' : 'message...',
                  hintStyle: EdenTheme.bodyLarge.copyWith(color: EdenTheme.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: EdenTheme.accentPrimary,
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: EdenTheme.bgPrimary,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
