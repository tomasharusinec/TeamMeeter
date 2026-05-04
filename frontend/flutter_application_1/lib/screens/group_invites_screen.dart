// Obrazovka s pozvánkami do skupín kde používateľ ešte nie je členom.
// Pozvanie vie priamo prijať alebo odmietnuť bez opúšťania tej istej obrazovky.
// AI generated with manual refinements




import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';

class GroupInvitesScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  final String? initialInviteCode;

  const GroupInvitesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.initialInviteCode,
  });

  @override
  State<GroupInvitesScreen> createState() => _GroupInvitesScreenState();
}

class _GroupInvitesScreenState extends State<GroupInvitesScreen> {
  bool _isLoading = true;
  bool _isEnabling = false;
  String? _inviteCode;

  bool get _isEnabled => _inviteCode != null && _inviteCode!.isNotEmpty;

  bool _isOfflineError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('cannot reach');
  }

  @override
  // Tato funkcia pripravi uvodny stav obrazovky.
  // Spusta prve nacitanie dat a potrebne inicializacie.
  void initState() {
    super.initState();
    _inviteCode = widget.initialInviteCode;
    if ((_inviteCode ?? '').isNotEmpty) {
      _isLoading = false;
      return;
    }
    _loadInviteCode();
  }

  // Tato funkcia nacita alebo obnovi data.
  // Pouziva API volania a potom aktualizuje stav.
  Future<void> _loadInviteCode() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final code = await api.getGroupInviteCode(widget.groupId);
      if (!mounted) return;
      setState(() => _inviteCode = code);
    } catch (e) {
      if (!mounted) return;
      if (_isOfflineError(e)) {
        context.showLatestSnackBar(
          const SnackBar(
            content: Text(
              'V offline režime nie je možné načítať QR invite kód.',
            ),
            backgroundColor: Color(0xFFEF6C00),
          ),
        );
      } else if ((_inviteCode ?? '').isEmpty) {
        context.showLatestSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFF8B1A2C),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setInviteEnabled(bool enabled) async {
    setState(() => _isEnabling = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      if (enabled) {
        final code = await api.enableGroupInviteCode(widget.groupId);
        if (!mounted) return;
        setState(() => _inviteCode = code);
      } else {
        await api.disableGroupInviteCode(widget.groupId);
        if (!mounted) return;
        setState(() => _inviteCode = null);
      }
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        _isOfflineError(e)
            ? const SnackBar(
                content: Text(
                  'V offline režime QR kód nie je možné zapnúť ani vypnúť.',
                ),
                backgroundColor: Color(0xFFEF6C00),
              )
            : SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: const Color(0xFF8B1A2C),
              ),
      );
    } finally {
      if (mounted) setState(() => _isEnabling = false);
    }
  }

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invites'),
        backgroundColor: AppColors.dialogBackground(context),
        foregroundColor: textPrimary,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.screenGradient(context),
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: AppColors.circularProgressOnBackground(context),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.panelTranslucent(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.listCardBorderMedium(context),
                      ),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Enable invite QR code',
                        style: TextStyle(color: textPrimary),
                      ),
                      subtitle: Text(
                        'When enabled, members can join via this QR code.',
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                      value: _isEnabled,
                      activeThumbColor: const Color(0xFFE57373),
                      onChanged: _isEnabling ? null : _setInviteEnabled,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isEnabled) ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: _inviteCode!,
                          size: 220,
                          backgroundColor: Colors.white,
                          version: QrVersions.auto,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _inviteCode!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _inviteCode!),
                        );
                        if (!mounted) return;
                        context.showLatestSnackBar(
                          const SnackBar(
                            content: Text('Invite code copied'),
                            backgroundColor: Color(0xFF8B1A2C),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy invite code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        side: BorderSide(color: AppColors.outlineStrong(context)),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: Center(
                        child: Text(
                          'Invite QR code is currently disabled.',
                          style: TextStyle(color: textSecondary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
