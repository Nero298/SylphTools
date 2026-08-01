import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Three-dot bouncing typing indicator shown inside a chat bubble,
/// styled like Telegram/Discord "is typing" bubbles.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: const BoxDecoration(
              gradient: AppColors.accentGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, size: 15, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.bgMsgAi,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: SizedBox(
              width: 34,
              height: 8,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(3, (i) {
                      final t = ((_controller.value - i * 0.2) % 1.0).clamp(0.0, 1.0);
                      final bounce = (t < 0.5) ? t * 2 : (1 - t) * 2;
                      return Transform.translate(
                        offset: Offset(0, -4 * bounce),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.accentHi.withValues(
                              alpha: 0.5 + 0.5 * bounce,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
