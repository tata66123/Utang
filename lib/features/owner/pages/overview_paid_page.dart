import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class PaidDetailsPage extends StatelessWidget {
  const PaidDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, store, child) {
        // Group payments by customer with per-customer total
        final Map<String, _CustomerPaidGroup> grouped = {};
        for (final credit in store.state.credits) {
          for (final payment in credit.payments) {
            final customer = store.state.customers.firstWhere(
              (c) => c.id == credit.customerId,
              orElse: () => Customer(id: '', name: 'Unknown'),
            );
            final key = customer.id;
            grouped.putIfAbsent(
              key,
              () => _CustomerPaidGroup(customer: customer, items: []),
            );
            grouped[key]!.items.add(
              _PaidItem(
                itemName: credit.item,
                amount: payment.amount,
                date: payment.date,
              ),
            );
          }
        }

        final List<_CustomerPaidGroup> groups = grouped.values.toList();
        for (final g in groups) {
          g.items.sort((a, b) => b.date.compareTo(a.date));
          g.totalPaid = g.items.fold(0.0, (s, i) => s + i.amount);
        }
        groups.sort((a, b) => b.totalPaid.compareTo(a.totalPaid));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Total Amount Paid'),
          ),
          body: groups.isEmpty
              ? const Center(child: Text('No payments recorded yet'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: const Icon(Icons.person, color: Colors.green),
                        title: Text(
                          group.customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Total Paid: ₱${group.totalPaid.toStringAsFixed(2)}',
                        ),
                        children: group.items.isEmpty
                            ? [const ListTile(title: Text('No payments'))]
                            : group.items
                                .map(
                                  (i) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.check_circle,
                                        color: Colors.green),
                                    title: Text(
                                      i.itemName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    trailing: Text(
                                      '₱${i.amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _CustomerPaidGroup {
  _CustomerPaidGroup({required this.customer, required this.items})
      : totalPaid = 0;
  final Customer customer;
  final List<_PaidItem> items;
  double totalPaid;
}

class _PaidItem {
  _PaidItem({required this.itemName, required this.amount, required this.date});
  final String itemName;
  final double amount;
  final DateTime date;
}


