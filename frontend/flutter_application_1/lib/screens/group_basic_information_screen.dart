// Editácia hlavných údajov o skupine vrátane názvu obrázku a krátkeho textového predstavenia tímu.
// Kontroluje oprávnenia používateľa a zmeny odošle cez aplikačný API klient s upozornením výsledku.
// AI generated with manual refinements




import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_utils.dart';

class GroupBasicInformationScreen extends StatefulWidget {
  final int groupId;

  const GroupBasicInformationScreen({super.key, required this.groupId});

  @override
  State<GroupBasicInformationScreen> createState() =>
      _GroupBasicInformationScreenState();
}

class _GroupBasicInformationScreenState
    extends State<GroupBasicInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isIconLoading = false;
  Group? _group;

  @override
  // Tato funkcia pripravi uvodny stav obrazovky.
  // Spusta prve nacitanie dat a potrebne inicializacie.
  void initState() {
    super.initState();
    _load();
  }

  @override
  // Tato funkcia uprace zdroje pred zatvorenim obrazovky.
  // Zastavi listenery, timery alebo controllery.
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  // Tato funkcia nacita alebo obnovi data.
  // Pouziva API volania a potom aktualizuje stav.
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final group = await api.getGroupDetails(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = group;
        _nameController.text = group.name;
        _capacityController.text = group.capacity.toString();
      });
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Tato funkcia odosle alebo ulozi formular.
  // Pred odoslanim skontroluje vstupy a spracuje odpoved.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _group == null) return;
    setState(() => _isSaving = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.updateGroup(
        groupId: _group!.idGroup,
        name: _nameController.text.trim(),
        capacity: int.parse(_capacityController.text.trim()),
      );
      final afterQueue = await api.getPendingOfflineChangesCount();
      if (!mounted) return;
      await _load();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            afterQueue > beforeQueue
                ? 'Zmeny skupiny sú uložené offline.'
                : 'Group updated successfully',
          ),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _dateLabel(String? input) {
    if (input == null || input.isEmpty) return '-';
    return input;
  }

  Future<void> _pickAndUploadIcon() async {
    if (_group == null) return;
    if (!await PermissionService.hasGalleryReadAccess()) {
      final granted = await PermissionService.requestGalleryPermission();
      if (!granted) {
        if (!mounted) return;
        context.showLatestSnackBar(
          const SnackBar(
            content: Text(
              'Bez prístupu ku galérii nemôžeme nahrať ikonu skupiny.',
            ),
            backgroundColor: Color(0xFF8B1A2C),
          ),
        );
        return;
      }
    }

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final denied = e.code == 'photo_access_denied' ||
          (e.message?.toLowerCase().contains('permission') ?? false);
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'Prístup ku galérii bol zamietnutý. Môžete ho zmeniť v nastaveniach telefónu.'
                : 'Nepodarilo sa otvoriť galériu.',
          ),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
      return;
    }
    if (picked == null) return;

    setState(() => _isIconLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.uploadGroupIcon(
        groupId: _group!.idGroup,
        imageFile: File(picked.path),
      );
      final afterQueue = await api.getPendingOfflineChangesCount();
      if (!mounted) return;
      await _load();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            afterQueue > beforeQueue
                ? 'Nahratie ikony skupiny je uložené offline.'
                : 'Group icon uploaded successfully',
          ),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isIconLoading = false);
    }
  }

  // Tato funkcia odstrani vybranu polozku.
  // Po vymazani synchronizuje stav obrazovky.
  Future<void> _removeIcon() async {
    if (_group == null) return;
    setState(() => _isIconLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final beforeQueue = await api.getPendingOfflineChangesCount();
      await api.deleteGroupIcon(_group!.idGroup);
      final afterQueue = await api.getPendingOfflineChangesCount();
      if (!mounted) return;
      await _load();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            afterQueue > beforeQueue
                ? 'Odstránenie ikony skupiny je uložené offline.'
                : 'Group icon removed successfully',
          ),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isIconLoading = false);
    }
  }

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Basic information'),
        backgroundColor: AppColors.dialogBackground(context),
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.screenGradient(context),
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: AppColors.circularProgressOnBackground(context),
                  ),
                )
              : _group == null
              ? Center(
                  child: Text(
                    'Unable to load group information',
                    style: TextStyle(color: AppColors.textMuted(context)),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSecondary(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.listCardBorderMedium(
                                      context,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _GroupIconPreview(
                                      groupId: _group!.idGroup,
                                      hasIcon: _group!.hasIcon,
                                      token: token,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _group!.hasIcon
                                          ? 'Group icon'
                                          : 'No icon uploaded yet',
                                      style: TextStyle(
                                        color: AppColors.textMuted(context),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: _isIconLoading
                                              ? null
                                              : _pickAndUploadIcon,
                                          icon: _isIconLoading
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.upload_rounded,
                                                ),
                                          label: const Text('Upload icon'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF8B1A2C,
                                            ),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed:
                                              (!_group!.hasIcon ||
                                                  _isIconLoading)
                                              ? null
                                              : _removeIcon,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Remove icon'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFFE57373,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFE57373),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _InfoTile(
                                label: 'Group ID',
                                value: _group!.idGroup.toString(),
                              ),
                              const SizedBox(height: 10),
                              _InfoTile(
                                label: 'Created',
                                value: _dateLabel(_group!.createDate),
                              ),
                              const SizedBox(height: 10),
                              _InfoTile(
                                label: 'Conversation ID',
                                value:
                                    _group!.conversationId?.toString() ?? '-',
                              ),
                              const SizedBox(height: 10),
                              _InfoTile(
                                label: 'Current capacity',
                                value: _group!.capacity.toString(),
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _nameController,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Group name',
                                  labelStyle: TextStyle(
                                    color: AppColors.textMuted(context),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.surfaceSecondary(context),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.outlineMuted(context),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF8B1A2C),
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Name is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _capacityController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Group capacity',
                                  labelStyle: TextStyle(
                                    color: AppColors.textMuted(context),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.surfaceSecondary(context),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.outlineMuted(context),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF8B1A2C),
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Capacity is required';
                                  }
                                  final parsed = int.tryParse(value.trim());
                                  if (parsed == null || parsed < 1) {
                                    return 'Capacity must be a number greater than 0';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B1A2C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save changes',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.listCardBorderMedium(context),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: AppColors.textMuted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupIconPreview extends StatelessWidget {
  final int groupId;
  final bool hasIcon;
  final String? token;

  const _GroupIconPreview({
    required this.groupId,
    required this.hasIcon,
    required this.token,
  });

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final imageUrl = '${ApiService.baseUrl}/groups/$groupId/icon';
    final canLoadNetworkIcon = groupId > 0 && hasIcon && token != null;
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.dialogBackground(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.outlineMuted(context)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder(
                      future: api.getCachedGroupIconBytes(groupId),
                      builder: (context, snapshot) {
                        final cachedBytes = snapshot.data;
                        if (cachedBytes != null && cachedBytes.isNotEmpty) {
                          return Image.memory(cachedBytes, fit: BoxFit.contain);
                        }
                        if (canLoadNetworkIcon) {
                          return Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            headers: {'Authorization': 'Bearer $token'},
                            errorBuilder: (_, __, ___) => SizedBox(
                              height: 220,
                              child: Center(
                                child: Icon(
                                  Icons.groups_rounded,
                                  color: AppColors.textMuted(context),
                                  size: 72,
                                ),
                              ),
                            ),
                          );
                        }
                        return SizedBox(
                          height: 220,
                          child: Center(
                            child: Icon(
                              Icons.groups_rounded,
                              color: AppColors.textMuted(context),
                              size: 72,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.avatarPlaceholderBackground(context),
          border: Border.all(
            color: AppColors.outlineStrong(context),
            width: 1.4,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder(
          future: api.getCachedGroupIconBytes(groupId),
          builder: (context, snapshot) {
            final cachedBytes = snapshot.data;
            if (cachedBytes != null && cachedBytes.isNotEmpty) {
              return Image.memory(cachedBytes, fit: BoxFit.cover);
            }
            if (canLoadNetworkIcon) {
              return Image.network(
                imageUrl,
                fit: BoxFit.cover,
                headers: {'Authorization': 'Bearer $token'},
                errorBuilder: (_, __, ___) => Icon(
                  Icons.groups_rounded,
                  color: AppColors.textMuted(context),
                  size: 34,
                ),
              );
            }
            return Icon(
              Icons.groups_rounded,
              color: AppColors.textMuted(context),
              size: 34,
            );
          },
        ),
      ),
    );
  }
}
