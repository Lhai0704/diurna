import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:diurna_core/diurna_core.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int length;
  external Pointer<Uint8> data;
}

typedef _CryptNative =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _CryptDart =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );

/// DPAPI CurrentUser, without UI, child processes, or plaintext temporary files.
List<int> protectSession(List<int> bytes, {required bool protect}) {
  if (!Platform.isWindows) {
    throw const DiurnaException(
      'VALIDATION',
      'Windows credential storage is required',
    );
  }
  final crypt = DynamicLibrary.open('crypt32.dll')
      .lookupFunction<_CryptNative, _CryptDart>(
        protect ? 'CryptProtectData' : 'CryptUnprotectData',
      );
  final free = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');
  final input = calloc<_DataBlob>(), output = calloc<_DataBlob>();
  final data = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  try {
    data.asTypedList(bytes.length).setAll(0, bytes);
    input.ref
      ..length = bytes.length
      ..data = data;
    // CRYPTPROTECT_UI_FORBIDDEN = 1. Absence of LOCAL_MACHINE binds to this user.
    if (crypt(input, nullptr, nullptr, nullptr, nullptr, 1, output) == 0) {
      throw const DiurnaException(
        'AUTH_REQUIRED',
        'Unable to encrypt/decrypt this user session',
      );
    }
    return List<int>.of(output.ref.data.asTypedList(output.ref.length));
  } finally {
    if (output.ref.data != nullptr) free(output.ref.data.cast());
    calloc.free(data);
    calloc.free(input);
    calloc.free(output);
  }
}
