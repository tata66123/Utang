import 'package:flutter/material.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _query = '';

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final DataStore store = DataStore.instance;
    final List<Customer> allCustomers = store.state.customers;
    // Filter by customer name only
    final List<Customer> filteredCustomers = allCustomers.where((c) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return c.name.toLowerCase().contains(q);
    }).toList();

    // Sort customers: those with any outstanding balance first, then by name
    filteredCustomers.sort((a, b) {
      final aOutstanding = store.getCustomerTotalBalance(a.id);
      final bOutstanding = store.getCustomerTotalBalance(b.id);
      if ((aOutstanding > 0) != (bOutstanding > 0)) {
        return (bOutstanding > 0) ? 1 : -1; // unpaid first
      }
      // If both same status, sort by name
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History'), backgroundColor: Colors.blue),
      body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by customer name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (String v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: filteredCustomers.isEmpty
                  ? const Center(child: Text('No customers found'))
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filteredCustomers.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Customer customer = filteredCustomers[index];
                        final List<CreditEntry> credits = store.getCustomerCredits(customer.id)
                          ..sort((a, b) {
                            final aUnpaid = a.balance > 0;
                            final bUnpaid = b.balance > 0;
                            if (aUnpaid != bUnpaid) return aUnpaid ? -1 : 1; // unpaid first
                            return b.date.compareTo(a.date); // recent first
                          });
                        final double totalPaid = credits.fold(0.0, (sum, c) => sum + c.paidAmount);
                        final double totalOutstanding = credits.fold(0.0, (sum, c) => sum + c.balance);

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text(
                              customer.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Paid: ₱${totalPaid.toStringAsFixed(2)}  •  Outstanding: ₱${totalOutstanding.toStringAsFixed(2)}',
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                              ),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () => _openCustomerTransactionsDialog(context, customer, credits),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
    );
  }

  Widget _buildCreditTile(CreditEntry e) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
      child: Card(
        child: ExpansionTile(
          leading: Icon(
            e.balance > 0 ? Icons.pending : Icons.check_circle,
            color: e.balance > 0 ? Colors.orange : Colors.green,
          ),
          title: Text(e.item),
          subtitle: Text(
            'Amount: ₱${e.amount.toStringAsFixed(2)}  •  Paid: ₱${e.paidAmount.toStringAsFixed(2)}  •  Bal: ₱${e.balance.toStringAsFixed(2)}\nDate: ${_formatDate(e.date)}${e.dueDate != null ? '  •  Due: ${_formatDate(e.dueDate!)}' : ''}',
          ),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Payments:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if (e.payments.isEmpty)
              const ListTile(title: Text('No payments yet'))
            else
              ...e.payments.map((Payment p) => ListTile(
                    leading: const Icon(Icons.payment, color: Colors.green),
                    title: Text('₱${p.amount.toStringAsFixed(2)}'),
                    subtitle: Text('Date: ${_formatDate(p.date)}'),
                  )),
          ],
        ),
      ),
    );
  }

  void _openCustomerTransactionsDialog(BuildContext context, Customer customer, List<CreditEntry> credits) {
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
                            Text('Transactions (${credits.length})', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
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
                  child: credits.isEmpty
                      ? const Center(child: Text('No transactions'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: credits.length,
                          itemBuilder: (context, index) => _buildCreditTile(credits[index]),
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


