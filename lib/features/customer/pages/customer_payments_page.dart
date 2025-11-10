import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';
import 'dart:async';
import '../../../core/database/database_helper.dart';

class CustomerPaymentsPage extends StatelessWidget {
  const CustomerPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, dataStore, child) {
        final user = dataStore.state.currentUser;
        if (user == null) return const SizedBox.shrink();

        final payments = List<Payment>.from(dataStore.getCustomerPayments(user.id))
          ..sort((a, b) => b.date.compareTo(a.date));

        return Scaffold(
          backgroundColor: Colors.white,
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
                  const Text(
                    'Payment History',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track all your payment transactions',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (payments.isEmpty)
                    _buildEmptyState()
                  else
                    ...payments.map((payment) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildPaymentCard(payment),
                    )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.payment,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No Payments Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You haven\'t made any payments yet.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(Payment payment) {
    // Try to find the owning credit and show its store name
    final dataStore = DataStore.instance;
    CreditEntry? credit;
    try {
      credit = dataStore.state.credits.firstWhere(
        (c) => c.payments.any((p) => p.id == payment.id),
      );
    } catch (_) {
      credit = null;
    }

    Widget storeNameWidget = const Text('Unknown Store', style: TextStyle(fontSize: 12, color: Colors.grey));
    if (credit != null && credit.storeId != null && credit.storeId!.isNotEmpty) {
      Future<String> getStoreName(String storeId) async {
        // Check if it's the current user (store owner viewing their own store)
        if (dataStore.state.currentUser != null && dataStore.state.currentUser!.id == storeId) {
          return dataStore.state.currentUser!.storeName;
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
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          );
        }
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.green.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.payment,
              color: Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Received',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${payment.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                storeNameWidget,
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green.shade400,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(payment.date),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}


