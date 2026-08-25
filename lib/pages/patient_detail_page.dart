import 'package:flutter/material.dart';

import '../models/patient.dart';
import 'io_balance_page.dart';
import 'patient_profile_edit_page.dart';

class PatientDetailPage extends StatelessWidget {
  final Patient patient;

  const PatientDetailPage({
    super.key,
    required this.patient,
  });

  String patientInfoText() {
    final List<String> lines = [];

    if (patient.birthDate.isNotEmpty) {
      final ageText = patient.age > 0 ? ' / ${patient.age}세' : '';
      lines.add('생년월일 ${patient.birthDate}$ageText');
    }

    if (patient.room.isNotEmpty) {
      lines.add('병실 ${patient.room}호');
    }

    if (patient.heightCm > 0 || patient.weightKg > 0) {
      final heightText = patient.heightCm > 0 ? '${patient.heightCm}cm' : '';
      final weightText = patient.weightKg > 0 ? '${patient.weightKg}kg' : '';

      if (heightText.isNotEmpty && weightText.isNotEmpty) {
        lines.add('$heightText / $weightText');
      } else {
        lines.add(heightText.isNotEmpty ? heightText : weightText);
      }
    }

    if (patient.note.isNotEmpty) {
      lines.add('주의사항 ${patient.note}');
    }

    if (lines.isEmpty) {
      return '상세 정보 없음';
    }

    return lines.join('\n');
  }

  Future<void> openEditPage(BuildContext context) async {
    if (patient.id == null || patient.id!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('환자 문서 ID가 없어 수정할 수 없습니다.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientProfileEditPage(
          patientId: patient.id!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(patient.name),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '환자 정보 수정',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => openEditPage(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFDCE7F5),
                  child: Text(
                    patient.room.isEmpty ? '-' : patient.room,
                    style: const TextStyle(
                      color: Color(0xFF16305E),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  patient.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    patientInfoText(),
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _menuButton(
              context: context,
              title: '섭취량 기록',
              subtitle: '식사, 음용수, 수분 섭취량 기록',
              icon: Icons.restaurant_rounded,
              color: const Color(0xFF16305E),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const IoBalancePage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _menuButton(
              context: context,
              title: '배설량 기록',
              subtitle: '소변, 대변, 기저귀, 유린백 기록',
              icon: Icons.water_drop_rounded,
              color: const Color(0xFF2563EB),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('배설량 기록 화면은 다음 단계에서 추가합니다.')),
                );
              },
            ),
            const SizedBox(height: 12),
            _menuButton(
              context: context,
              title: 'I/O 요약',
              subtitle: '섭취량 대비 배설량 확인',
              icon: Icons.analytics_rounded,
              color: const Color(0xFF6366F1),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('I/O 요약 화면은 다음 단계에서 추가합니다.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(
            icon,
            color: color,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}