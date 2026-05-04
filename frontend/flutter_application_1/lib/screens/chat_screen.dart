// Jedna vrstva so zoznamom priamych konverzácií aj druhá s detailom otvoreného chatu používateľa.
// Rieši vytvorenie chatu, mazanie konverzácií, websocket, prílohy aj odosielanie správ cez offline frontu.
// AI generated with manual refinements




import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/permission_service.dart';
import '../services/teammeeter_analytics.dart';
import '../utils/snackbar_utils.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    super.key,
    this.chatTabSelected = false,
  });

  
  final bool chatTabSelected;

  @override
  State<ConversationsScreen> createState() => ConversationsScreenState();
}

class ConversationsScreenState extends State<ConversationsScreen> {
  bool _isLoading = true;
  bool _isCreatingConversation = false;
  List<Map<String, dynamic>> _conversations = [];
  Timer? _pollWhileVisibleTimer;

  @override
  // Tato funkcia pripravi zoznam konverzacii po otvoreni karty Chat.
  // Spusti polling a prve nacitanie direct konverzacii.
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPollTimerWithTabVisibility();
    });
    _loadConversations(showLoadingIndicator: true);
  }

  @override
  // Tato funkcia reaguje na prepnutie aktivnej chat zalozky.
  // Podla viditelnosti zapne alebo vypne polling konverzacii.
  void didUpdateWidget(covariant ConversationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chatTabSelected != oldWidget.chatTabSelected) {
      _syncPollTimerWithTabVisibility();
      if (widget.chatTabSelected) {
        _loadConversations(showLoadingIndicator: false);
      }
    }
  }

  @override
  // Tato funkcia zastavi polling timer pri odchode zo screenu.
  // Zabrani opakovanym API volaniam na pozadi.
  void dispose() {
    _pollWhileVisibleTimer?.cancel();
    super.dispose();
  }

  static const Duration _conversationListPollInterval = Duration(seconds: 22);

  // Tato funkcia drzi polling aktivny len ked je karta Chat otvorena.
  // Pravidelne obnovuje zoznam konverzacii bez blokovania UI.
  void _syncPollTimerWithTabVisibility() {
    if (!mounted) return;
    if (widget.chatTabSelected) {
      _pollWhileVisibleTimer ??= Timer.periodic(
        _conversationListPollInterval,
        (_) async {
          if (!mounted || !widget.chatTabSelected) return;
          await _loadConversations(
            showLoadingIndicator: false,
            suppressErrorSnackBars: true,
          );
        },
      );
    } else {
      _pollWhileVisibleTimer?.cancel();
      _pollWhileVisibleTimer = null;
    }
  }

  // Tato funkcia otvori dialog na vytvorenie novej konverzacie.
  // Zo vstupu vyberie nazov a participantov a odosle ich na backend.
  Future<void> _showCreateConversationDialog() async {
    final nameController = TextEditingController();
    final participantUsernamesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(dialogContext),
        title: Text(
          'Nový chat',
          style: TextStyle(color: AppColors.textPrimary(dialogContext)),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                decoration: InputDecoration(
                  labelText: 'Názov chatu',
                  hintText: 'napr. Projekt tím',
                  labelStyle: TextStyle(
                    color: AppColors.textMuted(dialogContext),
                  ),
                  hintStyle: TextStyle(
                    color: AppColors.textDisabled(dialogContext),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Zadaj názov chatu';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: participantUsernamesController,
                style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                decoration: InputDecoration(
                  labelText: 'Usernames účastníkov',
                  hintText: 'napr. jano, eva, tomas',
                  labelStyle: TextStyle(
                    color: AppColors.textMuted(dialogContext),
                  ),
                  hintStyle: TextStyle(
                    color: AppColors.textDisabled(dialogContext),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Zadaj aspoň 1 username';
                  }
                  final parsed = _parseUsernames(value);
                  if (parsed.isEmpty) {
                    return 'Nesprávny formát username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Použi usernames oddelené čiarkou.',
                style: TextStyle(
                  color: AppColors.textSecondary(dialogContext),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Zrušiť'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
            ),
            onPressed: _isCreatingConversation
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setState(() => _isCreatingConversation = true);
                    try {
                      final api = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      ).apiService;
                      final name = nameController.text.trim();
                      final participantUsernames = _parseUsernames(
                        participantUsernamesController.text.trim(),
                      );
                      final conversationId = await api.createConversation(
                        name: name,
                        participantUsernames: participantUsernames,
                      );
                      if (!mounted) return;
                      Navigator.of(dialogContext).pop();
                      await _loadConversations(showLoadingIndicator: true);
                      if (mounted && conversationId < 0) {
                        context.showLatestSnackBar(
                          const SnackBar(
                            content: Text(
                              'Chat uložený offline. Po pripojení sa vytvorí na serveri a správy sa odošlú.',
                            ),
                            backgroundColor: Color(0xFFEF6C00),
                          ),
                        );
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            conversationId: conversationId,
                            title: name,
                            onConversationMetadataChanged: () {
                              if (mounted) {
                                _loadConversations(showLoadingIndicator: false);
                              }
                            },
                          ),
                        ),
                      );
                      if (mounted) {
                        await _loadConversations(showLoadingIndicator: false);
                      }
                    } catch (e) {
                      if (!mounted) return;
                      context.showLatestSnackBar(
                        SnackBar(
                          content: Text(e.toString().replaceAll('Exception: ', '')),
                          backgroundColor: const Color(0xFF8B1A2C),
                        ),
                      );
                    } finally {
                      if (mounted) {
                        setState(() => _isCreatingConversation = false);
                      }
                    }
                  },
            child: _isCreatingConversation
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(dialogContext).colorScheme.onPrimary,
                    ),
                  )
                : const Text('Vytvoriť'),
          ),
        ],
      ),
    );
  }

  List<String> _parseUsernames(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  int? _coerceDmConversationListId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  
  // Tato funkcia je verejny refresh zoznamu konverzacii pre rodicovsky screen.
  // Vola interny loader bez blokujuceho spinnera.
  Future<void> reloadConversations() => _loadConversations(
        showLoadingIndicator: false,
        suppressErrorSnackBars: false,
      );

  Future<void> _loadConversations({
    bool showLoadingIndicator = true,
    bool suppressErrorSnackBars = false,
  }) async {
    if (showLoadingIndicator && mounted) setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final results = await Future.wait([
        api.getConversations(),
        api.getGroups(),
      ]);
      final conversations = results[0] as List<Map<String, dynamic>>;
      final groups = results[1] as List<dynamic>;
      final groupConversationIds = groups
          .map((group) => group.conversationId)
          .whereType<int>()
          .toSet();
      final directConversations = conversations.where((conversation) {
        final cid = _coerceDmConversationListId(conversation['id']);
        return cid != null && !groupConversationIds.contains(cid);
      }).toList();
      if (!mounted) return;
      setState(() => _conversations = directConversations);
    } catch (e) {
      if (!mounted) return;
      if (!suppressErrorSnackBars) {
        context.showLatestSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFF8B1A2C),
          ),
        );
      }
    } finally {
      if (showLoadingIndicator && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Tato funkcia otvori spodne menu pre akcie nad konverzaciou.
  // Aktuálne riesi mazanie konverzacie a aktualizuje lokalny zoznam.
  Future<void> _showConversationActions(Map<String, dynamic> conversation) async {
    final conversationId = _coerceDmConversationListId(conversation['id']);
    if (conversationId == null) return;
    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bottomSheetBackground(context),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (selectedAction != 'delete') return;

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final deletedOnServer = await api.deleteConversation(conversationId);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((c) => c['id'] == conversationId);
      });
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            deletedOnServer
                ? 'Konverzácia bola zmazaná'
                : 'Konverzácia odstránená lokálne. Po pripojení sa dokončí vymazanie na serveri.',
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
    }
  }

  @override
  // Tato funkcia vykresli obsah tabky konverzacii.
  // Rieseny je loading stav, prazdny stav aj list s tlacidlom na novy chat.
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.circularProgressOnBackground(context),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: () =>
                _loadConversations(showLoadingIndicator: false),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 140),
                Icon(
                  Icons.chat_bubble_outline,
                  color: AppColors.textDisabled(context),
                  size: 58,
                ),
                const SizedBox(height: 16),
                Text(
                  'Zatiaľ nemáš žiadne konverzácie',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted(context)),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 14,
            child: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
              onPressed: _showCreateConversationDialog,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Nový chat'),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _loadConversations(showLoadingIndicator: false),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
            itemCount: _conversations.length,
            itemBuilder: (context, index) {
              final conversation = _conversations[index];
              final conversationId = _coerceDmConversationListId(
                conversation['id'],
              );
              final name = (conversation['name']?.toString().trim().isNotEmpty ??
                      false)
                  ? conversation['name'].toString().trim()
                  : 'Konverzácia #${conversationId ?? '?'}';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.listCardBackground(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.listCardBorder(context),
                  ),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF8B1A2C),
                    child: Icon(Icons.forum_outlined, color: Colors.white),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  subtitle: Text(
                    conversationId != null && conversationId < 0
                        ? 'Offline — čaká na synchronizáciu (#$conversationId)'
                        : 'ID: ${conversationId ?? '-'}',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: AppColors.textDisabled(context),
                  ),
                  onLongPress: () => _showConversationActions(conversation),
                  onTap: conversationId == null
                      ? null
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                conversationId: conversationId,
                                title: name,
                                onConversationMetadataChanged: () {
                                  if (mounted) {
                                    _loadConversations(
                                      showLoadingIndicator: false,
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                          if (mounted) {
                            _loadConversations(showLoadingIndicator: false);
                          }
                        },
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 14,
          child: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF8B1A2C),
            foregroundColor: Colors.white,
            onPressed: _showCreateConversationDialog,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Nový chat'),
          ),
        ),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String title;
  
  
  final int? groupId;
  
  final VoidCallback? onConversationMetadataChanged;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.groupId,
    this.onConversationMetadataChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _maxFileSizeBytes = 10 * 1024 * 1024;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  WebSocket? _socket;
  Timer? _connectionMaintenanceTimer;
  bool _isSocketConnected = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploadingFile = false;
  bool _isSyncingPendingChatOps = false;
  Completer<void>? _awaitingFileCompleter;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _participants = [];
  Map<String, dynamic>? _replyingTo;
  
  bool _canDeleteOthersGroupMessages = false;
  late int _effectiveConversationId;

  @override
  // Tato funkcia pripravi detail konkretneho chatu.
  // Nastavi conversation id, nacita data a spusti udrzbu socket spojenia.
  void initState() {
    super.initState();
    _effectiveConversationId = widget.conversationId;
    _initializeChat();
    _startConnectionMaintenance();
  }

  @override
  // Tato funkcia zastavi maintenance timer a zavrie socket spojenie.
  // Uvolni aj textovy a scroll controller po zatvoreni chatu.
  void dispose() {
    _connectionMaintenanceTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _socket?.close();
    super.dispose();
  }

  int? _coerceConversationIdField(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _disconnectSocketQuietly() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    if (mounted) {
      setState(() => _isSocketConnected = false);
    }
  }

  Future<bool> _reconcileConversationId() async {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final resolved = await api.resolveConversationApiId(_effectiveConversationId);
    if (!mounted) return false;
    if (resolved != _effectiveConversationId && resolved > 0) {
      setState(() => _effectiveConversationId = resolved);
      await _disconnectSocketQuietly();
      return true;
    }
    return false;
  }

  Future<void> _initializeChat() async {
    await _reconcileConversationId();
    if (widget.groupId != null) {
      unawaited(_loadGroupMessageDeleteCapability());
    }
    await _loadMessages();
    await _loadParticipants();
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    await api.syncPendingChatOperations();
    await _reconcileConversationId();
    await _loadMessages(showBlockingLoader: false);
    await _connectSocket();
  }

  // Tato funkcia nacita spravy konverzacie a spoji ich s lokalnymi pending spravami.
  // Po nacitani ulozi vysledok do cache a posunie zoznam na spodok.
  Future<void> _loadMessages({bool showBlockingLoader = true}) async {
    if (showBlockingLoader && mounted) setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final messages = await api.getConversationMessages(_effectiveConversationId);
      if (!mounted) return;
      final merged = _mergeServerMessagesWithLocalPending(messages);
      setState(() => _messages = merged);
      await api.saveConversationMessagesToCache(_effectiveConversationId, merged);
      _scrollToBottom();
    } catch (e) {
      if (!mounted || !showBlockingLoader) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (showBlockingLoader && mounted) setState(() => _isLoading = false);
    }
  }

  // Tato funkcia nacita participantov aktualnej konverzacie.
  // Pouziva sa po otvoreni chatu aj po pridani noveho clena.
  Future<void> _loadParticipants() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final participants = await api.getConversationParticipants(
        _effectiveConversationId,
      );
      if (!mounted) return;
      setState(() => _participants = participants);
    } catch (_) {
      
    }
  }

  // Tato funkcia overi, ci moze pouzivatel mazat cudzie spravy v skupinovom chate.
  // Kontroluje roly aj permission delete_messages.
  Future<void> _loadGroupMessageDeleteCapability() async {
    final gid = widget.groupId;
    if (gid == null) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.user?.idRegistration;
    if (uid == null) return;
    try {
      final api = auth.apiService;
      final userRoles = await api.getUserRolesInGroup(groupId: gid, userId: uid);
      if (userRoles.any(
        (r) => (r['name']?.toString() ?? '') == 'Manager',
      )) {
        if (mounted) setState(() => _canDeleteOthersGroupMessages = true);
        return;
      }
      final groupRoles = await api.getGroupRoles(gid);
      final userRoleIds = userRoles
          .map((r) => r['id_role'])
          .whereType<num>()
          .map((n) => n.toInt())
          .toSet();
      var can = false;
      for (final r in groupRoles) {
        final rid = r['id_role'];
        final id = rid is int ? rid : (rid is num ? rid.toInt() : null);
        if (id == null || !userRoleIds.contains(id)) continue;
        final name = (r['name'] ?? '').toString();
        if (name == 'Manager') {
          can = true;
          break;
        }
        final perms = r['permissions'];
        final list = perms is List
            ? perms.map((e) => e.toString()).toList()
            : <String>[];
        if (list.contains('delete_messages')) {
          can = true;
          break;
        }
      }
      if (mounted) setState(() => _canDeleteOthersGroupMessages = can);
    } catch (_) {
      
    }
  }

  Future<void> _connectSocket() async {
    if (_isSocketConnected) return;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.token;
      if (token == null || token.isEmpty) return;

      final wsUrl = Uri.parse(
        ApiService.baseUrl
            .replaceFirst('http://', 'ws://')
            .replaceFirst('https://', 'wss://'),
      ).replace(path: '/websocket');

      final socket = await WebSocket.connect(wsUrl.toString());
      socket.add(jsonEncode({'type': 'auth', 'token': token}));

      _socket = socket;
      setState(() => _isSocketConnected = true);

      socket.listen(
        (raw) {
          if (raw is! String) return;
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final type = data['type']?.toString();
          if (type == 'awaiting_file') {
            _awaitingFileCompleter?.complete();
            _awaitingFileCompleter = null;
            return;
          }
          if (type == 'new_message' &&
              _coerceConversationIdField(data['conversation_id']) ==
                  _effectiveConversationId) {
            if (!mounted) return;
            setState(() {
              _messages.removeWhere(
                (message) =>
                    message['is_local_pending'] == true &&
                    _isLikelySameMessage(data, message),
              );
              final incomingId = data['id'];
              final alreadyPresent = _messages.any((message) {
                final existingId = message['id'];
                return incomingId != null &&
                    existingId != null &&
                    existingId == incomingId;
              });
              if (!alreadyPresent) {
                _messages.add(data);
              }
            });
            final api = Provider.of<AuthProvider>(context, listen: false).apiService;
            api.saveConversationMessagesToCache(_effectiveConversationId, _messages);
            _scrollToBottom();
          }
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isSocketConnected = false);
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isSocketConnected = false);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSocketConnected = false);
    }
  }

  void _startConnectionMaintenance() {
    _connectionMaintenanceTimer?.cancel();
    _connectionMaintenanceTimer = Timer.periodic(const Duration(seconds: 4), (
      _,
    ) async {
      if (!mounted) return;
      try {
        final api = Provider.of<AuthProvider>(context, listen: false).apiService;
        final isReachable = await api.isServerReachable();
        if (!isReachable) return;

        if (!_isSocketConnected) {
          await _connectSocket();
        }

        if (_isSyncingPendingChatOps) return;
        _isSyncingPendingChatOps = true;
        final hadLocalPending =
            _messages.any((m) => m['is_local_pending'] == true);
        final syncedAny = await api.syncPendingChatOperations();
        final idChanged = await _reconcileConversationId();
        
        
        if (mounted && (syncedAny || hadLocalPending || idChanged)) {
          await _loadMessages(showBlockingLoader: false);
          if (widget.groupId != null) {
            unawaited(_loadGroupMessageDeleteCapability());
          }
        }
        if (mounted && !_isSocketConnected) {
          await _connectSocket();
        }
      } catch (_) {
        
      } finally {
        _isSyncingPendingChatOps = false;
      }
    });
  }

  // Tato funkcia otvori dialog na pridanie dalsieho ucastnika do chatu.
  // Po uspesnom pridani obnovi participantov a metadata konverzacie.
  Future<void> _addParticipantDialog() async {
    final usernameController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.dialogBackground(dialogContext),
        title: Text(
          'Pridať účastníka',
          style: TextStyle(color: AppColors.textPrimary(dialogContext)),
        ),
        content: TextField(
          controller: usernameController,
          style: TextStyle(color: AppColors.textPrimary(dialogContext)),
          decoration: InputDecoration(
            labelText: 'Username',
            hintText: 'napr. janko123',
            labelStyle: TextStyle(color: AppColors.textMuted(dialogContext)),
            hintStyle: TextStyle(color: AppColors.textDisabled(dialogContext)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Zrušiť',
              style: TextStyle(color: AppColors.textSecondary(dialogContext)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = usernameController.text.trim();
              if (username.isEmpty) return;
              try {
                final api = Provider.of<AuthProvider>(
                  context,
                  listen: false,
                ).apiService;
                await api.addConversationParticipant(
                  conversationId: _effectiveConversationId,
                  username: username,
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _loadParticipants();
                widget.onConversationMetadataChanged?.call();
                context.showLatestSnackBar(
                  const SnackBar(
                    content: Text('Účastník bol pridaný'),
                    backgroundColor: Color(0xFF8B1A2C),
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
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A2C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Pridať'),
          ),
        ],
      ),
    );
  }

  // Tato funkcia odosle subor ako prilohu spravy.
  // Pri vypadku siete ulozi odoslanie offline a doplni lokalny pending zaznam.
  Future<void> _sendFile() async {
    if (_isUploadingFile) return;
    if (!await PermissionService.hasGalleryReadAccess()) {
      final granted = await PermissionService.requestGalleryPermission();
      if (!granted) {
        if (!mounted) return;
        context.showLatestSnackBar(
          const SnackBar(
            content: Text(
              'Bez prístupu ku súborom a médiám nemôžete priložiť prílohu.',
            ),
            backgroundColor: Color(0xFF8B1A2C),
          ),
        );
        return;
      }
    }
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) {
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa načítať cestu k súboru'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }
    final ioFile = File(filePath);
    if (!ioFile.existsSync()) {
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Vybraný súbor neexistuje'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }
    final bytes = await ioFile.readAsBytes();
    if (bytes.isEmpty) {
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa načítať súbor'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }
    if (bytes.length > _maxFileSizeBytes) {
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Súbor je príliš veľký. Maximum je 10 MB.'),
          backgroundColor: Color(0xFF8B1A2C),
        ),
      );
      return;
    }

    final fileName = file.name;
    final dotIdx = fileName.lastIndexOf('.');
    final pureName = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
    final extension = dotIdx > 0 ? fileName.substring(dotIdx + 1) : 'bin';
    final text = _messageController.text.trim();

    setState(() => _isUploadingFile = true);
    try {
      if (_socket != null && _isSocketConnected) {
        _awaitingFileCompleter = Completer<void>();
        _socket!.add(
          jsonEncode({
            'type': 'send_message_with_file',
            'conversation_id': _effectiveConversationId,
            'text': text,
            'file_name': pureName,
            'file_extension': extension,
          }),
        );
        await _awaitingFileCompleter!.future.timeout(const Duration(seconds: 8));
        _socket!.add(bytes);
      } else {
        final api = Provider.of<AuthProvider>(context, listen: false).apiService;
        await api.queueOfflineConversationFileMessage(
          conversationId: _effectiveConversationId,
          text: text,
          filePath: filePath,
          fileName: pureName,
          fileExtension: extension,
        );
        _addLocalPendingFileMessage(
          text: text,
          fileName: pureName,
          fileExtension: extension,
        );
        if (!mounted) return;
        context.showLatestSnackBar(
          const SnackBar(
            content: Text('Offline: súbor sa odošle po opätovnom pripojení'),
            backgroundColor: Color(0xFFEF6C00),
          ),
        );
      }
      _messageController.clear();
    } catch (e) {
      try {
        final api = Provider.of<AuthProvider>(context, listen: false).apiService;
        await api.queueOfflineConversationFileMessage(
          conversationId: _effectiveConversationId,
          text: text,
          filePath: filePath,
          fileName: pureName,
          fileExtension: extension,
        );
        _addLocalPendingFileMessage(
          text: text,
          fileName: pureName,
          fileExtension: extension,
        );
        if (!mounted) return;
        _messageController.clear();
        context.showLatestSnackBar(
          const SnackBar(
            content: Text('Súbor je uložený offline a odošle sa neskôr'),
            backgroundColor: Color(0xFFEF6C00),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        context.showLatestSnackBar(
          SnackBar(
            content: Text(
              'Odoslanie súboru zlyhalo: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: const Color(0xFF8B1A2C),
          ),
        );
      }
    } finally {
      _awaitingFileCompleter = null;
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  // Tato funkcia odosle textovu spravu alebo reply.
  // Ak socket nie je dostupny, spravu zaradi do offline fronty.
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;
    final isReply = _replyingTo != null;
    final replyPrefix = _replyingTo == null
        ? ''
        : 'Reply to ${_replyingTo!['sender_username'] ?? 'user'}: '
              '${(_replyingTo!['text'] ?? '').toString().replaceAll('\n', ' ').trim()}\n';
    final payloadText = '$replyPrefix$text';

    setState(() => _isSending = true);
    var usedSocketTransport = false;
    var shouldLogChatSend = false;
    try {
      if (_socket != null && _isSocketConnected) {
        usedSocketTransport = true;
        _socket!.add(
          jsonEncode({
            'type': 'send_message',
            'conversation_id': _effectiveConversationId,
            'text': payloadText,
          }),
        );
        shouldLogChatSend = true;
      } else {
        final api = Provider.of<AuthProvider>(context, listen: false).apiService;
        await api.queueOfflineConversationMessage(
          conversationId: _effectiveConversationId,
          text: payloadText,
        );
        _addLocalPendingMessage(payloadText);
        shouldLogChatSend = true;
        if (!mounted) return;
        context.showLatestSnackBar(
          const SnackBar(
            content: Text('Offline: správa sa odošle po opätovnom pripojení'),
            backgroundColor: Color(0xFFEF6C00),
          ),
        );
      }
      _messageController.clear();
    } catch (_) {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.queueOfflineConversationMessage(
        conversationId: _effectiveConversationId,
        text: payloadText,
      );
      _addLocalPendingMessage(payloadText);
      usedSocketTransport = false;
      shouldLogChatSend = true;
      if (!mounted) return;
      _messageController.clear();
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Správa je uložená offline a odošle sa neskôr'),
          backgroundColor: Color(0xFFEF6C00),
        ),
      );
    } finally {
      if (shouldLogChatSend) {
        unawaited(
          TeamMeeterAnalytics.instance.logChatMessageSend(
            conversationId: _effectiveConversationId,
            socketConnected: usedSocketTransport,
            isReply: isReply,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _isSending = false;
          _replyingTo = null;
        });
      }
    }
  }

  // Tato funkcia prida lokalnu pending spravu do UI okamzite po odoslani.
  // Uzivatel vidi spravu hned, aj ked server ju potvrdi az neskor.
  void _addLocalPendingMessage(String text) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final localMessage = <String, dynamic>{
      'id': -DateTime.now().millisecondsSinceEpoch,
      'conversation_id': _effectiveConversationId,
      'sender_id': user?.idRegistration,
      'sender_username': user?.username ?? 'me',
      'text': text,
      'is_local_pending': true,
    };
    setState(() => _messages.add(localMessage));
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    api.saveConversationMessagesToCache(_effectiveConversationId, _messages);
    _scrollToBottom();
  }

  void _addLocalPendingFileMessage({
    required String text,
    required String fileName,
    required String fileExtension,
  }) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final localMessage = <String, dynamic>{
      'id': -DateTime.now().millisecondsSinceEpoch,
      'conversation_id': _effectiveConversationId,
      'sender_id': user?.idRegistration,
      'sender_username': user?.username ?? 'me',
      'text': text,
      'is_local_pending': true,
      'file': {
        'id': -1,
        'name': fileName,
        'extension': fileExtension,
      },
    };
    setState(() => _messages.add(localMessage));
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    api.saveConversationMessagesToCache(_effectiveConversationId, _messages);
    _scrollToBottom();
  }

  List<Map<String, dynamic>> _mergeServerMessagesWithLocalPending(
    List<Map<String, dynamic>> serverMessages,
  ) {
    final pendingMessages = _messages
        .where((message) => message['is_local_pending'] == true)
        .toList();

    final merged = List<Map<String, dynamic>>.from(serverMessages);
    for (final pending in pendingMessages) {
      final alreadySynced = serverMessages.any(
        (serverMessage) => _isLikelySameMessage(serverMessage, pending),
      );
      if (!alreadySynced) {
        merged.add(pending);
      }
    }
    return merged;
  }

  bool _isLikelySameMessage(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aText = (a['text'] ?? '').toString().trim();
    final bText = (b['text'] ?? '').toString().trim();
    if (aText != bText) return false;

    final aSender = a['sender_id'];
    final bSender = b['sender_id'];
    if (aSender != null && bSender != null && aSender != bSender) return false;

    final aFile = a['file'];
    final bFile = b['file'];
    if (aFile == null && bFile == null) return true;
    if (aFile == null || bFile == null) return false;

    final aFileMap = Map<String, dynamic>.from(aFile);
    final bFileMap = Map<String, dynamic>.from(bFile);
    final aFileName = (aFileMap['name'] ?? '').toString().trim();
    final bFileName = (bFileMap['name'] ?? '').toString().trim();
    final aFileExt = (aFileMap['extension'] ?? '').toString().trim();
    final bFileExt = (bFileMap['extension'] ?? '').toString().trim();
    return aFileName == bFileName && aFileExt == bFileExt;
  }

  bool _isImageExtension(String extension) {
    final normalized = extension.trim().toLowerCase();
    return normalized == 'png' ||
        normalized == 'jpg' ||
        normalized == 'jpeg' ||
        normalized == 'webp' ||
        normalized == 'gif';
  }

  IconData _fileTypeIcon(String extension) {
    final ext = extension.trim().toLowerCase();
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (ext == 'doc' || ext == 'docx' || ext == 'txt' || ext == 'rtf') {
      return Icons.description_outlined;
    }
    if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') {
      return Icons.table_chart_outlined;
    }
    if (ext == 'zip' || ext == 'rar' || ext == '7z' || ext == 'tar') {
      return Icons.archive_outlined;
    }
    if (ext == 'mp4' || ext == 'mov' || ext == 'mkv' || ext == 'avi') {
      return Icons.movie_outlined;
    }
    if (ext == 'mp3' || ext == 'wav' || ext == 'ogg' || ext == 'flac') {
      return Icons.audiotrack_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _openImagePreview({
    required String imageUrl,
    required String? token,
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(220),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  headers: token == null
                      ? null
                      : {'Authorization': 'Bearer $token'},
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.imagePreviewErrorBackground(
                        dialogContext,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Nepodarilo sa načítať obrázok',
                      style: TextStyle(
                        color: AppColors.textMuted(dialogContext),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 12,
              right: 44,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAttachment(Map<String, dynamic> file) async {
    try {
      final fileId = file['id'];
      if (fileId == null) return;
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final payload = await api.downloadConversationFile((fileId as num).toInt());
      final filename = payload['filename']?.toString() ?? 'attachment_$fileId';
      final bytes = Uint8List.fromList(payload['bytes'] as List<int>);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Uložiť súbor',
        fileName: filename,
        bytes: bytes,
      );
      if (!mounted || savedPath == null) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text('Súbor uložený: $filename'),
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
    }
  }

  // Tato funkcia otvori akcie nad konkretnou spravou (reply alebo delete).
  // Podla vyberu bud pripravi reply rezim, alebo vykona mazanie spravy.
  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final currentUserId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).user?.idRegistration;
    final isMine =
        message['sender_id'] != null && message['sender_id'] == currentUserId;

    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bottomSheetBackground(context),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.reply,
                color: AppColors.textPrimary(sheetCtx),
              ),
              title: Text(
                'Reply',
                style: TextStyle(color: AppColors.textPrimary(sheetCtx)),
              ),
              onTap: () => Navigator.of(sheetCtx).pop('reply'),
            ),
            if (isMine ||
                (widget.groupId != null && _canDeleteOthersGroupMessages))
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('delete'),
              ),
          ],
        ),
      ),
    );

    if (selectedAction == 'reply') {
      setState(() => _replyingTo = message);
      return;
    }
    if (selectedAction != 'delete') return;

    final messageId = message['id'];
    if (messageId == null || (messageId is num && messageId.toInt() <= 0)) {
      setState(() => _messages.remove(message));
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      api.saveConversationMessagesToCache(_effectiveConversationId, _messages);
      return;
    }
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final deletedOnServer = await api.deleteConversationMessage(
        conversationId: _effectiveConversationId,
        messageId: (messageId as num).toInt(),
      );
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m['id'] == messageId);
        if (_replyingTo?['id'] == messageId) _replyingTo = null;
      });
      await api.saveConversationMessagesToCache(_effectiveConversationId, _messages);
      if (!deletedOnServer && mounted) {
        context.showLatestSnackBar(
          const SnackBar(
            content: Text('Offline: zmazanie sa dokončí po pripojení'),
            backgroundColor: Color(0xFFEF6C00),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  // Tato funkcia vykresli detail chat konverzacie.
  // Obsahuje app bar, zoznam sprav, reply panel a composer na odoslanie spravy.
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.idRegistration;
    final token = authProvider.token;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDarkMode ? const Color(0xFF1A0A0A) : const Color(0xFFF2ECEC);
    final screenBg = isDarkMode ? const Color(0xFF0D0D0D) : const Color(0xFFF6F3F3);
    final myBubbleBg = isDarkMode ? const Color(0xFF8B1A2C) : const Color(0xFFD66A7A);
    final otherBubbleBg = isDarkMode ? const Color(0xFF2A1111) : Colors.white;
    final primaryTextColor = isDarkMode ? Colors.white : const Color(0xFF1A1A1A);
    final secondaryTextColor = isDarkMode
        ? Colors.white70
        : const Color(0xFF666666);
    final inputBg = isDarkMode ? const Color(0xFF2A1111) : Colors.white;
    final bubbleBorderColor = AppColors.bubbleOutline(context);
    final fileChipBg = AppColors.bubbleFileChipBackground(context);
    final fileChipBorder = AppColors.bubbleFileChipBorder(context);
    final fileChipFg = AppColors.bubbleFileChipForeground(context);
    final replyBarBg = AppColors.replyPreviewBackground(context);
    final composerBg = AppColors.composerBarBackground(context);
    final inputBorderSide = BorderSide(
      color: isDarkMode
          ? Colors.white.withAlpha(16)
          : const Color(0xFF000000).withAlpha(14),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: appBarBg,
        actions: [
          IconButton(
            onPressed: _effectiveConversationId < 0
                ? () {
                    context.showLatestSnackBar(
                      const SnackBar(
                        content: Text(
                          'Účastníkov pridáš po synchronizácii chatu na server (internet).',
                        ),
                        backgroundColor: Color(0xFFEF6C00),
                      ),
                    );
                  }
                : _addParticipantDialog,
            tooltip: 'Pridať účastníka',
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            onPressed: () async {
              await _loadParticipants();
              if (!mounted) return;
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.bottomSheetBackground(context),
                builder: (sheetCtx) => SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(
                        'Účastníci',
                        style: TextStyle(
                          color: AppColors.textPrimary(sheetCtx),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_participants.isEmpty)
                        Text(
                          'Nie sú dostupní žiadni účastníci',
                          style: TextStyle(color: AppColors.textMuted(sheetCtx)),
                        ),
                      for (final participant in _participants)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            participant['username']?.toString() ??
                                'user #${participant['id_registration'] ?? '?'}',
                            style: TextStyle(color: AppColors.textPrimary(sheetCtx)),
                          ),
                          subtitle: Text(
                            'ID: ${participant['id_registration'] ?? '-'}',
                            style: TextStyle(color: AppColors.textMuted(sheetCtx)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
            tooltip: 'Zobraziť účastníkov',
            icon: const Icon(Icons.group_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              _isSocketConnected ? Icons.wifi : Icons.wifi_off,
              color: _isSocketConnected ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
      body: Container(
        color: screenBg,
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: AppColors.circularProgressOnBackground(context),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isMine =
                            message['sender_id'] != null &&
                            message['sender_id'] == currentUserId;
                        return GestureDetector(
                          onLongPress: () => _showMessageActions(message),
                          child: Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            constraints: const BoxConstraints(maxWidth: 290),
                            decoration: BoxDecoration(
                              color: isMine
                                  ? myBubbleBg
                                  : otherBubbleBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: bubbleBorderColor,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMine &&
                                    (message['sender_username']?.toString() ??
                                            '')
                                        .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      message['sender_username'].toString(),
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                Text(
                                  message['text']?.toString() ?? '',
                                  style: TextStyle(color: primaryTextColor),
                                ),
                                if (message['is_local_pending'] == true)
                                  Padding(
                                    padding: EdgeInsets.only(top: 5),
                                    child: Text(
                                      'Čaká na odoslanie...',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                if (message['file'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Builder(
                                      builder: (_) {
                                        final fileMap = Map<String, dynamic>.from(
                                          message['file'],
                                        );
                                        final fileId = fileMap['id'];
                                        final fileName =
                                            fileMap['name']?.toString() ?? 'file';
                                        final fileExtension =
                                            fileMap['extension']?.toString() ?? '';
                                        final fullName = fileExtension.isEmpty
                                            ? fileName
                                            : '$fileName.$fileExtension';
                                        final downloadable =
                                            fileId is num && fileId.toInt() > 0;
                                        final isImage = _isImageExtension(
                                          fileExtension,
                                        );
                                        final imageUrl = downloadable
                                            ? '${ApiService.baseUrl}/conversations/files/${fileId.toInt()}'
                                            : null;

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (isImage &&
                                                imageUrl != null &&
                                                token != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                child: InkWell(
                                                  onTap: () => _openImagePreview(
                                                    imageUrl: imageUrl,
                                                    token: token,
                                                    title: fullName,
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 220,
                                                            maxHeight: 180,
                                                          ),
                                                      child: Image.network(
                                                        imageUrl,
                                                        headers: {
                                                          'Authorization':
                                                              'Bearer $token',
                                                        },
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, __, ___) =>
                                                                const SizedBox.shrink(),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (!isImage)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: fileChipBg,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: fileChipBorder,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _fileTypeIcon(
                                                        fileExtension,
                                                      ),
                                                      size: 18,
                                                      color: fileChipFg,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      fileExtension
                                                              .trim()
                                                              .isEmpty
                                                          ? 'FILE'
                                                          : fileExtension
                                                                .toUpperCase(),
                                                      style: TextStyle(
                                                        color: fileChipFg,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            InkWell(
                                              onTap: downloadable
                                                  ? () => _downloadAttachment(
                                                      fileMap,
                                                    )
                                                  : null,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.download_rounded,
                                                    size: 14,
                                                    color: fileChipFg,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      fullName,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: fileChipFg,
                                                        fontSize: 12,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                color: composerBg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyingTo != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: replyBarBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Reply na: ${_replyingTo!['sender_username'] ?? 'user'} - '
                                '${(_replyingTo!['text'] ?? '').toString()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _replyingTo = null),
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _isUploadingFile ? null : _sendFile,
                          icon: _isUploadingFile
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isDarkMode
                                        ? Colors.white
                                        : const Color(0xFF8B1A2C),
                                  ),
                                )
                              : Icon(Icons.attach_file, color: secondaryTextColor),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: TextStyle(color: primaryTextColor),
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Napíš správu...',
                              hintStyle: TextStyle(color: secondaryTextColor),
                              filled: true,
                              fillColor: inputBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: inputBorderSide,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: inputBorderSide,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isSending ? null : _sendMessage,
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF8B1A2C),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
