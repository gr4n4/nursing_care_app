import 'package:flutter/material.dart';

/// 저장/기록 완료를 명확히 보여주는 확인 표시.
/// 화면 중앙에 초록 체크 + "완료되었습니다"가 떴다가 약 1.2초 뒤 자동으로 닫힌다.
/// (탭하거나 바깥을 눌러도 닫힌다.)
void showSaveSuccess(BuildContext context, {String message = ''}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.12),
    builder: (_) => _SuccessDialog(message: message),
  );
}

class _SuccessDialog extends StatefulWidget {
  final String message;

  const _SuccessDialog({required this.message});

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F9EF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF15803D),
                  size: 42,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '입력이 완료되었습니다',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (widget.message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
