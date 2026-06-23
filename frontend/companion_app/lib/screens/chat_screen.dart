import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/eden_theme.dart';
import '../models/models.dart';
import '../main.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final List<Message> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isInitializing = true;
  bool _isSending = false;
  bool _isCompanionTyping = false;
  String? _errorMessage;

  String? _conversationId;
  String _partnerName = 'Companion';
  String _partnerMood = 'peaceful';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeChat());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _initializeChat() async {
    try {
      final apiService = ref.read(apiServiceProvider);

      // 1. Start Session / Load Partner Info
      final session = await apiService.startSession();
      if (!mounted) return;
      setState(() {
        _partnerName = session.partner.name;
        _partnerMood = session.partner.currentMood ?? 'peaceful';
      });

      // 2. Fetch Conversations to find current conversation ID
      final conversations = await apiService.getConversations();
      if (conversations.isNotEmpty && mounted) {
        final mostRecent = conversations.first as Map<String, dynamic>;
        _conversationId = mostRecent['id']?.toString();
        
        // 3. Load messages for this conversation
        if (_conversationId != null) {
          final fetched = await apiService.getMessages(_conversationId!);
          if (mounted) {
            setState(() {
              _messages.addAll(fetched);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error starting chat session: $e');
      setState(() {
        _errorMessage = 'could not connect to Eden. try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
        _scrollToBottom();
      }
    }

    _pollProactiveMessages();
  }

  Future<void> _pollProactiveMessages() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final proactive = await apiService.getPendingProactive();
      if (proactive.isNotEmpty && mounted) {
        for (var pm in proactive) {
          setState(() {
            _messages.insert(
              0,
              Message(
                id: pm.id,
                role: 'assistant',
                content: pm.message,
                sentAt: pm.sentAt,
              ),
            );
          });
          await apiService.acknowledgeProactive(pm.id);
        }
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending || _isCompanionTyping) return;

    _inputController.clear();
    _inputFocusNode.requestFocus();
    HapticFeedback.lightImpact();

    final userMessage = Message(
      id: UniqueKey().toString(),
      role: 'user',
      content: text,
      sentAt: DateTime.now(),
    );

    setState(() {
      _messages.insert(0, userMessage);
      _isSending = true;
      _isCompanionTyping = true;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.sendMessage(_conversationId, text);
      
      if (response.conversationId.isNotEmpty) {
        _conversationId = response.conversationId;
      }

      // Simulate typing speed based on reply length
      final delay = (response.reply.length * 20).clamp(1000, 2500);
      await Future.delayed(Duration(milliseconds: delay));

      if (mounted) {
        setState(() {
          _isSending = false;
          _isCompanionTyping = false;
          _messages.insert(
            0,
            Message(
              id: UniqueKey().toString(),
              role: 'assistant',
              content: response.reply,
              sentAt: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isCompanionTyping = false;
          _errorMessage = 'failed to send message. check your network.';
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildMessageList()),
            if (_errorMessage != null) _buildErrorBanner(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      decoration: const BoxDecoration(
        color: EdenTheme.bgSurface,
        border: Border(bottom: BorderSide(color: EdenTheme.bgElevated, width: 0.8)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: EdenTheme.bgElevated,
              border: Border.all(color: EdenTheme.accentPrimary.withValues(alpha: 0.35), width: 1.2),
            ),
            child: Center(
              child: Text(
                _partnerName.isNotEmpty ? _partnerName[0].toUpperCase() : 'E',
                style: EdenTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold, color: EdenTheme.accentPrimary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Name and Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _partnerName,
                  style: EdenTheme.emphasisLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  _isCompanionTyping ? 'typing…' : _partnerMood.toLowerCase(),
                  style: EdenTheme.bodySmall.copyWith(
                    color: _isCompanionTyping ? EdenTheme.accentPrimary : EdenTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            icon: const Icon(Icons.bookmark_border_rounded, color: EdenTheme.textSecondary),
            tooltip: 'Memory Vault',
            onPressed: () => context.push('/memories'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: EdenTheme.textSecondary),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary)),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'connection established.\nsay hello to $_partnerName.',
          textAlign: TextAlign.center,
          style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textSecondary, fontStyle: FontStyle.italic),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
      itemCount: _messages.length + (_isCompanionTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isCompanionTyping && index == 0) {
          return _buildTypingBubble();
        }
        
        final msgIndex = _isCompanionTyping ? index - 1 : index;
        final msg = _messages[msgIndex];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(Message msg) {
    final bool isUser = msg.role == 'user';
    final String formattedTime = DateFormat('jm').format(msg.sentAt);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: isUser ? EdenTheme.accentPrimary : EdenTheme.bgSurface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser 
                  ? null 
                  : Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.08), width: 0.6),
            ),
            child: Text(
              msg.content,
              style: EdenTheme.bodyMedium.copyWith(
                color: isUser ? EdenTheme.bgPrimary : EdenTheme.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: Text(
              formattedTime,
              style: EdenTheme.labelSmall.copyWith(fontSize: 9),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: EdenTheme.bgSurface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.08), width: 0.6),
        ),
        child: const _TypingDots(),
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

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: EdenTheme.bgSurface,
        border: Border(top: BorderSide(color: EdenTheme.bgElevated, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: EdenTheme.bgPrimary.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.15)),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                style: EdenTheme.bodyMedium,
                cursorColor: EdenTheme.accentPrimary,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Message $_partnerName...',
                  hintStyle: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: EdenTheme.accentPrimary,
              ),
              child: const Center(
                child: Icon(Icons.send_rounded, color: EdenTheme.bgPrimary, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Typing indicator dot animation ---
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double step = 1.0 / 3.0;
            final double value = (_controller.value - (index * step)).clamp(0.0, step) / step;
            final double bounce = 3.0 * (1.0 - (value - 0.5).abs() * 2.0);
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2.0),
              transform: Matrix4.translationValues(0.0, -bounce, 0.0),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: EdenTheme.accentPrimary,
              ),
            );
          },
        );
      }),
    );
  }
}
