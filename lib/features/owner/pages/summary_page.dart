import 'package:flutter/material.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DataStore store = DataStore.instance;
    final List<Customer> customers = store.state.customers
        .where((c) => store.totalOutstandingForCustomer(c.id) > 0)
        .toList();
    final double total = store.totalOutstanding();
    return Scaffold(
      appBar: AppBar(title: const Text('Outstanding Summary')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Total Outstanding (Store)'),
              trailing: Text(total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Per Customer', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (customers.isEmpty)
            const Center(child: Text('No outstanding balances'))
          else
            ...customers.map((Customer c) {
              final double amt = store.totalOutstandingForCustomer(c.id);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(c.name),
                  subtitle: Text('Outstanding: ₱${store.totalOutstandingForCustomer(c.id).toStringAsFixed(2)}'),
                  trailing: Text(amt.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            }),
        ],
      ),
    );
  }
}


