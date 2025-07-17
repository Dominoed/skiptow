import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MessagesPage extends StatefulWidget {
  final String currentUserId;
  final String otherUserId;
  final String? initialMessage;

  const MessagesPage({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    this.initialMessage,
  });

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _conversationId;
  String? _otherUsername;

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null) {
      _controller.text = widget.initialMessage!;
    }
    _initConversation();
  }

  Future<void> _initConversation() async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).get();
    final otherDoc =
        await FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).get();
    final username = otherDoc.data()?['username'];
    final userRole = userDoc.data()?['role'];
    final otherRole = otherDoc.data()?['role'];

    String convId;
    if (userRole == 'customer' && otherRole == 'mechanic') {
      convId = '${widget.currentUserId}_${widget.otherUserId}';
    } else if (userRole == 'mechanic' && otherRole == 'customer') {
      convId = '${widget.otherUserId}_${widget.currentUserId}';
    } else {
      final ids = [widget.currentUserId, widget.otherUserId]..sort();
      convId = '${ids[0]}_${ids[1]}';
    }

    setState(() {
      _conversationId = convId;
      _otherUsername = username;
    });

    await _markMessagesAsRead();
  }

  Future<void> _markMessagesAsRead() async {
    if (_conversationId == null) return;
    final query = await FirebaseFirestore.instance
        .collection('messages')
        .doc(_conversationId)
        .collection('threads')
        .where('recipientId', isEqualTo: widget.currentUserId)
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in query.docs) {
      await doc.reference.update({'isRead': true});
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _conversationId == null) return;

    final threads = FirebaseFirestore.instance
        .collection('messages')
        .doc(_conversationId)
        .collection('threads');

    await threads.add({
      'senderId': widget.currentUserId,
      'recipientId': widget.otherUserId,
      'text': text,
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

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('h:mm a on MM/dd/yyyy').format(dt);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_conversationId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('To: ${_otherUsername ?? ''}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .doc(_conversationId)
                  .collection('threads')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
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
                    final isMe = data['senderId'] == widget.currentUserId;
                    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
                    final color = isMe ? Colors.blue[100] : Colors.grey[300];
                    final Timestamp? ts = data['timestamp'];
                    final formatted = _formatTimestamp(ts);
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
                            child: Text(data['text'] ?? ''),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatted,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
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
      ),
    );
  }
}
