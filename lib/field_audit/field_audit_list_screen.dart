// Field Audit — the local audit queue (schema v2).
//
// Entry point (only when built with --dart-define=FIELD_AUDIT_MODE=true).
// Everything here is local. Two distinct exports:
//   * EVIDENCE BACKUP (ZIP)  — recommended. ALL records + COMPLETED-only
//     analysis CSV/JSON + every referenced photo + a manifest.
//   * Quick CSV + JSON       — ALL records, no photos.
// Pending queue entries are never presented as completed study observations.

import 'package:flutter/material.dart';

import '../theme/sm_theme.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_widgets.dart';
import 'field_audit_config.dart';
import 'field_audit_export.dart';
import 'field_audit_form_screen.dart';
import 'field_audit_model.dart';
import 'field_audit_pick_toilet_screen.dart';
import 'field_audit_store.dart';

class FieldAuditListScreen extends StatefulWidget {
  const FieldAuditListScreen({super.key});

  @override
  State<FieldAuditListScreen> createState() => _FieldAuditListScreenState();
}

class _FieldAuditListScreenState extends State<FieldAuditListScreen> {
  final _store = FieldAuditStore();
  List<FieldAudit> _audits = const [];
  bool _loading = true;
  bool _busy = false;
  AuditStatus? _filter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final list = await _store.loadAll();
    if (mounted) {
      setState(() {
        _audits = list;
        _loading = false;
      });
    }
  }

  int _count(AuditStatus s) => _audits.where((a) => a.status == s).length;

  List<FieldAudit> get _visible => _filter == null
      ? _audits
      : _audits.where((a) => a.status == _filter).toList();

  Future<void> _openForm(FieldAudit a) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FieldAuditFormScreen(audit: a, store: _store),
      ),
    );
    await _reload();
  }

  Future<void> _addFromNearby() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FieldAuditPickToiletScreen(store: _store),
      ),
    );
    await _reload();
  }

  Future<void> _confirmDelete(FieldAudit a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.sm.surface,
        title: Text(
          'Delete this audit?',
          style: SmText.subhead.copyWith(color: ctx.sm.ink),
        ),
        content: Text(
          '"${a.toiletName}" and its ${a.photoFilenames.length} photo(s) will '
          'be permanently removed from this device.',
          style: SmText.body.copyWith(color: ctx.sm.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: ctx.sm.statusClosed)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(a.auditId);
      await _reload();
    }
  }

  Future<void> _exportMenu() async {
    if (_audits.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to export yet.')));
      return;
    }
    final completed = _audits
        .where((a) => a.status == AuditStatus.completed)
        .length;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.sm.surface,
      builder: (ctx) {
        final c = ctx.sm;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SmTokens.s8),
              const SmGrabHandle(),
              const SizedBox(height: SmTokens.s8),
              ListTile(
                leading: Icon(Icons.inventory_2_outlined, color: c.brand),
                title: Text(
                  'Evidence backup (ZIP) — recommended',
                  style: SmText.bodyStrong.copyWith(color: c.ink),
                ),
                subtitle: Text(
                  'BACKUP: all ${_audits.length} records + photos. '
                  'ANALYSIS DATASET: $completed completed only. + manifest.',
                  style: SmText.caption.copyWith(color: c.ink2),
                ),
                onTap: () => Navigator.pop(ctx, 'zip'),
              ),
              ListTile(
                leading: Icon(Icons.description_outlined, color: c.ink2),
                title: Text(
                  'Quick CSV + JSON (all records, no photos)',
                  style: SmText.body.copyWith(color: c.ink),
                ),
                onTap: () => Navigator.pop(ctx, 'quick'),
              ),
              const SizedBox(height: SmTokens.s8),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final String localPath;
      if (choice == 'zip') {
        localPath = await shareEvidenceBundle(_audits, _store);
      } else {
        localPath = (await shareExport(_audits, _store)).csvPath;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported. Local copy kept at:\n$localPath'),
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Field Audit — internal',
          style: SmText.subhead.copyWith(color: c.ink),
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: SmTokens.s16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Export / evidence backup',
              icon: Icon(Icons.ios_share, color: c.ink),
              onPressed: _exportMenu,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SmTokens.s16,
              SmTokens.s4,
              SmTokens.s16,
              0,
            ),
            child: Text(
              'Schema v${FieldAuditConfig.schemaVersion} · ${_audits.length} '
              'record(s) · local only, no production writes',
              style: SmText.caption.copyWith(color: c.ink3),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: SmTokens.s12),
              children: [
                _chip(
                  'All (${_audits.length})',
                  _filter == null,
                  () => setState(() => _filter = null),
                ),
                _chip(
                  'Pending (${_count(AuditStatus.pending)})',
                  _filter == AuditStatus.pending,
                  () => setState(() => _filter = AuditStatus.pending),
                ),
                _chip(
                  'In progress (${_count(AuditStatus.inProgress)})',
                  _filter == AuditStatus.inProgress,
                  () => setState(() => _filter = AuditStatus.inProgress),
                ),
                _chip(
                  'Completed (${_count(AuditStatus.completed)})',
                  _filter == AuditStatus.completed,
                  () => setState(() => _filter = AuditStatus.completed),
                ),
                _chip(
                  'Revisit (${_count(AuditStatus.revisit)})',
                  _filter == AuditStatus.revisit,
                  () => setState(() => _filter = AuditStatus.revisit),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.brandSolid))
                : _visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(SmTokens.s32),
                      child: Text(
                        'No audits here yet.\nTap "Add from nearby / '
                        'search" to queue records.',
                        textAlign: TextAlign.center,
                        style: SmText.body.copyWith(color: c.ink3),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(SmTokens.s16),
                      itemCount: _visible.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: SmTokens.s8),
                      itemBuilder: (_, i) => _row(c, _visible[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.brandSolid,
        foregroundColor: c.onBrand,
        onPressed: _addFromNearby,
        icon: const Icon(Icons.add),
        label: const Text('Add from nearby / search'),
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => onTap(),
    ),
  );

  Widget _row(SmColors c, FieldAudit a) {
    final t = a.completedAt ?? a.visitStartedAt ?? a.queuedAt;
    Color statusColor;
    switch (a.status) {
      case AuditStatus.completed:
        statusColor = c.statusOpen;
        break;
      case AuditStatus.revisit:
        statusColor = c.statusUnsure;
        break;
      case AuditStatus.inProgress:
        statusColor = c.brand;
        break;
      case AuditStatus.pending:
        statusColor = c.ink3;
        break;
    }
    return SmCard(
      onTap: () => _openForm(a),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.toiletName.isEmpty ? '(unnamed)' : a.toiletName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmText.bodyStrong.copyWith(color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${auditStatusWire(a.status)} · '
                  '${recordContextWire(a.recordContext)} · '
                  '${t.year}-${_pad2(t.month)}-${_pad2(t.day)} '
                  '${_pad2(t.hour)}:${_pad2(t.minute)}',
                  style: SmText.caption.copyWith(color: statusColor),
                ),
                if (a.status == AuditStatus.completed) ...[
                  const SizedBox(height: 2),
                  Text(
                    'facility=${fourStateUsableWire(a.computeFacilityUsable())} · '
                    'mapped_option=${mappedOptionUsableWire(a.computeMappedOptionUsable())} · '
                    'gps=${gpsSourceWire(a.gpsSource)} · '
                    '${a.hasPhotos ? "📷 ${a.photoFilenames.length}" : "no photo"}',
                    style: SmText.caption.copyWith(color: c.ink2),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: c.ink3),
            onPressed: () => _confirmDelete(a),
          ),
        ],
      ),
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
