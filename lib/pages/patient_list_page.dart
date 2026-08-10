import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/patient.dart';
import 'patient_register_page.dart';
import 'patient_detail_page.dart';

class PatientListPage extends StatefulWidget {
  const PatientListPage({super.key});

  @override
  State<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends State<PatientListPage> {
  Future<List<Patient>> loadPatients() async {
    // orderBy('room')은 room 필드가 없는 문서를 제외하므로, 전부 받아 클라이언트에서 정렬한다.
    final snapshot =
        await FirebaseFirestore.instance.collection('patients').get();

    int roomNumber(String room) {
      final text = room.replaceAll('호', '').trim();
      return int.tryParse(text) ?? 999999;
    }

    final list = snapshot.docs
        .map((doc) => Patient.fromMap(doc.id, doc.data()))
        .toList();

    list.sort((a, b) {
      final ar = roomNumber(a.room);
      final br = roomNumber(b.room);
      if (ar != br) return ar.compareTo(br);
      return a.name.compareTo(b.name);
    });

    return list;
  }

  Future<void> openPatientRegisterPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PatientRegisterPage(),
      ),
    );

    if (!mounted) return;

    setState(() {});
  }

  void openDetailPage(Patient patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDetailPage(patient: patient),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  String patientSubtitle(Patient patient) {
    final List<String> parts = [];

    if (patient.room.isNotEmpty) {
      parts.add('${patient.room}호');
    }

    if (patient.age > 0) {
      parts.add('${patient.age}세');
    }

    if (patient.heightCm > 0) {
      parts.add('${patient.heightCm}cm');
    }

    if (patient.weightKg > 0) {
      parts.add('${patient.weightKg}kg');
    }

    if (parts.isEmpty) {
      return '상세 정보 없음';
    }

    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('환자 목록'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: FutureBuilder<List<Patient>>(
        future: loadPatients(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('환자 목록 불러오기 오류: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final patients = snapshot.data!;

          if (patients.isEmpty) {
            return const Center(
              child: Text(
                '등록된 환자가 없습니다.\n오른쪽 아래 + 버튼으로 환자를 등록하세요.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];

              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE6FAF8),
                    child: Text(
                      patient.room.isEmpty ? '-' : patient.room,
                      style: const TextStyle(
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    patient.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(patientSubtitle(patient)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openDetailPage(patient),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: openPatientRegisterPage,
        child: const Icon(Icons.add),
      ),
    );
  }
}