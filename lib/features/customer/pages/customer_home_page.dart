import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<DataStore>(
      builder: (context, dataStore, child) {
        final user = dataStore.state.currentUser;
        if (user == null) return const SizedBox.shrink();

        final totalBalance = dataStore.getCustomerTotalBalance(user.id);
        final overdueCredits = dataStore.getCustomerOverdueCredits(user.id);
        final dueSoonCredits = dataStore.getCustomerDueSoonCredits(user.id);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.blue.shade900.withOpacity(0.3),
                      Colors.grey.shade900,
                    ]
                  : [
                      Colors.blue.shade50,
                      Colors.white,
                    ],
            ),
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              try {
                await dataStore.refreshData();
                await dataStore.syncNow();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Data updated successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error refreshing data: $e')),
                  );
                }
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeHeader(user, isDark),
                  const SizedBox(height: 24),
                  _buildQuickStatsCards(totalBalance, overdueCredits, dueSoonCredits, isDark),
                  const SizedBox(height: 24),
                  _buildRecentActivitySection(dataStore, user.id, isDark),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader(User user, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(
              Icons.person,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${user.username}!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customer Account',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsCards(double totalBalance, List<CreditEntry> overdueCredits, List<CreditEntry> dueSoonCredits, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade100 : Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Balance',
                '₱${totalBalance.toStringAsFixed(2)}',
                Icons.account_balance_wallet,
                totalBalance > 0 ? Colors.red.shade400 : Colors.green.shade400,
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Overdue',
                overdueCredits.length.toString(),
                Icons.warning,
                Colors.red.shade400,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Due Soon',
                dueSoonCredits.length.toString(),
                Icons.schedule,
                Colors.orange.shade400,
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Status',
                totalBalance > 0 ? 'Outstanding' : 'All Clear',
                Icons.check_circle,
                totalBalance > 0 ? Colors.orange.shade400 : Colors.green.shade400,
                isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark) {
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
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection(DataStore dataStore, String userId, bool isDark) {
    final recentPayments = dataStore.getCustomerPayments(userId);
    final recentCredits = dataStore.getAllStoreCreditsForCustomer(userId);

    // Create a combined list
    final List<_ActivityEvent> events = [];
    events.addAll(recentPayments.map((p) => _ActivityEvent.payment(p)));
    events.addAll(recentCredits.map((c) => _ActivityEvent.credit(c)));

    // Sort by date descending
    events.sort((a, b) => b.date.compareTo(a.date));
    final topEvents = events.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade100 : Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        if (topEvents.isNotEmpty)
          ...topEvents.map((ev) {
            if (ev.payment != null) {
              final p = ev.payment!;
              return _buildActivityItem(
                'Payment Received',
                '₱${p.amount.toStringAsFixed(2)}',
                _formatDate(p.date),
                Icons.payment,
                Colors.blue,
                isDark,
              );
            } else if (ev.credit != null) {
              final c = ev.credit!;
              return _buildActivityItem(
                'Credit Added',
                c.item,
                _formatDate(c.date),
                Icons.add_circle,
                Colors.blue,
                isDark,
              );
            } else {
              return const SizedBox.shrink();
            }
          }),
        if (topEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'No recent activity',
                style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActivityItem(String title, String subtitle, String date, IconData icon, Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade100 : Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Text(
            date,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ActivityEvent {
  final Payment? payment;
  final CreditEntry? credit;
  final DateTime date;
  _ActivityEvent.payment(Payment p)
      : payment = p,
        credit = null,
        date = p.date;
  _ActivityEvent.credit(CreditEntry c)
      : payment = null,
        credit = c,
        date = c.date;
}


