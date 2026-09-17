import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 욕창 위험이 어디에 생겼는지 적는 곳.
///
/// 압력 대시보드에도 같은 입력칸이 있고, 압력 서버가 이 문서를 보고 로컬
/// warnings.log 에도 같은 값을 붙인다. 그래서 어느 쪽에서 적어도 두 곳에
/// 다 남는다.
///
/// 경보 팝업과 알림 기록이 같은 함수를 쓴다. 두 곳에서 따로 적으면 필드
/// 이름이 언젠가 어긋나고, 그러면 한쪽에서 적은 것이 다른 쪽에 안 보인다.
class PressureSite {
  const PressureSite._();

  /// 적어 두는 흔한 자리. 손으로 치면 오타가 나고, 오타가 나면 나중에
  /// "엉치뼈"와 "엉치"가 다른 것으로 세어진다.
  static const List<String> presets = [
    '엉치뼈',
    '꼬리뼈',
    '뒤꿈치',
    '어깨',
    '등',
    '팔꿈치',
    '귀',
    '무릎',
  ];

  /// 부위를 남긴다. 빈 값이면 아무것도 하지 않는다(적기 싫을 수도 있다).
  ///
  /// 실패해도 예외를 올리지 않는다. 부위는 덧붙이는 기록이라, 이것 때문에
  /// 경보 확인이 막히면 안 된다.
  static Future<void> save(String docId, String site) async {
    final value = site.trim();
    if (value.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('pressure_sites')
          .doc(docId)
          .set({
        'site': value,
        'by': FirebaseAuth.instance.currentUser?.email ?? '',
        'at': FieldValue.serverTimestamp(),
        // 어디서 적었는지. 압력 서버가 자기가 올린 것을 되읽고 다시
        // 쓰지 않도록 가르는 데 쓴다.
        'source': 'nrcarec',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('부위 저장 실패: $e');
    }
  }

  /// 알림 기록에서 나중에 적을 때 쓰는 작은 창.
  /// 적으면 그 값을, 그냥 닫으면 null 을 준다.
  static Future<String?> ask(BuildContext context, {String? initial}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _SiteDialog(initial: initial),
    );
  }
}

/// 적어 둔 부위, 또는 아직 안 적었으면 적으라는 단추.
///
/// 경보 팝업은 놓치면 그대로 지나간다. 알림 기록에서 나중에라도 적을 수
/// 있어야 실제로 기록이 쌓인다 — 압력 대시보드는 팝업에서만 받아서,
/// 그 순간을 놓친 경보에는 부위를 영영 못 적는다.
class PressureSiteChip extends StatelessWidget {
  final String docId;

  const PressureSiteChip({super.key, required this.docId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pressure_sites')
          .doc(docId)
          .snapshots(),
      builder: (context, snap) {
        final site = (snap.data?.data()?['site'] ?? '').toString().trim();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final v = await PressureSite.ask(context, initial: site);
            if (v != null) await PressureSite.save(docId, v);
          },
          child: site.isEmpty ? _empty() : _filled(site),
        );
      },
    );
  }

  Widget _filled(String site) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      child: Text(
        site,
        style: const TextStyle(
          color: AppColors.brand,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.brandSoftBorder,
          style: BorderStyle.solid,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 13, color: AppColors.interactive),
          SizedBox(width: 3),
          Text(
            '부위 적기',
            style: TextStyle(
              color: AppColors.interactive,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// 부위 입력칸 + 자주 쓰는 자리 단추.
///
/// 경보 팝업과 알림 기록이 같은 모양을 쓰도록 위젯으로 빼 두었다.
class PressureSiteField extends StatelessWidget {
  final TextEditingController controller;

  /// 단추를 눌렀을 때 화면을 다시 그리게 하는 쪽에서 넘긴다.
  final VoidCallback? onChanged;

  const PressureSiteField({
    super.key,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '위험 발생 부위',
          style: TextStyle(
            color: AppColors.inkMid,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: '예: 엉치뼈, 뒤꿈치',
            hintStyle: const TextStyle(
              color: AppColors.inkDim,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.warn, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in PressureSite.presets)
              _preset(
                p,
                selected: controller.text.trim() == p,
                onTap: () {
                  // 같은 것을 다시 누르면 지운다. 잘못 누르고 못 지우면
                  // 아예 안 적는 편이 낫다고 여기게 된다.
                  controller.text = controller.text.trim() == p ? '' : p;
                  onChanged?.call();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _preset(String label,
      {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.warn : AppColors.raised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.warn : AppColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.inkMid,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SiteDialog extends StatefulWidget {
  final String? initial;

  const _SiteDialog({this.initial});

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '부위 적기',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              PressureSiteField(
                controller: _controller,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.inkMid,
                          side: const BorderSide(color: AppColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('그만두기'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warn,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        onPressed: () =>
                            Navigator.pop(context, _controller.text.trim()),
                        child: const Text('저장'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
