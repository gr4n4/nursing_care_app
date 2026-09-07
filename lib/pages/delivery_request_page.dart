import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/delivery_request.dart';
import '../theme/app_colors.dart';

/// 물품 배송 요청 (모바일 · 간호사).
///
/// 환자 상세에서 들어오면 그 환자의 호실이 이미 채워져 있다. 간호사는
/// "421호에 뭐가 필요해"가 아니라 "김OO 환자한테 뭐가 필요해"로 생각하고,
/// 호실을 손으로 치면 오타가 나므로 patients.room 을 그대로 쓴다.
///
/// 품목은 settings/delivery_items 에서 읽는다. 병동마다 쓰는 물건이 다르고
/// 바뀌기도 해서, 앱을 다시 배포하지 않고 콘솔에서 고칠 수 있게 열어 두었다.
/// 문서가 없으면 아래 기본값을 쓴다.
class DeliveryRequestPage extends StatefulWidget {
  /// 환자 상세에서 들어왔다면 그 호실. 없으면 직접 고른다.
  final String? presetRoom;

  /// 화면 위에 "김OO 환자" 하고 보여 줄 이름. 없으면 호실만 보인다.
  final String? patientName;

  const DeliveryRequestPage({
    super.key,
    this.presetRoom,
    this.patientName,
  });

  @override
  State<DeliveryRequestPage> createState() => _DeliveryRequestPageState();
}

class _DeliveryRequestPageState extends State<DeliveryRequestPage> {
  static const List<String> _fallbackItems = [
    '기저귀', '물티슈', '수액세트', '거즈', '소독솜',
  ];

  final _noteController = TextEditingController();
  final _etcController = TextEditingController();

  /// 고른 품목 → 수량. 0이면 안 고른 것.
  final Map<String, int> _picked = {};

  List<String> _items = _fallbackItems;
  bool _loadingItems = true;
  String? _room;
  List<String> _rooms = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _room = widget.presetRoom;
    _loadItems();
    if (widget.presetRoom == null) _loadRooms();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _etcController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('delivery_items')
          .get();
      final list = (doc.data()?['items'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (mounted && list != null && list.isNotEmpty) {
        setState(() => _items = list);
      }
    } catch (_) {
      // 못 읽어도 요청은 할 수 있어야 한다. 기본 목록으로 간다.
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  /// 환자 없이 요청할 때 고를 호실 목록. 등록된 환자들의 호실에서 뽑는다.
  Future<void> _loadRooms() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('patients').get();
      final rooms = snap.docs
          .map((d) => (d.data()['room'] ?? '').toString().trim())
          .where((r) => r.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {/* 목록을 못 얻어도 직접 입력으로 요청할 수 있다 */}
  }

  bool get _canSend =>
      !_sending &&
      (_room ?? '').trim().isNotEmpty &&
      (_picked.values.any((v) => v > 0) ||
          _etcController.text.trim().isNotEmpty);

  Future<void> _send() async {
    final room = (_room ?? '').trim();
    if (room.isEmpty) return;

    final items = <DeliveryItem>[
      for (final e in _picked.entries)
        if (e.value > 0) DeliveryItem(name: e.key, qty: e.value),
    ];
    final etc = _etcController.text.trim();
    if (etc.isNotEmpty) items.add(DeliveryItem(name: etc));
    if (items.isEmpty) return;

    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('delivery_requests').add({
        'room': room,
        'items': items.map((e) => e.toMap()).toList(),
        'note': _noteController.text.trim(),
        'status': DeliveryStatus.requested,
        // 지금은 간호과 공용 계정이라 화면에 띄우지 않지만, 나중에 개인
        // 계정으로 바뀌면 그때부터 "누가 요청했는지"가 의미를 갖는다.
        'createdBy': FirebaseAuth.instance.currentUser?.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$room호 물품 요청을 보냈습니다.'),
          backgroundColor: AppColors.ok,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('요청을 보내지 못했습니다: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('물품 요청'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _roomCard(),
            const SizedBox(height: 14),
            _sectionTitle('무엇이 필요한가요?'),
            const SizedBox(height: 8),
            _itemsCard(),
            const SizedBox(height: 14),
            _sectionTitle('메모 (선택)'),
            const SizedBox(height: 8),
            _noteCard(),
            const SizedBox(height: 22),
            _sendButton(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.inkMid,
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  Widget _roomCard() {
    if (widget.presetRoom != null) {
      return _card(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.brandSoft,
              child: Text(
                widget.presetRoom!,
                style: const TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.presetRoom}호로 배송',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  if ((widget.patientName ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${widget.patientName} 환자',
                        style: const TextStyle(color: AppColors.inkDim),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 환자 없이 들어온 경우 — 호실을 고른다.
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '어느 호실로 보낼까요?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (_rooms.isEmpty)
            TextField(
              decoration: const InputDecoration(
                hintText: '호실 입력 (예: 421)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _room = v),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _rooms)
                  ChoiceChip(
                    label: Text('$r호'),
                    selected: _room == r,
                    onSelected: (_) => setState(() => _room = r),
                    selectedColor: AppColors.brandSoft,
                    labelStyle: TextStyle(
                      color: _room == r ? AppColors.brand : AppColors.inkMid,
                      fontWeight:
                          _room == r ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _itemsCard() {
    if (_loadingItems) {
      return _card(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return _card(
      child: Column(
        children: [
          for (final name in _items) _itemRow(name),
          const Divider(height: 26),
          TextField(
            controller: _etcController,
            decoration: const InputDecoration(
              labelText: '기타 (목록에 없는 물품)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  /// 품목 한 줄. 수량을 −/+ 로 조절한다.
  /// 장갑 낀 손으로도 누를 수 있게 버튼을 크게 잡았다.
  Widget _itemRow(String name) {
    final qty = _picked[name] ?? 0;
    final on = qty > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? AppColors.brand : AppColors.inkMid,
              ),
            ),
          ),
          IconButton(
            iconSize: 30,
            onPressed: qty == 0
                ? null
                : () => setState(() {
                      final v = qty - 1;
                      if (v <= 0) {
                        _picked.remove(name);
                      } else {
                        _picked[name] = v;
                      }
                    }),
            icon: const Icon(Icons.remove_circle_outline),
            color: AppColors.inkDim,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: on ? AppColors.brand : AppColors.inkDim,
              ),
            ),
          ),
          IconButton(
            iconSize: 30,
            onPressed: () => setState(() => _picked[name] = qty + 1),
            icon: const Icon(Icons.add_circle),
            color: AppColors.interactive,
          ),
        ],
      ),
    );
  }

  Widget _noteCard() => _card(
        child: TextField(
          controller: _noteController,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: '예) 급하지 않습니다 / 문 앞에 두세요',
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      );

  Widget _sendButton() => SizedBox(
        height: 58,
        child: FilledButton.icon(
          onPressed: _canSend ? _send : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            disabledBackgroundColor: AppColors.line,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.local_shipping_rounded),
          label: Text(
            _sending ? '보내는 중…' : '요청 보내기',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
}
