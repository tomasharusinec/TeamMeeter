import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/teammeeter_analytics.dart';
import '../utils/snackbar_utils.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => ConversationsScreenState();
}

class ConversationsScreenState extends State<ConversationsScreen> {
  bool _isLoading = true;
  bool _isCreatingConversation = false;
  List<Map<String, dynamic>> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadConversations(showLoadingIndicator: true);
  }

  Future<void> _showCreateConversationDialog() async {
    final nameController = TextEditingController();
    final participantUsernamesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0A),
        title: const Text(
          'Nový chat',
          style: TextStyle(color: Colors.white),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Názov chatu',
                  hintText: 'napr. Projekt tím',
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
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Usernames účastníkov',
                  hintText: 'napr. jano, eva, tomas',
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
              const Text(
                'Použi usernames oddelené čiarkou.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
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
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
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

  /// Voliteľné obnovenie zoznamu (napr. po prepnutí na záložku Chat v HomeScreen).
  Future<void> reloadConversations() =>
      _loadConversations(showLoadingIndicator: false);

  Future<void> _loadConversations({bool showLoadingIndicator = true}) async {
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
        final conversationId = conversation['id'];
        return conversationId is int && !groupConversationIds.contains(conversationId);
      }).toList();
      if (!mounted) return;
      setState(() => _conversations = directConversations);
    } catch (e) {
      if (!mounted) return;
      context.showLatestSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFF8B1A2C),
        ),
      );
    } finally {
      if (showLoadingIndicator && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showConversationActions(Map<String, dynamic> conversation) async {
    final conversationId = conversation['id'] as int?;
    if (conversationId == null) return;
    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A0A0A),
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ),
    );
    if (selectedAction != 'delete') return;

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteConversation(conversationId);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((c) => c['id'] == conversationId);
      });
      context.showLatestSnackBar(
        const SnackBar(
          content: Text('Konverzácia bola zmazaná'),
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
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_conversations.isEmpty) {
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: () =>
                _loadConversations(showLoadingIndicator: false),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: const [
                SizedBox(height: 140),
                Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 58),
                SizedBox(height: 16),
                Text(
                  'Zatiaľ nemáš žiadne konverzácie',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
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
              final conversationId = conversation['id'] as int?;
              final name = (conversation['name']?.toString().trim().isNotEmpty ??
                      false)
                  ? conversation['name'].toString().trim()
                  : 'Konverzácia #${conversationId ?? '?'}';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A0A).withAlpha(204),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(16)),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF8B1A2C),
                    child: Icon(Icons.forum_outlined, color: Colors.white),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'ID: ${conversationId ?? '-'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
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
  /// Napr. obnovenie zoznamu konverzácií po pridaní účastníka.
  final VoidCallback? onConversationMetadataChanged;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
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

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _startConnectionMaintenance();
  }

  @override
  void dispose() {
    _connectionMaintenanceTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _socket?.close();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    await _loadMessages();
    await _loadParticipants();
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    await api.syncPendingChatOperations();
    await _loadMessages();
    await _connectSocket();
  }

  Future<void> _loadMessages() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final messages = await api.getConversationMessages(widget.conversationId);
      if (!mounted) return;
      final merged = _mergeServerMessagesWithLocalPending(messages);
      setState(() => _messages = merged);
      await api.saveConversationMessagesToCache(widget.conversationId, merged);
      _scrollToBottom();
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

  Future<void> _loadParticipants() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final participants = await api.getConversationParticipants(
        widget.conversationId,
      );
      if (!mounted) return;
      setState(() => _participants = participants);
    } catch (_) {
      // Keep chat functional even if participant list fails.
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
              data['conversation_id'] == widget.conversationId) {
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
            api.saveConversationMessagesToCache(widget.conversationId, _messages);
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
        final syncedAny = await api.syncPendingChatOperations();
        if (syncedAny && mounted) {
          await _loadMessages();
        }
      } catch (_) {
        // Keep trying on next tick without breaking chat UI.
      } finally {
        _isSyncingPendingChatOps = false;
      }
    });
  }

  Future<void> _addParticipantDialog() async {
    final usernameController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0A),
        title: const Text('Pridať účastníka', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: usernameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'napr. janko123',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Zrušiť'),
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
                  conversationId: widget.conversationId,
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
            child: const Text('Pridať'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFile() async {
    if (_isUploadingFile) return;
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
            'conversation_id': widget.conversationId,
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
          conversationId: widget.conversationId,
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
          conversationId: widget.conversationId,
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
            'conversation_id': widget.conversationId,
            'text': payloadText,
          }),
        );
        shouldLogChatSend = true;
      } else {
        final api = Provider.of<AuthProvider>(context, listen: false).apiService;
        await api.queueOfflineConversationMessage(
          conversationId: widget.conversationId,
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
        conversationId: widget.conversationId,
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
            conversationId: widget.conversationId,
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

  void _addLocalPendingMessage(String text) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final localMessage = <String, dynamic>{
      'id': -DateTime.now().millisecondsSinceEpoch,
      'conversation_id': widget.conversationId,
      'sender_id': user?.idRegistration,
      'sender_username': user?.username ?? 'me',
      'text': text,
      'is_local_pending': true,
    };
    setState(() => _messages.add(localMessage));
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    api.saveConversationMessagesToCache(widget.conversationId, _messages);
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
      'conversation_id': widget.conversationId,
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
    api.saveConversationMessagesToCache(widget.conversationId, _messages);
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
                      color: const Color(0xFF1A0A0A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Nepodarilo sa načítať obrázok',
                      style: TextStyle(color: Colors.white70),
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

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final currentUserId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).user?.idRegistration;
    final isMine =
        message['sender_id'] != null && message['sender_id'] == currentUserId;

    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A0A0A),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.white),
              title: const Text('Reply', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(context).pop('reply'),
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(context).pop('delete'),
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
      api.saveConversationMessagesToCache(widget.conversationId, _messages);
      return;
    }
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteConversationMessage(
        conversationId: widget.conversationId,
        messageId: (messageId as num).toInt(),
      );
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m['id'] == messageId);
        if (_replyingTo?['id'] == messageId) _replyingTo = null;
      });
      await api.saveConversationMessagesToCache(widget.conversationId, _messages);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: appBarBg,
        actions: [
          IconButton(
            onPressed: _addParticipantDialog,
            tooltip: 'Pridať účastníka',
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            onPressed: () async {
              await _loadParticipants();
              if (!mounted) return;
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1A0A0A),
                builder: (_) => SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      const Text(
                        'Účastníci',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_participants.isEmpty)
                        const Text(
                          'Nie sú dostupní žiadni účastníci',
                          style: TextStyle(color: Colors.white60),
                        ),
                      for (final participant in _participants)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            participant['username']?.toString() ??
                                'user #${participant['id_registration'] ?? '?'}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'ID: ${participant['id_registration'] ?? '-'}',
                            style: const TextStyle(color: Colors.white60),
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
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
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
                                color: Colors.white.withAlpha(18),
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
                                                  color: Colors.black.withAlpha(
                                                    28,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.white.withAlpha(
                                                      20,
                                                    ),
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
                                                      color: Colors.white70,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      fileExtension
                                                              .trim()
                                                              .isEmpty
                                                          ? 'FILE'
                                                          : fileExtension
                                                                .toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.white70,
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
                                                  const Icon(
                                                    Icons.download_rounded,
                                                    size: 14,
                                                    color: Colors.white70,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      fullName,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
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
                color: Colors.black.withAlpha(18),
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
                          color: const Color(0xFF2A1111),
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
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _replyingTo = null),
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white70,
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
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
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
                                borderSide: BorderSide(
                                  color: Colors.white.withAlpha(16),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.white.withAlpha(16),
                                ),
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
