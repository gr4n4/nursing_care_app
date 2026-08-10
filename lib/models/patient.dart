import 'package:cloud_firestore/cloud_firestore.dart';

class Patient {
  final String? id;
  final String uid;
  final String email;
  final String name;
  final String gender; // 'male' | 'female' | ''
  final String birthDate;
  final int heightCm;
  final int weightKg;
  final String room;
  final String note;
  final Timestamp? createdAt;

  Patient({
    this.id,
    required this.uid,
    required this.email,
    required this.name,
    this.gender = '',
    required this.birthDate,
    required this.heightCm,
    required this.weightKg,
    required this.room,
    required this.note,
    this.createdAt,
  });

  /// 목록 카드 등에서 '46Y/M' 형태로 쓰기 위한 성별 약자.
  String get genderShort {
    if (gender == 'male') return 'M';
    if (gender == 'female') return 'F';
    return '';
  }

  int get age {
    if (birthDate.isEmpty) return 0;

    final birth = DateTime.tryParse(birthDate);
    if (birth == null) return 0;

    final today = DateTime.now();
    int calculatedAge = today.year - birth.year;

    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      calculatedAge--;
    }

    return calculatedAge;
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'gender': gender,
      'birthDate': birthDate,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'room': room,
      'note': note,
      'createdAt': createdAt ?? Timestamp.now(),
    };
  }

  factory Patient.fromMap(String id, Map<String, dynamic> map) {
    return Patient(
      id: id,
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      gender: map['gender'] ?? '',
      birthDate: map['birthDate'] ?? '',
      heightCm: map['heightCm'] ?? 0,
      weightKg: map['weightKg'] ?? 0,
      room: map['room'] ?? '',
      note: map['note'] ?? '',
      createdAt: map['createdAt'],
    );
  }
}