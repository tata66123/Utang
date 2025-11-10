import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class OutstandingDetailsPage extends StatelessWidget {
  const OutstandingDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, store, child) {
        final entries = store.state.customers
            .map((c) => _OutstandingEntry(
                  customer: c,
                  outstanding: store.totalOutstandingForCustomer(c.id),
                  items: store
                      .getCustomerCredits(c.id)
                      .where((credit) => credit.balance > 0)
                      .toList(),
                ))
            .where((e) => e.outstanding > 0)
            .toList()
          ..sort((a, b) => b.outstanding.compareTo(a.outstanding));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Total Outstanding'),
          ),
          body: entries.isEmpty
              ? const Center(child: Text('No outstanding balances'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading:
                            const Icon(Icons.person, color: Colors.blue),
                        title: Text(
                          entry.customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Outstanding: ₱${entry.outstanding.toStringAsFixed(2)}',
                        ),
                        children: entry.items.isEmpty
                            ? [const ListTile(title: Text('No outstanding items'))]
                            : entry.items
                                .map(
                                  (credit) => ListTile(
                                    dense: true,
                                    title: Text(credit.item),
                                    subtitle: Text(
                                      'Balance: ₱${credit.balance.toStringAsFixed(2)}',
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

class _OutstandingEntry {
  _OutstandingEntry({
    required this.customer,
    required this.outstanding,
    required this.items,
  });
  final Customer customer;
  final double outstanding;
  final List<CreditEntry> items;
}


