import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/models.dart';
import '../../../core/services/data_store.dart';
import 'enhanced_payment_dialog.dart';

class PaymentPage extends StatefulWidget {
  final bool hideAppBar;
  final VoidCallback? onBackPressed;
  
  const PaymentPage({super.key, this.hideAppBar = false, this.onBackPressed});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String? _selectedCustomerId;

  DataStore get _store => DataStore.instance;

  Map<String, double> get _customersWithBalance {
    final Map<String, double> customerBalances = {};
    for (final credit in _store.state.credits) {
      if (credit.balance > 0) {
        customerBalances[credit.customerId] = (customerBalances[credit.customerId] ?? 0) + credit.balance;
      }
    }
    return customerBalances;
  }

  String _getCustomerName(String customerId) {
    final customer = _store.state.customers.firstWhere(
      (c) => c.id == customerId,
      orElse: () => Customer(id: '', name: 'Unknown'),
    );
    return customer.name;
  }

  Customer? _getCustomer(String customerId) {
    try {
      return _store.state.customers.firstWhere((c) => c.id == customerId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openPaymentDialog(Customer customer) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EnhancedPaymentDialog(
        customer: customer,
        store: _store,
      ),
    );

    if (result == true && mounted) {
      await _store.refreshData();
      setState(() {
        _selectedCustomerId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        title: const Text('Record Payment'),
        backgroundColor: Colors.green,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.onBackPressed != null) {
              widget.onBackPressed!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
          tooltip: 'Go Back',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Payment Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Consumer<DataStore>(
                  builder: (context, store, child) {
                    final customersWithBalance = _customersWithBalance;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Record Payment',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Select Customer',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.person),
                            hintText: customersWithBalance.isEmpty
                                ? 'No customers with outstanding balance'
                                : 'Choose a customer',
                          ),
                          isExpanded: true,
                          initialValue: customersWithBalance.containsKey(_selectedCustomerId)
                              ? _selectedCustomerId
                              : null,
                          items: customersWithBalance.isEmpty
                              ? [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('No customers available'),
                                  ),
                                ]
                              : customersWithBalance.entries.map((entry) {
                                  final customerName = _getCustomerName(entry.key);
                                  return DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            customerName,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        Text(
                                          '₱${entry.value.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                          onChanged: customersWithBalance.isEmpty
                              ? null
                              : (value) => setState(() => _selectedCustomerId = value),
                        ),
                        if (_selectedCustomerId != null &&
                            customersWithBalance.containsKey(_selectedCustomerId)) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Outstanding Balance: ₱${customersWithBalance[_selectedCustomerId!]!.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (_selectedCustomerId == null)
                                ? null
                                : () {
                                    final customer = _getCustomer(_selectedCustomerId!);
                                    if (customer != null) {
                                      _openPaymentDialog(customer);
                                    }
                                  },
                            icon: const Icon(Icons.payments),
                            label: const Text('Open Payment Dialog'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Outstanding Credits List
            Consumer<DataStore>(
              builder: (context, store, child) {
                final customersWithBalance = _customersWithBalance;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Outstanding Credits',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    customersWithBalance.isEmpty
                        ? SizedBox(
                            height: 200,
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                                  SizedBox(height: 16),
                                  Text('All credits are paid!', style: TextStyle(fontSize: 18, color: Colors.green)),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: customersWithBalance.length,
                            itemBuilder: (context, index) {
                              final entry = customersWithBalance.entries.elementAt(index);
                              final customerName = _getCustomerName(entry.key);
                              final totalBalance = entry.value;
                              
                              // Check if any credits are overdue
                              final hasOverdue = store.state.credits.any(
                                (credit) => credit.customerId == entry.key && credit.isOverdue && credit.balance > 0
                              );

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: hasOverdue ? Colors.red.shade100 : Colors.blue.shade100,
                                    child: Icon(
                                      hasOverdue ? Icons.warning : Icons.person,
                                      color: hasOverdue ? Colors.red : Colors.blue,
                                    ),
                                  ),
                                  title: Text(customerName),
                                  subtitle: Text('Balance: ₱${totalBalance.toStringAsFixed(2)}'),
                                  trailing: hasOverdue
                                      ? const Icon(Icons.warning, color: Colors.red)
                                      : null,
                                  onTap: () {
                                    final customer = _getCustomer(entry.key);
                                    if (customer != null) {
                                      setState(() => _selectedCustomerId = entry.key);
                                      _openPaymentDialog(customer);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

