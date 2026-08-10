import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_page.dart';

/// 관리자가 가입한 간호사 명단을 확인하는 화면. (승인/반려 절차 없음)
class AdminNurseRosterPage extends StatelessWidget {
  const AdminNurseRosterPage({super.key});

  static const Color mintDark = Color(0xFF0F766E);
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color borderGrey = Color(0xFFE5E7EB);

  String formatDate(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  Widget infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: textGrey),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget nurseCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final email = (data['email'] ?? doc.id).toString();
    final name = (data['name'] ?? '').toString();
    final department = (data['department'] ?? '').toString();
    final assignedRooms = (data['assignedRooms'] ?? '').toString();
    // 담당 병동/병실은 한 칸으로 통합됨(assignedRooms). 예전 계정은 department도 있을 수 있어 함께 표기.
    final assignedText = [department, assignedRooms]
        .where((e) => e.trim().isNotEmpty)
        .join(' ');
    final phone = (data['phone'] ?? '').toString();
    final createdAt = formatDate(data['createdAt']);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: borderGrey),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '간호사',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF7CCFC6),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name.isEmpty ? email : name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: textDark,
              ),
            ),
            const SizedBox(height: 14),
            infoLine('이메일', email),
            infoLine('연락처', phone),
            infoLine('담당 병동/병실', assignedText),
            infoLine('가입일', createdAt),
          ],
        ),
      ),
    );
  }

  Future<void> logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('가입 간호사 명단'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: '로그아웃',
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'nurse')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                '가입한 간호사가 없습니다.',
                style: TextStyle(fontSize: 16, color: textGrey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) => nurseCard(docs[index]),
          );
        },
      ),
    );
  }
}
