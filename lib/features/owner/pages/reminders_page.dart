import 'package:flutter/material.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/firebase_service.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _sendReminder(BuildContext context, Customer customer, CreditEntry credit) async {
    final notificationService = NotificationService();
    final firebaseService = FirebaseService();
    
    // Initialize services
    await notificationService.initialize();
    await firebaseService.initialize();
    
    // Show in-app notification to store owner (feedback that reminder was sent)
    await notificationService.showInAppNotification(
      context: context,
      title: 'Reminder Sent',
      message: 'Reminder sent to ${customer.name} for ${credit.item}',
      type: NotificationType.success,
    );

    // Send notification to customer's phone (not store owner's phone)
    // The customer.id is the customer's user ID
    try {
      final storeName = DataStore.instance.state.currentUser?.storeName ?? 'Store';
      await firebaseService.saveNotification(
        userId: customer.id, // Send to customer's phone, not store owner's
        title: 'Payment Reminder',
        message: '${credit.item}: ₱${credit.balance.toStringAsFixed(2)} due ${_formatDate(credit.dueDate!)}',
        type: 'payment_reminder',
        data: {
          'creditId': credit.id,
          'storeId': credit.storeId,
          'storeName': storeName,
          'amount': credit.balance,
          'item': credit.item,
          'dueDate': credit.dueDate?.millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Error sending reminder notification to customer: $e');
      // Show error to store owner if notification fails
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending reminder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DataStore store = DataStore.instance;
    final List<Customer> customers = store.state.customers;
    // Group due credits by customer
    final Map<String, List<CreditEntry>> dueByCustomer = {};
    for (final credit in store.state.credits) {
      if (credit.dueDate != null && credit.balance > 0) {
        (dueByCustomer[credit.customerId] ??= []).add(credit);
      }
    }
    for (final list in dueByCustomer.values) {
      list.sort((a, b) => (a.dueDate!).compareTo(b.dueDate!));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Due Dates & Reminders')),
      body: dueByCustomer.isEmpty
          ? const Center(child: Text('No upcoming or overdue items'))
          : ListView.builder(
              itemCount: customers.length,
              itemBuilder: (BuildContext context, int index) {
                final c = customers[index];
                final dueList = dueByCustomer[c.id] ?? const <CreditEntry>[];
                if (dueList.isEmpty) {
                  return const SizedBox.shrink();
                }
                final overdueCount = dueList.where((e) => e.isOverdue).length;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: overdueCount > 0 
                          ? (isDark ? Colors.red.shade900.withOpacity(0.5) : Colors.red.shade100)
                          : (isDark ? Colors.orange.shade900.withOpacity(0.5) : Colors.orange.shade100),
                      child: Icon(
                        overdueCount > 0 ? Icons.warning : Icons.event,
                        color: overdueCount > 0 ? Colors.red : Colors.orange,
                      ),
                    ),
                    title: Text(
                      c.name, 
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey.shade100 : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      '${dueList.length} item(s) due',
                      style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _openDueDialog(context, c, dueList),
                  ),
                );
              },
            ),
    );
  }

  void _openDueDialog(BuildContext context, Customer customer, List<CreditEntry> dueList) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.blue.shade900.withOpacity(0.3)
                        : Colors.blue.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isDark 
                            ? Colors.blue.shade800.withOpacity(0.5)
                            : Colors.blue.shade100,
                        child: Text(
                          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isDark ? Colors.blue.shade200 : Colors.blue.shade700, 
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name, 
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey.shade100 : Colors.black87,
                              ),
                            ),
                            Text(
                              'Due items (${dueList.length})', 
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, 
                                fontSize: 12
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: dueList.length,
                    itemBuilder: (context, index) {
                      final e = dueList[index];
                      final overdue = e.isOverdue;
                      final soon = e.dueSoon;
                      final color = overdue ? Colors.red : (soon ? Colors.orange : Colors.green);
                      return Card(
                        child: ListTile(
                          leading: Icon(overdue ? Icons.warning : Icons.event, color: color),
                          title: Text(e.item, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Qty: ${e.quantity} ${e.unit ?? 'pcs'} × ₱${e.effectiveUnitPrice.toStringAsFixed(2)} = ₱${e.amount.toStringAsFixed(2)}  •  Balance: ₱${e.balance.toStringAsFixed(2)}  •  Due: ${_formatDate(e.dueDate!)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.notifications_active),
                            tooltip: 'Send Reminder',
                            onPressed: () => _sendReminder(context, customer, e),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}