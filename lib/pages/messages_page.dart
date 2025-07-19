import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Messaging page that shows an inbox of conversations and
/// individual chat threads between users.
class MessagesPage extends StatefulWidget {
  /// ID of the logged in user.
  final String currentUserId;

  /// Optional ID of another user to open directly.
  final String? otherUserId;

  /// Optional message to pre-fill when opening a thread.
  final String? initialMessage;

  const MessagesPage({
    super.key,
    required this.currentUserId,
    this.otherUserId,
    this.initialMessage,
  });

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _threadUserId;
  String? _otherUsername;

  @override
  void initState() {
    super.initState();
    _threadUserId = widget.otherUserId;
    if (widget.initialMessage != null) {
      _controller.text = widget.initialMessage!;
    }
    if (_threadUserId != null) {
      _loadOtherUsername();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOtherUsername() async {
    if (_threadUserId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_threadUserId)
        .get();
    setState(() {
      _otherUsername = doc.data()?['username'] ?? 'Unknown';
    });
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('MM/dd h:mm a').format(dt);
  }

  Future<void> _startNewMessage() async {
    final controller = TextEditingController();
    final otherId = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Recipient ID'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'User ID'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final id = controller.text.trim();
                Navigator.pop(context, id.isEmpty ? null : id);
              },
              child: const Text('Chat'),
            ),
          ],
        );
      },
    );
    if (otherId != null && otherId.isNotEmpty) {
      setState(() {
        _threadUserId = otherId;
        _otherUsername = null;
        _controller.clear();
      });
      await _loadOtherUsername();
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _threadUserId == null) return;

    await FirebaseFirestore.instance.collection('messages').add({
      'fromUserId': widget.currentUserId,
      'toUserId': _threadUserId,
      'content': text,
      'timestamp': DateTime.now(),
    });

    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildInbox() {
    final query = FirebaseFirestore.instance
        .collection('messages')
        .where(Filter.or(
          Filter('fromUserId', isEqualTo: widget.currentUserId),
          Filter('toUserId', isEqualTo: widget.currentUserId),
        ))
        .orderBy('timestamp', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        final Map<String, Map<String, dynamic>> latest = {};
        for (final doc in docs) {
          final data = doc.data();
          final otherId = data['fromUserId'] == widget.currentUserId
              ? data['toUserId']
              : data['fromUserId'];
          if (!latest.containsKey(otherId)) {
            latest[otherId] = data;
          }
        }
        if (latest.isEmpty) {
          return const Center(child: Text('No messages'));
        }
        final entries = latest.entries.toList();
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final otherId = entries[index].key;
            final data = entries[index].value;
            final Timestamp? ts = data['timestamp'];
            return ListTile(
              title: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherId)
                    .get(),
                builder: (context, snap) {
                  final name = snap.data?.data()?['username'] ?? 'Unknown';
                  return Text(name);
                },
              ),
              subtitle: Text(data['content'] ?? ''),
              trailing: Text(
                _formatTimestamp(ts),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                setState(() {
                  _threadUserId = otherId;
                  _otherUsername = null;
                  _controller.clear();
                });
                _loadOtherUsername();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildThread() {
    final otherId = _threadUserId!;
    final query = FirebaseFirestore.instance
        .collection('messages')
        .where(
          Filter.or(
            Filter.and(
              Filter('fromUserId', isEqualTo: widget.currentUserId),
              Filter('toUserId', isEqualTo: otherId),
            ),
            Filter.and(
              Filter('fromUserId', isEqualTo: otherId),
              Filter('toUserId', isEqualTo: widget.currentUserId),
            ),
          ),
        )
        .orderBy('timestamp', descending: false);

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());
              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final isMe = data['fromUserId'] == widget.currentUserId;
                  final alignment =
                      isMe ? Alignment.centerRight : Alignment.centerLeft;
                  final color = isMe ? Colors.blue[100] : Colors.grey[300];
                  final Timestamp? ts = data['timestamp'];
                  return Align(
                    alignment: alignment,
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(data['content'] ?? ''),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTimestamp(ts),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool inThread = _threadUserId != null;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (inThread) {
              setState(() {
                _threadUserId = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          inThread ? 'To: ${_otherUsername ?? ''}' : 'Messages',
        ),
      ),
      body: inThread ? _buildThread() : _buildInbox(),
      floatingActionButton: inThread
          ? null
          : FloatingActionButton(
              onPressed: _startNewMessage,
              child: const Icon(Icons.add),
            ),
    );
  }
}
