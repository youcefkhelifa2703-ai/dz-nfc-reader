import 'dart:typed_data';
import 'package:dmrtd/dmrtd.dart';
import 'package:dmrtd/extensions.dart';

class IdCardData {
  final String documentNumber;
  final String firstName;
  final String lastName;
  final String nin;
  final String birthDate;
  final String expiryDate;
  final String gender;
  final String? arabicFullName;
  final Uint8List? photoBytes;

  IdCardData({
    required this.documentNumber,
    required this.firstName,
    required this.lastName,
    required this.nin,
    required this.birthDate,
    required this.expiryDate,
    required this.gender,
    this.arabicFullName,
    this.photoBytes,
  });
}

class NfcIdService {
  static Future<IdCardData> readBiometricCard({
    required String documentNumber,
    required DateTime birthDate,
    required DateTime expiryDate,
    required Function(String) onStatusUpdate,
  }) async {
    final tagProvider = NfcTagProvider();

    try {
      onStatusUpdate('قرّب بطاقة التعريف من ظهر الهاتف (منطقة NFC)...');
      await tagProvider.connect();

      onStatusUpdate('جاري فك تشفير الشريحة (BAC)...');
      final mrtd = MrtdApi(tagProvider);
      final bacKey = DBAKey(documentNumber.trim(), birthDate, expiryDate);
      await mrtd.initSessionViaBAC(bacKey);

      onStatusUpdate('جاري قراءة البيانات الأساسية (DG1)...');
      final dg1 = await mrtd.readDG1();
      final mrz = dg1.mrz;

      String? arabicName;
      try {
        onStatusUpdate('جاري قراءة الاسم بالعربية (DG11)...');
        final dg11 = await mrtd.readDG11();
        arabicName = dg11.nameOfHolder;
      } catch (_) {}

      onStatusUpdate('جاري سحب الصورة الشخصية (DG2)...');
      Uint8List? imageBytes;
      try {
        final dg2 = await mrtd.readDG2();
        imageBytes = dg2.imageData;
      } catch (_) {}

      return IdCardData(
        documentNumber: mrz.documentNumber,
        firstName: mrz.firstName,
        lastName: mrz.lastName,
        nin: mrz.optionalData,
        birthDate: mrz.dateOfBirth.toIso8601String().split('T')[0],
        expiryDate: mrz.dateOfExpiry.toIso8601String().split('T')[0],
        gender: mrz.sex,
        arabicFullName: arabicName,
        photoBytes: imageBytes,
      );
    } finally {
      await tagProvider.disconnect();
    }
  }
}
