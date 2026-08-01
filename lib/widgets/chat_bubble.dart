import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../models/message_model.dart';
import '../services/llm_service.dart';

class ChatBubble extends StatelessWidget {
  final MessageModel message;
  /// If true, this is the last AI message and we show speed info
  final bool showSpeed;

  const ChatBubble({super.key, required this.message, this.showSpeed = false});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final width = MediaQuery.of(context).size.width;
    final maxBubbleWidth = width * 0.8;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: const BoxDecoration(
                gradient: AppColors.accentGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.accentDim : context.bgMsgAi,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                ),
                child: _buildContent(context, isUser),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    if (isUser) {
      return Text(
        message.content,
        style: GoogleFonts.inter(
          fontSize: 15,
          color: Colors.white,
          height: 1.5,
        ),
      );
    }

    // AI: render markdown
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: GoogleFonts.inter(fontSize: 15, color: context.text, height: 1.55),
            h1: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: context.text),
            h2: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: context.text),
            h3: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: context.text),
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: AppColors.accentHi,
              backgroundColor: context.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            codeblockDecoration: BoxDecoration(
              color: context.isDark
                  ? const Color(0xFF071322)
                  : const Color(0xFFE3F1FA),
              borderRadius: BorderRadius.circular(10),
            ),
            codeblockPadding: const EdgeInsets.all(14),
            blockquoteDecoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              border: const Border(
                left: BorderSide(color: AppColors.accentHi, width: 3),
              ),
            ),
            blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            listBullet: TextStyle(color: context.text),
            tableHead: GoogleFonts.inter(fontWeight: FontWeight.w600, color: context.text, fontSize: 14),
            tableBody: GoogleFonts.inter(color: context.text, fontSize: 14),
            tableBorder: TableBorder.all(color: context.border),
            tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.border)),
            ),
          ),
        ),

        // Action row: Copy + Speed
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 13, color: context.textD),
                        const SizedBox(width: 4),
                        Text('Copy', style: GoogleFonts.inter(fontSize: 11.5, color: context.textD)),
                      ],
                    ),
                  ),
                ),
                if (showSpeed) ...[
                  const SizedBox(width: 12),
                  Obx(() {
                    final llm = Get.find<LlmService>();
                    final speed = llm.isGenerating.value
                        ? llm.tokensPerSecond.value
                        : llm.lastGenerationSpeed.value;
                    if (speed <= 0) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed_rounded, size: 13, color: context.textD),
                        const SizedBox(width: 4),
                        Text(
                          '${speed.toStringAsFixed(1)} t/s',
                          style: GoogleFonts.inter(fontSize: 11.5, color: context.textD),
                        ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
