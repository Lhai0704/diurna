import 'windows_crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:diurna_core/diurna_core.dart';

/// Windows user-bound encryption. Plain session JSON never enters a command line.
class AuthStore {
  AuthStore(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/session.enc');
  static Future<List<int>> crypt(
    List<int> input, {
    required bool protect,
  }) async => protectSession(input, protect: protect);

  Future<Map<String, dynamic>?> read() async {
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(
      jsonDecode(
            utf8.decode(await crypt(await file.readAsBytes(), protect: false)),
          )
          as Map,
    );
  }

  Future<void> write(Map<String, dynamic> session) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(
      await crypt(utf8.encode(jsonEncode(session)), protect: true),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }

  Future<void> secureDirectory() async {
    await directory.create(recursive: true);
    if (!Platform.isWindows) {
      throw const DiurnaException('VALIDATION', 'Windows is required');
    }
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$p=\$env:DIURNA_STATE_PATH; \$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User; '
            '\$acl=[IO.Directory]::GetAccessControl(\$p,[Security.AccessControl.AccessControlSections]::Access); '
            '\$acl.SetAccessRuleProtection(\$true,\$false); foreach(\$old in @(\$acl.Access)){\$acl.RemoveAccessRuleSpecific(\$old)}; '
            '\$rule=New-Object Security.AccessControl.FileSystemAccessRule(\$sid,"FullControl","ContainerInherit,ObjectInherit","None","Allow"); '
            '\$acl.AddAccessRule(\$rule); [IO.Directory]::SetAccessControl(\$p,\$acl)',
      ],
      environment: {'DIURNA_STATE_PATH': directory.absolute.path},
    );
    if (result.exitCode != 0) {
      throw const DiurnaException(
        'AUTH_REQUIRED',
        'Could not restrict credential directory permissions',
      );
    }
  }
}
