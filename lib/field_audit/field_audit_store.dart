// Field Audit — local-first persistence (schema v2).
//
// One JSON file per audit under  <appDocs>/field_audit/audits/<audit_id>.json
// Photos under                   <appDocs>/field_audit/photos/<filename>
// Exports / evidence bundles      <appDocs>/field_audit/exports/
//
// Persistence is SERIALIZED PER AUDIT and LAST-WRITE-WINS:
//   * save() snapshots the record synchronously, then enqueues the write;
//   * only one write per audit runs at a time (no overlapping .tmp writes);
//   * if newer snapshots arrive while a write is in flight, the newest is
//     written last — an older value can never overwrite a newer one;
//   * save() / flush() resolve once that-or-newer state is durably on disk.
//
// Writes are atomic (write .tmp, then rename). A crash mid-write never corrupts
// an existing record; a stray .tmp is ignored by the loader. Nothing here
// touches Firestore or the network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'field_audit_config.dart';
import 'field_audit_model.dart';

class FieldAuditStore {
  /// [baseDirOverride] lets tests point at a temp directory. In the app it is
  /// null and the app documents directory is used.
  FieldAuditStore({Directory? baseDirOverride})
    : _baseOverride = baseDirOverride;

  final Directory? _baseOverride;
  Directory? _root;
  final Map<String, _AuditSaveWorker> _workers = {};

  Future<Directory> _rootDir() async {
    if (_root != null) return _root!;
    final base = _baseOverride ?? await getApplicationDocumentsDirectory();
    final r = Directory('${base.path}/${FieldAuditConfig.rootFolder}');
    await r.create(recursive: true);
    _root = r;
    return r;
  }

  Future<Directory> _auditsDir() async {
    final d = Directory('${(await _rootDir()).path}/audits');
    await d.create(recursive: true);
    return d;
  }

  Future<Directory> photosDir() async {
    final d = Directory('${(await _rootDir()).path}/photos');
    await d.create(recursive: true);
    return d;
  }

  Future<Directory> exportsDir() async {
    final d = Directory('${(await _rootDir()).path}/exports');
    await d.create(recursive: true);
    return d;
  }

  File _auditFile(Directory dir, String id) => File('${dir.path}/$id.json');

  // --------------------------------------------------------------- save queue

  /// Snapshot the record now, enqueue the write. Returns when this snapshot
  /// (or a newer one for the same audit) is durably persisted.
  Future<void> save(FieldAudit audit) {
    audit.lastSavedAt = DateTime.now();
    final id = audit.auditId;
    final Map<String, dynamic> snapshot = audit.toJson(); // synchronous
    final worker = _workers.putIfAbsent(
      id,
      () => _AuditSaveWorker((snap) => _writeAuditFile(id, snap)),
    );
    return worker.enqueue(snapshot);
  }

  /// Wait until every queued save for [auditId] has settled.
  Future<void> flush(String auditId) =>
      _workers[auditId]?.whenIdle() ?? Future<void>.value();

  /// Wait until every queued save (all audits) has settled.
  Future<void> flushAll() =>
      Future.wait(_workers.values.map((w) => w.whenIdle()));

  Future<void> _writeAuditFile(String id, Map<String, dynamic> snapshot) async {
    final target = _auditFile(await _auditsDir(), id);
    await _atomicWriteString(
      target,
      const JsonEncoder.withIndent('  ').convert(snapshot),
    );
  }

  // ------------------------------------------------------------------- reads

  Future<FieldAudit?> load(String id) async {
    await flush(id);
    final f = _auditFile(await _auditsDir(), id);
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return FieldAudit.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// All audits, newest visit/queue time first. Corrupt files are skipped.
  Future<List<FieldAudit>> loadAll() async {
    await flushAll();
    final dir = await _auditsDir();
    final out = <FieldAudit>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        out.add(FieldAudit.fromJson(j));
      } catch (_) {
        // ignore a corrupt file; the rest of the queue is unaffected
      }
    }
    out.sort((a, b) {
      final at = a.visitStartedAt ?? a.queuedAt;
      final bt = b.visitStartedAt ?? b.queuedAt;
      return bt.compareTo(at);
    });
    return out;
  }

  Future<void> delete(String id) async {
    _workers.remove(id);
    final f = _auditFile(await _auditsDir(), id);
    if (await f.exists()) await f.delete();
    final pdir = await photosDir();
    if (await pdir.exists()) {
      await for (final e in pdir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith('${id}__')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    }
  }

  // ------------------------------------------------------------------ photos

  Future<String> savePhotoBytes(
    String auditId,
    String slot,
    Uint8List bytes,
  ) async {
    final safeSlot = slot.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final name =
        '${auditId}__${safeSlot}__${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File('${(await photosDir()).path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<File?> photoFile(String filename) async {
    final f = File('${(await photosDir()).path}/$filename');
    return await f.exists() ? f : null;
  }

  Future<void> deletePhoto(String filename) async {
    final f = File('${(await photosDir()).path}/$filename');
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------ export

  /// Writes arbitrary export files into `<appDocs>/field_audit/exports/`.
  Future<File> writeExportFile(String name, List<int> bytes) async {
    final f = File('${(await exportsDir()).path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<File> writeExportString(String name, String content) async {
    final f = File('${(await exportsDir()).path}/$name');
    await f.writeAsString(content, flush: true);
    return f;
  }

  // ------------------------------------------------------------------ atomic

  static Future<void> _atomicWriteString(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Some platforms (e.g. Windows) won't rename over an existing file.
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    }
  }
}

/// Serialized, last-write-wins writer for a single audit.
class _AuditSaveWorker {
  _AuditSaveWorker(this._write);

  final Future<void> Function(Map<String, dynamic> snapshot) _write;

  Map<String, dynamic>? _pending;
  Completer<void>? _pendingCompleter;
  bool _running = false;
  final List<Completer<void>> _idleWaiters = [];

  Future<void> enqueue(Map<String, dynamic> snapshot) {
    _pending = snapshot;
    _pendingCompleter ??= Completer<void>();
    final f = _pendingCompleter!.future;
    if (!_running) {
      _running = true;
      unawaited(_drain());
    }
    return f;
  }

  Future<void> whenIdle() {
    if (!_running) return Future<void>.value();
    final c = Completer<void>();
    _idleWaiters.add(c);
    return c.future;
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final snap = _pending!;
      final comp = _pendingCompleter!;
      _pending = null;
      _pendingCompleter = null;
      try {
        await _write(snap);
        comp.complete();
      } catch (e, st) {
        comp.completeError(e, st);
      }
    }
    _running = false;
    final waiters = List<Completer<void>>.of(_idleWaiters);
    _idleWaiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) w.complete();
    }
  }
}
