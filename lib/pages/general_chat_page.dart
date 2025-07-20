import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Simple chat page for general messaging threads.
class GeneralChatPage extends StatefulWidget {
  final String threadId;
  final String currentUserId;
  final String otherUserId;
  final String otherUsername;
  final String currentUsername;
  final String currentUserRole; // admin/customer/mechanic

  const GeneralChatPage({
    super.key,
    required this.threadId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUsername,
    required this.currentUsername,
    required this.currentUserRole,
  });

  @override
  State<GeneralChatPage> createState() => _GeneralChatPageState();
}

class _GeneralChatPageState extends State<GeneralChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('MM/dd h:mm a').format(dt);
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('messages_general')
        .doc(widget.threadId)
        .collection('messages')
        .add({
      'senderId': widget.currentUserId,
      'senderRole': widget.currentUserRole,
      'messageText': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('messages_general')
        .doc(widget.threadId)
        .update({
      'lastMessage': text,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (widget.currentUserRole != 'admin') {
      await FirebaseFirestore.instance.collection('notifications_admin').add({
        'threadId': widget.threadId,
        'userId': widget.currentUserId,
        'username': widget.currentUsername,
        'messagePreview': text.length > 50 ? text.substring(0, 50) : text,
        'unread': true,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

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

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('messages_general')
        .doc(widget.threadId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: Text('Chat with ${widget.otherUsername}')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
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
                            child: Text(data['messageText'] ?? ''),
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
      ),
    );
  }
}
