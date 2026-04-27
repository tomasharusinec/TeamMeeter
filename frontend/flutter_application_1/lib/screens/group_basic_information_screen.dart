import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

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

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isIconLoading = false;
  Group? _group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final group = await api.getGroupDetails(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = group;
        _nameController.text = group.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _group == null) return;
    setState(() => _isSaving = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.updateGroup(
        groupId: _group!.idGroup,
        name: _nameController.text.trim(),
      );
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group updated successfully'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isIconLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.uploadGroupIcon(
        groupId: _group!.idGroup,
        imageFile: File(picked.path),
      );
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group icon uploaded successfully'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (mounted) setState(() => _isIconLoading = false);
    }
  }

  Future<void> _removeIcon() async {
    if (_group == null) return;
    setState(() => _isIconLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteGroupIcon(_group!.idGroup);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group icon removed successfully'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Basic information'),
        backgroundColor: const Color(0xFF1A0A0A),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF8B1A2C),
              Color(0xFF3D0C0C),
              Color(0xFF1A0A0A),
              Color(0xFF0D0D0D),
            ],
            stops: [0.0, 0.25, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _group == null
                  ? const Center(
                      child: Text(
                        'Unable to load group information',
                        style: TextStyle(color: Colors.white70),
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
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A1111),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.white.withAlpha(20)),
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
                                          style: const TextStyle(
                                            color: Colors.white70,
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
                                                      Icons.upload_rounded),
                                              label: const Text('Upload icon'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF8B1A2C),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: (!_group!.hasIcon ||
                                                      _isIconLoading)
                                                  ? null
                                                  : _removeIcon,
                                              icon:
                                                  const Icon(Icons.delete_outline),
                                              label: const Text('Remove icon'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    const Color(0xFFE57373),
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
                                    value: _group!.conversationId?.toString() ?? '-',
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _nameController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Group name',
                                      labelStyle:
                                          const TextStyle(color: Colors.white70),
                                      filled: true,
                                      fillColor: const Color(0xFF2A1111),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: Colors.white.withAlpha(26)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFF8B1A2C)),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Name is required';
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
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
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
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
  Widget build(BuildContext context) {
    final imageUrl = '${ApiService.baseUrl}/groups/$groupId/icon';
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
                color: const Color(0xFF1A0A0A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: hasIcon && token != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            headers: {'Authorization': 'Bearer $token'},
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 220,
                              child: Center(
                                child: Icon(
                                  Icons.groups_rounded,
                                  color: Colors.white70,
                                  size: 72,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox(
                            height: 220,
                            child: Center(
                              child: Icon(
                                Icons.groups_rounded,
                                color: Colors.white70,
                                size: 72,
                              ),
                            ),
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
          color: const Color(0xFF1A0A0A),
          border: Border.all(color: Colors.white.withAlpha(70), width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasIcon && token != null
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                headers: {'Authorization': 'Bearer $token'},
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.groups_rounded,
                  color: Colors.white70,
                  size: 34,
                ),
              )
            : const Icon(
                Icons.groups_rounded,
                color: Colors.white70,
                size: 34,
              ),
      ),
    );
  }
}
