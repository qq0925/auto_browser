import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: 10,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) => ListTile(
                leading: const Icon(Icons.bookmark_border),
                title: Text('Bookmark ${index + 1}'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Text(
            'Bookmarks',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}