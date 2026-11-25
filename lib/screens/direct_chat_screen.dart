import 'package:flutter/material.dart';

import '../services/direct_chat_service.dart';
import '../theme.dart';

/// Temporary shell; Task 5 replaces the body with the live conversation.
class DirectChatScreen extends StatelessWidget {
  const DirectChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.client,
  });

  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final DirectChatClient? client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(peerName)),
      body: const Center(child: Text('Opening conversation…')),
    );
  }
}
