// ═══════════════════════════════════════════════════════════════════
// FILE: question_card.dart
// PURPOSE: UI widget representing an onboarding card question.
// CONTEXT: Frontend UI components.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_theme.dart';
import 'pill_option.dart';

enum QuestionType {
  openText,
  multipleChoice,
}

class QuestionConfig {
  final int step;
  final String question;
  final QuestionType type;
  final List<String>? options;
  final bool optional;

  const QuestionConfig({
    required this.step,
    required this.question,
    required this.type,
    this.options,
    this.optional = false,
  });
}

class QuestionCard extends StatefulWidget {
  final QuestionConfig config;
  final Future<void> Function(dynamic response) onAnswer;

  const QuestionCard({
    super.key,
    required this.config,
    required this.onAnswer,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  final _textController = TextEditingController();
  String? _selectedOption;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _textController.text = '';
  }

  @override
  void didUpdateWidget(covariant QuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.step != widget.config.step) {
      _textController.clear();
      _selectedOption = null;
      _isSubmitting = false;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (widget.config.type == QuestionType.openText) {
      if (widget.config.optional) return true;
      return _textController.text.trim().isNotEmpty;
    } else {
      return _selectedOption != null;
    }
  }

  Future<void> _submitTextAnswer() async {
    if (!_isValid || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
    });
    try {
      await widget.onAnswer(_textController.text.trim());
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _selectOption(String option) async {
    if (_isSubmitting) return;
    setState(() {
      _selectedOption = option;
      _isSubmitting = true;
    });
    // Trigger callback directly after small delay to show animation
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      try {
        await widget.onAnswer(option);
      } catch (_) {
        if (mounted) {
          setState(() {
            _selectedOption = null;
            _isSubmitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Question text
          Text(
            widget.config.question,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: EdenTheme.textPrimary,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),

          // Input field or pill options
          if (widget.config.type == QuestionType.openText) ...[
            TextField(
              controller: _textController,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                color: EdenTheme.textPrimary,
              ),
              cursorColor: EdenTheme.accentPrimary,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitTextAnswer(),
              decoration: InputDecoration(
                border: const UnderlineInputBorder(
                  borderSide: BorderSide(color: EdenTheme.accentPrimary, width: 1.0),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: EdenTheme.accentPrimary.withValues(alpha: 0.4), width: 1.0),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: EdenTheme.accentPrimary, width: 2.0),
                ),
                hintText: widget.config.optional ? 'optional (tap arrow to skip)' : 'type your answer...',
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: EdenTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 16,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 32),
            // Centered next icon button with haptic feedback
            IconButton(
              icon: Icon(
                Icons.arrow_forward_rounded,
                color: _isValid ? EdenTheme.accentPrimary : EdenTheme.textSecondary.withValues(alpha: 0.2),
                size: 32,
              ),
              onPressed: _isValid && !_isSubmitting ? _submitTextAnswer : null,
            ),
          ] else if (widget.config.type == QuestionType.multipleChoice) ...[
            Column(
              children: (widget.config.options ?? []).map((option) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: PillOption(
                    text: option,
                    isSelected: _selectedOption == option,
                    onTap: () => _selectOption(option),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
