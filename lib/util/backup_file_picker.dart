import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

abstract interface class BackupFilePicker {
  Future<Uri?> saveFile({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  });

  Future<PlatformFile?> pickFile({required String dialogTitle});
}

class SystemBackupFilePicker implements BackupFilePicker {
  const SystemBackupFilePicker();

  @override
  Future<Uri?> saveFile({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) => FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
  );

  @override
  Future<PlatformFile?> pickFile({required String dialogTitle}) =>
      FilePicker.pickFile(dialogTitle: dialogTitle);
}
