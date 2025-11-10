import 'package:flutter/material.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';
import '../../../core/services/notification_service.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _sendReminder(BuildContext context, Customer customer, CreditEntry credit) async {
    final notificationService = NotificationService();
    
    // Show in-app notification with haptic feedback
    await notificationService.showInAppNotification(
      context: context,
      title: 'Reminder Sent',
      message: 'Reminder sent to ${customer.name} for ${credit.item}',
      type: NotificationType.success,
    );

    // Schedule a local notification as backup
    await notificationService.scheduleReminderNotification(
      title: 'Payment Reminder',
      message: '${customer.name} - ${credit.item}: ₱${credit.balance.toStringAsFixed(2)} due ${_formatDate(credit.dueDate!)}',
      scheduledDate: DateTime.now().add(const Duration(minutes: 1)),
    );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Due Dates & Reminders'), backgroundColor: Colors.blue),
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
                      backgroundColor: overdueCount > 0 ? Colors.red.shade100 : Colors.orange.shade100,
                      child: Icon(
                        overdueCount > 0 ? Icons.warning : Icons.event,
                        color: overdueCount > 0 ? Colors.red : Colors.orange,
                      ),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${dueList.length} item(s) due'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _openDueDialog(context, c, dueList),
                  ),
                );
              },
            ),
    );
  }

  void _openDueDialog(BuildContext context, Customer customer, List<CreditEntry> dueList) {
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
                    color: Colors.blue.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('Due items (${dueList.length})', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
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
                          subtitle: Text('Balance: ₱${e.balance.toStringAsFixed(2)}  •  Due: ${_formatDate(e.dueDate!)}'),
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