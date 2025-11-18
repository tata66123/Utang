import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/models.dart';
import '../../../core/services/data_store.dart';
import 'credits/add_credit_page.dart' as credit;

enum TransactionFilter { all, credits, payments }

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _expandedCustomerId;
  final TransactionFilter _selectedFilter = TransactionFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _getCustomerOutstanding(String customerId, DataStore store) {
    return store.totalOutstandingForCustomer(customerId);
  }

  double _getCustomerTotalPaid(String customerId, DataStore store) {
    return store.getCustomerCredits(customerId)
        .fold(0.0, (sum, credit) => sum + credit.paidAmount);
  }

  List<Customer> _getFilteredCustomers(List<Customer> customers, String query) {
    if (query.isEmpty) return customers;
    final lowerQuery = query.toLowerCase();
    return customers.where((customer) {
      return customer.name.toLowerCase().contains(lowerQuery) ||
          customer.id.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, store, child) {
        final List<Customer> allCustomers = store.state.customers;
        final filteredCustomers = _getFilteredCustomers(allCustomers, _searchController.text);

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Customers'),
          ),
          body: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or ID...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) => setState(() {}),
                ),
              ),

              // Customers List
              Expanded(
                child: filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'No customers yet'
                                  : 'No customers found',
                              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                            ),
                            if (_searchController.text.isEmpty)
                              Text(
                                'Add your first customer above',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = filteredCustomers[index];
                          final outstanding = _getCustomerOutstanding(customer.id, store);
                          final totalPaid = _getCustomerTotalPaid(customer.id, store);
                          final isExpanded = _expandedCustomerId == customer.id; // legacy, no longer used for UI
                          final totalBalance = outstanding;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: isExpanded ? 4 : 2,
                            child: Column(
                              children: [
                                // Customer Header
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isDark 
                                        ? Colors.blue.shade800.withOpacity(0.5)
                                        : Colors.blue.shade100,
                                    child: Text(
                                      customer.name[0].toUpperCase(),
                                      style: TextStyle(
                                        color: isDark ? Colors.blue.shade200 : Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    customer.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Outstanding: ₱${outstanding.toStringAsFixed(2)}'),
                                      Text('Total Paid: ₱${totalPaid.toStringAsFixed(2)}'),
                                      if (customer.creditLimit != null)
                                        Text(
                                          'Credit Limit: ₱${customer.creditLimit!.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: outstanding > customer.creditLimit!
                                                ? Colors.red
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => credit.AddCreditPage(customer: customer),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.add_circle, color: Colors.blue),
                                    tooltip: 'Add Credit',
                                  ),
                                  onTap: () => _openCustomerDialog(context, customer, store, totalBalance, outstanding, totalPaid),
                                ),
                                // Expanded Panel removed in favor of dialog
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsListForDialog(String customerId, DataStore store, TransactionFilter filter) {
    final credits = store.getCustomerCredits(customerId);
    final allTransactions = <Map<String, dynamic>>[];

    for (final credit in credits) {
      allTransactions.add({'type': 'credit', 'credit': credit, 'amount': credit.amount, 'date': credit.date});
      for (final payment in credit.payments) {
        allTransactions.add({'type': 'payment', 'payment': payment, 'credit': credit, 'amount': payment.amount, 'date': payment.date});
      }
    }
    allTransactions.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    if (filter == TransactionFilter.payments) {
      final payments = <Map<String, dynamic>>[];
      for (final t in allTransactions) {
        if (t['type'] == 'payment') payments.add(t);
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: payments.length,
        itemBuilder: (context, index) {
          final payment = payments[index]['payment'] as Payment;
          final credit = payments[index]['credit'] as CreditEntry;
          return _buildTransactionTile(type: 'payment', amount: payment.amount, date: payment.date, credit: credit);
        },
      );
    } else if (filter == TransactionFilter.credits) {
      final creditOnly = allTransactions.where((t) => t['type'] == 'credit').map((t) => t['credit'] as CreditEntry).toList();
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: creditOnly.length,
        itemBuilder: (context, index) {
          final credit = creditOnly[index];
          return _buildTransactionTile(type: 'credit', amount: credit.amount, date: credit.date, credit: credit);
        },
      );
    }

    // All
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: credits.length,
      itemBuilder: (context, index) {
        final credit = credits[index];
        return ExpansionTile(
          title: Text(credit.item),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Qty: ${credit.quantity} × ₱${credit.effectiveUnitPrice.toStringAsFixed(2)} = ₱${credit.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
              Text('Balance: ₱${credit.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          leading: const Icon(Icons.add_circle, color: Colors.blue),
          children: [
            if (credit.payments.isEmpty)
              const ListTile(title: Text('No payments yet'))
            else
              ...credit.payments.map((payment) => _buildTransactionTile(type: 'payment', amount: payment.amount, date: payment.date, credit: credit)),
          ],
        );
      },
    );
  }

  Widget _buildTransactionTile({
    required String type,
    required double amount,
    required DateTime date,
    required CreditEntry credit,
  }) {
    final isCredit = type == 'credit';
    return ListTile(
      dense: true,
      leading: Icon(
        isCredit ? Icons.add_circle : Icons.payment,
        color: isCredit ? Colors.blue : Colors.green,
      ),
      title: Text(
        isCredit ? credit.item : 'Payment for ${credit.item}',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isCredit ? Colors.blue : Colors.green,
            ),
          ),
          Icon(
            Icons.cloud_done,
            size: 16,
            color: Colors.grey.shade400,
          ),
        ],
      ),
    );
  }

  void _openCustomerDialog(BuildContext context, Customer customer, DataStore store, double totalBalance, double outstanding, double totalPaid) {
    showDialog(
      context: context,
      builder: (ctx) {
        TransactionFilter localFilter = _selectedFilter;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: StatefulBuilder(
              builder: (context, setLocalState) {
                final dialogIsDark = Theme.of(context).brightness == Brightness.dark;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: dialogIsDark 
                            ? Colors.blue.shade900.withOpacity(0.3)
                            : Colors.blue.shade50,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: dialogIsDark 
                                ? Colors.blue.shade800.withOpacity(0.5)
                                : Colors.blue.shade100,
                            child: Text(
                              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: dialogIsDark ? Colors.blue.shade200 : Colors.blue.shade700, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('Balance: ₱${totalBalance.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                Text('Paid: ₱${totalPaid.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
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
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Info rows
                            _buildInfoRow('Total Balance', '₱${totalBalance.toStringAsFixed(2)}'),
                            _buildInfoRow('Total Paid', '₱${totalPaid.toStringAsFixed(2)}'),
                            if (customer.creditLimit != null)
                              _buildInfoRow('Credit Limit', '₱${customer.creditLimit!.toStringAsFixed(2)}',
                                  color: outstanding > customer.creditLimit! ? Colors.red : null),
                            const SizedBox(height: 16),

                            // Filter
                            SegmentedButton<TransactionFilter>(
                              segments: const [
                                ButtonSegment(value: TransactionFilter.all, label: Text('All', style: TextStyle(fontSize: 12)), icon: Icon(Icons.list, size: 16)),
                                ButtonSegment(value: TransactionFilter.credits, label: Text('Credits', style: TextStyle(fontSize: 12)), icon: Icon(Icons.add_circle, size: 16)),
                                ButtonSegment(value: TransactionFilter.payments, label: Text('Payments', style: TextStyle(fontSize: 12)), icon: Icon(Icons.payment, size: 16)),
                              ],
                              selected: {localFilter},
                              onSelectionChanged: (Set<TransactionFilter> newSelection) {
                                setLocalState(() { localFilter = newSelection.first; });
                              },
                            ),
                            const SizedBox(height: 12),
                            Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                            const SizedBox(height: 8),
                            _buildTransactionsListForDialog(customer.id, store, localFilter),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                      ),
                    )
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
