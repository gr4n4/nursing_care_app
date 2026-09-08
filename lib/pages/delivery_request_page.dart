import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/delivery_request.dart';

/// 물품 배송 요청 (모바일 · 간호사).
///
/// 환자 상세에서 들어오면 그 환자의 호실이 이미 채워져 있다. 간호사는
/// "421호에 뭐가 필요해"가 아니라 "김OO 환자한테 뭐가 필요해"로 생각하고,
/// 호실을 손으로 치면 오타가 나므로 patients.room 을 그대로 쓴다.
///
/// 보낼 곳이 병실만은 아니다(처치실·널스스테이션 등). 그래서 화면에서는
/// '호실'이 아니라 '요청 위치'라고 부르고, 목록에 없는 곳은 직접 적게 한다.
///
/// 품목은 settings/delivery_items 에서 읽는다. 병동마다 쓰는 물건이 다르고
/// 바뀌기도 해서, 앱을 다시 배포하지 않고 콘솔에서 고칠 수 있게 열어 두었다.
/// 문서가 없으면 아래 기본값을 쓴다.
///
/// 색과 짜임새는 다른 간호사 화면(입력 선택·배설 기록)과 같은 규칙을 쓴다.
/// 화면마다 모양이 다르면 같은 앱으로 보이지 않는다.
class DeliveryRequestPage extends StatefulWidget {
  /// 환자 상세에서 들어왔다면 그 호실. 없으면 직접 고른다.
  final String? presetRoom;

  /// 화면 위에 "김OO 환자" 하고 보여 줄 이름. 없으면 위치만 보인다.
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
  // 다른 간호사 화면과 같은 값. 여기만 달라지면 같은 앱으로 보이지 않는다.
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color fieldBg = Color(0xFFF8FAFC);
  static const Color successColor = Color(0xFF22C55E);
  static const Color dangerColor = Color(0xFFEF4444);

  static const List<String> _fallbackItems = [
    '기저귀', '물티슈', '수액세트', '거즈', '소독솜',
  ];

  /// 로봇이 목록을 못 알려줄 때만 쓰는 비상용.
  ///
  /// 정상일 때는 settings/delivery_rooms(로봇이 씀)를 쓴다. 여기 적힌 값과
  /// 로봇 설정을 손으로 맞추면 언젠가 어긋나고, 어긋나면 간호사가 "갈 수
  /// 있다"고 나온 곳을 골랐다가 실패를 떠안는다.
  static const List<String> _fallbackRooms = [
    '420', '421', '422', '423', '424', '425',
    '426', '427', '428', '429', '430',
  ];

  /// 저장할 위치 값을 한 가지 모양으로 맞춘다.
  ///
  /// 환자 명부에는 '신관 421'처럼 앞말이 붙어 있고 병실 단추는 '421'이라,
  /// 그대로 두면 같은 방이 두 값으로 저장된다. 로봇은 이 값으로 갈 곳을
  /// 고르므로 한 가지로 통일해야 한다. 숫자가 있으면 숫자만, 없으면
  /// (처치실 등) 적은 그대로 쓴다.
  static String _normalizeRoom(String v) {
    final m = RegExp(r'\d+').firstMatch(v);
    return m?.group(0) ?? v.trim();
  }

  /// 사람에게 보여 줄 이름. 숫자면 '421호', 아니면 적은 그대로.
  static String _roomLabel(String v) {
    final t = v.trim();
    if (t.isEmpty) return '';
    return RegExp(r'^\d+$').hasMatch(t) ? '$t호' : t;
  }

  final _noteController = TextEditingController();
  final _etcController = TextEditingController();

  /// 목록에 없는 곳(처치실 등)을 직접 적는 칸.

  /// 고른 품목 → 수량. 0이면 안 고른 것.
  final Map<String, int> _picked = {};

  List<String> _items = _fallbackItems;
  bool _loadingItems = true;
  String? _room;
  List<String> _rooms = [];

  /// 위치 목록을 아직 읽는 중인가.
  ///
  /// 다 읽기 전에 그리면 단추가 하나도 없는 빈 칸이 잠깐 보였다가 툭 나타난다.
  bool _loadingRooms = false;
  /// 목록이 로봇에게서 온 것인가. 비상용 목록이면 화면에 알린다.
  bool _roomsFromRobot = false;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _room = widget.presetRoom;
    _loadItems();
    // presetRoom 이어도 목록을 읽는다. 환자의 호실이 로봇이 갈 수 있는 곳인지
    // 확인해야 하기 때문이다. 안 하면 못 가는 곳으로 요청이 만들어진다.
    _loadingRooms = true;
    _loadRooms();
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

  /// 고를 수 있는 위치 목록 — 로봇이 알려준 곳만.
  ///
  /// 로봇이 켜질 때 settings/delivery_rooms 에 "내가 갈 수 있는 곳"을 쓴다.
  /// 그 목록만 보여주면 못 가는 곳을 애초에 고를 수 없다. 앱과 로봇 설정을
  /// 따로 적어 두면 언젠가 어긋나므로, 로봇 설정을 하나뿐인 원본으로 삼는다.
  ///
  /// 환자 명부는 더하지 않는다. 명부에 있어도 로봇이 못 가면 소용이 없다.
  Future<void> _loadRooms() async {
    List<String>? fromRobot;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('delivery_rooms')
          .get();
      fromRobot = (doc.data()?['rooms'] as List<dynamic>?)
          ?.map((e) => _normalizeRoom(e.toString()))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      // 못 읽으면 비상용 목록으로 간다. 요청 자체를 막지는 않는다.
    }
    final known = fromRobot != null && fromRobot.isNotEmpty;
    final list = (known ? fromRobot : [..._fallbackRooms])..sort();
    if (mounted) {
      setState(() {
        _rooms = list;
        _roomsFromRobot = known;
        _loadingRooms = false;
      });
    }
  }

  /// 화면 맨 위 알약. 어디로 보내는 요청인지 한눈에 보이게 한다.
  String get _chipText {
    final room = (_room ?? '').trim();
    final name = (widget.patientName ?? '').trim();
    if (room.isEmpty) return '물품 배송';
    final r = _roomLabel(_normalizeRoom(room));
    return name.isEmpty ? r : '$r · $name';
  }

  /// 로봇이 갈 수 있는 곳인가.
  ///
  /// 환자 상세에서 들어오면 그 환자의 호실이 미리 채워지는데, 명부에 있다고
  /// 로봇이 갈 수 있는 것은 아니다(다른 층에 잠시 가 있는 경우 등).
  /// 목록에 없으면 보내기를 막아, 실패할 요청이 만들어지지 않게 한다.
  bool get _roomReachable {
    final r = _normalizeRoom(_room ?? '');
    return r.isNotEmpty && _rooms.contains(r);
  }

  bool get _canSend =>
      !_sending &&
      !_loadingRooms &&
      _roomReachable &&
      (_picked.values.any((v) => v > 0) ||
          _etcController.text.trim().isNotEmpty);

  Future<void> _send() async {
    final room = _normalizeRoom(_room ?? '');
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
          content: Text('${_roomLabel(room)} 물품 요청을 보냈습니다.'),
          backgroundColor: successColor,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('요청을 보내지 못했습니다: $e'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: pageBg,
        elevation: 0,
        surfaceTintColor: pageBg,
        foregroundColor: textDark,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth >= 700 ? 560.0 : constraints.maxWidth;

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _chip(),
                        const SizedBox(height: 18),
                        const Text(
                          '물품 요청',
                          style: TextStyle(
                            color: textDark,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '필요한 물품을 선택하면 로봇이 가져다 드립니다.',
                          style: TextStyle(
                            color: textGrey,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle('요청 위치'),
                        const SizedBox(height: 10),
                        _placeCard(),
                        const SizedBox(height: 20),
                        _sectionTitle('필요한 물품'),
                        const SizedBox(height: 10),
                        _itemsCard(),
                        const SizedBox(height: 20),
                        _sectionTitle('메모 (선택)'),
                        const SizedBox(height: 10),
                        _noteCard(),
                        const SizedBox(height: 26),
                        _sendButton(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: mintSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFC3D5EE)),
        ),
        child: Text(
          _chipText,
          style: const TextStyle(
            color: mintDark,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
          color: textDark,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderGrey),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: child,
      );

  Widget _placeCard() {
    // 환자 상세에서 들어온 경우 — 위치가 이미 정해져 있다.
    if (widget.presetRoom != null) {
      final r = _roomLabel(_normalizeRoom(widget.presetRoom!));
      return _card(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: mintSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.place_rounded,
                color: mintDark,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                    ),
                  ),
                  if (!_loadingRooms && !_roomReachable)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _rooms.isEmpty
                            ? '로봇이 갈 수 있는 곳을 못 받았습니다'
                            : '로봇이 갈 수 없는 곳입니다 '
                                '(갈 수 있는 곳: ${_rooms.join(", ")})',
                        style: const TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if ((widget.patientName ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${widget.patientName} 환자',
                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_loadingRooms) {
      return _card(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    // 자유 입력은 두지 않는다.
    //
    // 예전에는 아무 곳이나 칠 수 있었는데, 로봇이 못 가는 곳을 적으면
    // 로봇이 널스스테이션까지 오고 간호사가 물품을 다 실은 뒤에야 실패했다.
    // 고를 수 있는 곳만 보여주면 그런 헛걸음이 아예 생기지 않는다.
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _rooms) _placeChip(r, true),
            ],
          ),
          if (!_roomsFromRobot) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 17, color: textGrey),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '로봇이 갈 수 있는 곳을 아직 못 받아 기본 목록을 보여줍니다. '
                    '로봇이 꺼져 있으면 배송이 시작되지 않습니다.',
                    style: const TextStyle(
                      color: textGrey,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _placeChip(String r, bool selectable) {
    final on = selectable && _room == r;
    return GestureDetector(
      onTap: () => setState(() {
        _room = r;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: on ? mintSoft : fieldBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? const Color(0xFFC3D5EE) : borderGrey,
            width: on ? 1.5 : 1,
          ),
        ),
        child: Text(
          _roomLabel(r),
          style: TextStyle(
            color: on ? mintDark : textGrey,
            fontSize: 15,
            fontWeight: on ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _itemsCard() {
    if (_loadingItems) {
      return _card(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return _card(
      child: Column(
        children: [
          for (int i = 0; i < _items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
            _itemRow(_items[i]),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _etcController,
            style: const TextStyle(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '목록에 없는 물품 직접 입력',
              hintStyle: const TextStyle(
                color: textGrey,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: fieldBg,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: borderGrey),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: borderGrey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: mintDark, width: 1.6),
              ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                color: on ? mintDark : textDark,
              ),
            ),
          ),
          // 고르지 않은 줄에는 −와 숫자를 아예 두지 않는다.
          //
          // 처음에는 흐리게만 해 뒀는데, 눌러지지도 않는 빈 네모가 품목마다
          // 하나씩 늘어서서 무엇을 골랐는지 되레 알아보기 어려웠다.
          // 0에서 뺄 것이 없으니 단추도 없는 편이 솔직하다.
          if (on) ...[
            _qtyButton(
              plus: false,
              onTap: () => setState(() {
                final v = qty - 1;
                if (v <= 0) {
                  _picked.remove(name);
                } else {
                  _picked[name] = v;
                }
              }),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: mintDark,
                ),
              ),
            ),
          ],
          _qtyButton(
            plus: true,
            onTap: () => setState(() => _picked[name] = qty + 1),
          ),
        ],
      ),
    );
  }

  /// 수량 −/+ 단추.
  ///
  /// 아이콘 글꼴을 쓰지 않고 막대를 직접 그린다. 웹 빌드에서 빼기 아이콘만
  /// 자리는 잡히는데 그림이 나오지 않았다(더하기는 멀쩡했다). 글꼴에 기대지
  /// 않으면 어느 브라우저에서도 같은 모양이 나온다.
  Widget _qtyButton({required bool plus, required VoidCallback onTap}) {
    const double bar = 2.6;
    const double len = 17;

    Widget stroke({required double w, required double h}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: mintDark,
            borderRadius: BorderRadius.circular(bar),
          ),
        );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        // 크기를 정한 상자에 그림을 넣을 때는 가운데로 놓으라고 일러 줘야 한다.
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mintSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFC3D5EE)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            stroke(w: len, h: bar),
            if (plus) stroke(w: bar, h: len),
          ],
        ),
      ),
    );
  }

  Widget _noteCard() => _card(
        child: TextField(
          controller: _noteController,
          maxLines: 2,
          style: const TextStyle(fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            hintText: '예) 급하지 않습니다 / 문 앞에 두세요',
            hintStyle: TextStyle(color: textGrey, fontWeight: FontWeight.w600),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );

  Widget _sendButton() => GestureDetector(
        onTap: _canSend ? _send : null,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: _canSend ? mintDark : borderGrey,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_sending)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  Icons.local_shipping_rounded,
                  color: _canSend ? Colors.white : textGrey,
                  size: 22,
                ),
              const SizedBox(width: 10),
              Text(
                _sending ? '보내는 중…' : '요청 보내기',
                style: TextStyle(
                  color: _canSend ? Colors.white : textGrey,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
}
