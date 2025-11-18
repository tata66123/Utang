import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';

class CustomerNotificationsPage extends StatelessWidget {
  const CustomerNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<DataStore>(
      builder: (context, dataStore, child) {
        final user = dataStore.state.currentUser;
        if (user == null) return const SizedBox.shrink();

        final overdueCredits = dataStore.getCustomerOverdueCredits(user.id);
        final dueSoonCredits = dataStore.getCustomerDueSoonCredits(user.id);

        return Scaffold(
          backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade100 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stay updated with your account status',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                if (overdueCredits.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _buildNotificationCard(
                      'Overdue Credits',
                      'You have ${overdueCredits.length} overdue credit(s) that need immediate attention.',
                      Icons.warning,
                      Colors.red,
                      isDark,
                    ),
                  ),
                ],
                if (dueSoonCredits.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _buildNotificationCard(
                      'Credits Due Soon',
                      'You have ${dueSoonCredits.length} credit(s) due within 3 days.',
                      Icons.schedule,
                      Colors.orange,
                      isDark,
                    ),
                  ),
                ],
                if (overdueCredits.isEmpty && dueSoonCredits.isEmpty)
                  _buildAllClearCard(isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(String title, String message, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(isDark ? 0.3 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(isDark ? 0.4 : 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade300 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllClearCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(isDark ? 0.3 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle,
            size: 64,
            color: isDark ? Colors.green.shade300 : Colors.green.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'All Caught Up!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.green.shade300 : Colors.green.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No notifications at this time. Your account is up to date.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


