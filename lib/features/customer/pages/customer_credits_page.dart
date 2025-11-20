import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';
import 'dart:async';
import '../../../core/database/database_helper.dart';

class CustomerCreditsPage extends StatelessWidget {
  const CustomerCreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<DataStore>(
      builder: (context, dataStore, child) {
        final user = dataStore.state.currentUser;
        if (user == null) return const SizedBox.shrink();

        final allCredits = List<CreditEntry>.from(dataStore.getAllStoreCreditsForCustomer(user.id))
          ..sort((a, b) => b.date.compareTo(a.date));

        return Scaffold(
          backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
          body: RefreshIndicator(
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
                  Text(
                    'Your Credits',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey.shade100 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'View all your credit transactions',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (allCredits.isEmpty)
                    _buildEmptyState(isDark)
                  else
                    ...allCredits.map((credit) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildCreditCard(credit, isDark),
                    )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.credit_card_off,
                size: 64,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No Credits Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You don\'t have any credits yet.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditCard(CreditEntry credit, bool isDark) {
    final status = credit.balance <= 0 ? 'Paid' : 'Unpaid';
    final statusColor = credit.balance <= 0 ? Colors.green : Colors.red;

    Widget storeNameWidget = Text(
      'Unknown Store', 
      style: TextStyle(
        fontSize: 12, 
        color: isDark ? Colors.grey.shade400 : Colors.grey
      ),
    );
    if (credit.storeId != null && credit.storeId!.isNotEmpty) {
      Future<String> getStoreName(String storeId) async {
        final ds = DataStore.instance;
        // Check if it's the current user (store owner viewing their own store)
        if (ds.state.currentUser != null && ds.state.currentUser!.id == storeId) {
          return ds.state.currentUser!.storeName;
        }
        // Query database for the store owner by ID
        final db = DatabaseHelper();
        final user = await db.getUserById(storeId);
        if (user != null) return user.storeName;
        return 'Unknown Store';
      }
      storeNameWidget = FutureBuilder<String>(
        future: getStoreName(credit.storeId!),
        builder: (context, snapshot) {
          final storeName = snapshot.hasData && snapshot.data != null 
              ? snapshot.data! 
              : 'Unknown Store';
          return Text(
            'Store: $storeName',
            style: TextStyle(
              fontSize: 12, 
              color: isDark ? Colors.grey.shade400 : Colors.grey
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          );
        }
      );
    }

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
          color: statusColor.withOpacity(isDark ? 0.4 : 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  credit.item,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade100 : Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          storeNameWidget,
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount (Qty: ${credit.quantity} ${credit.unit ?? 'pcs'} × ₱${credit.effectiveUnitPrice.toStringAsFixed(2)})',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '₱${credit.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey.shade100 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '₱${credit.balance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (credit.dueDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  'Due: ${_formatDate(credit.dueDate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                if (credit.isOverdue) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'OVERDUE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else if (credit.dueSoon) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'DUE SOON',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}


