import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/core/repositories/file_chat_history_repository.dart';
import 'package:golem_flutter/core/repositories/file_preferences_repository.dart';
import 'package:golem_flutter/core/repositories/file_settings_repository.dart';

/// The corrupt-vs-I/O split: malformed content still quarantines to
/// `.corrupt` and falls back to defaults, while an OS-level failure to read,
/// rename, or write surfaces as a typed [PersistenceException] instead of
/// masquerading as recovery.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('golem-persist-fail');
    addTearDown(() {
      _makeWritable(directory);
      directory.deleteSync(recursive: true);
    });
  });

  File storeFile(String name) => File('${directory.path}/$name');

  Future<void> makeUnreadable(File file) =>
      Process.run('chmod', ['000', file.path]);

  group('read failures are typed, never quarantined', () {
    test('settings', () async {
      final file = storeFile('settings.json');
      file.writeAsStringSync(const GenerationSettings().encode());
      await makeUnreadable(file);
      final repository = FileSettingsRepository(file);
      await expectLater(
        repository.load(),
        throwsA(
          isA<PersistenceException>().having(
            (e) => e.kind,
            'kind',
            PersistenceFailureKind.read,
          ),
        ),
      );
      // The store was preserved under its own name — not renamed .corrupt.
      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.corrupt').existsSync(), isFalse);
    }, skip: Platform.isWindows);

    test('preferences', () async {
      final file = storeFile('prefs.json');
      file.writeAsStringSync(const AppPreferences().encode());
      await makeUnreadable(file);
      await expectLater(
        FilePreferencesRepository(file).load(),
        throwsA(isA<PersistenceException>()),
      );
    }, skip: Platform.isWindows);

    test('chat history', () async {
      final file = storeFile('chats.json');
      file.writeAsStringSync('{"schemaVersion": 2, "conversations": []}');
      await makeUnreadable(file);
      await expectLater(
        FileChatHistoryRepository(file).load(),
        throwsA(isA<PersistenceException>()),
      );
    }, skip: Platform.isWindows);

    test('fake model management', () async {
      final file = storeFile('models.json');
      file.writeAsStringSync('{"schemaVersion": 2, "artifacts": {}}');
      await makeUnreadable(file);
      await expectLater(
        FakeModelManagementRepository(file, catalog: modelCatalog).load(),
        throwsA(isA<PersistenceException>()),
      );
    }, skip: Platform.isWindows);
  });

  test('corruption still quarantines and defaults', () async {
    final file = storeFile('settings.json');
    file.writeAsStringSync('{"schemaVersion": 99}');
    final settings = await FileSettingsRepository(file).load();
    expect(settings, const GenerationSettings());
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.corrupt').existsSync(), isTrue);
  });

  test(
    'a failing quarantine surfaces instead of claiming recovery',
    () async {
      final file = storeFile('settings.json');
      file.writeAsStringSync('not json at all');
      // A read-only parent lets the read succeed and the rename fail.
      Process.runSync('chmod', ['555', directory.path]);
      await expectLater(
        FileSettingsRepository(file).load(),
        throwsA(
          isA<PersistenceException>().having(
            (e) => e.kind,
            'kind',
            PersistenceFailureKind.read,
          ),
        ),
      );
      _makeWritable(directory);
      expect(file.existsSync(), isTrue);
    },
    skip: Platform.isWindows,
  );

  test('a failing write surfaces as a typed write failure', () async {
    // The store's parent path is an ordinary file, so no directory can be
    // created and the atomic write cannot begin.
    final blocker = storeFile('blocker')..writeAsStringSync('');
    final repository = FileSettingsRepository(
      File('${blocker.path}/settings.json'),
    );
    await expectLater(
      repository.save(const GenerationSettings()),
      throwsA(
        isA<PersistenceException>().having(
          (e) => e.kind,
          'kind',
          PersistenceFailureKind.write,
        ),
      ),
    );
    // The serialization chain survives a failed member: the next save fails
    // for its own reason rather than hanging on a poisoned chain.
    await expectLater(
      repository.save(const GenerationSettings()),
      throwsA(isA<PersistenceException>()),
    );
  });
}

void _makeWritable(Directory directory) {
  Process.runSync('chmod', ['-R', 'u+rwX', directory.path]);
}
