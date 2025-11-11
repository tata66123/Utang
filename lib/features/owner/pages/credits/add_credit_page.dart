import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/data_store.dart';

class AddCreditPage extends StatefulWidget {
  final Customer? customer;
  final bool hideAppBar;
  final VoidCallback? onBackPressed;
  
  const AddCreditPage({super.key, this.customer, this.hideAppBar = false, this.onBackPressed});

  @override
  State<AddCreditPage> createState() => _AddCreditPageState();
}

class _AddCreditPageState extends State<AddCreditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _customerSearchController = TextEditingController();
  Customer? _selectedCustomer; // Track selected customer from dropdown
  DateTime _selectedDate = DateTime.now();
  DateTime? _dueDate;
  bool _isLoadingCustomers = true;
  
  // List to store multiple items
  final List<Map<String, dynamic>> _items = [
    {'item': '', 'amount': ''}
  ];
  
  final List<TextEditingController> _itemControllers = [TextEditingController()];
  final List<TextEditingController> _amountControllers = [TextEditingController()];

  DataStore get _store => DataStore.instance;

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) {
      _selectedCustomer = widget.customer;
      _customerSearchController.text = widget.customer!.name;
    }
    // Refresh data from Firebase on page load
    _refreshCustomers();
  }

  Future<void> _refreshCustomers() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCustomers = true;
    });
    
    try {
      print('Starting customer refresh...');
      
      // First sync from Firebase to SQLite
      await _store.syncNow();
      print('Sync completed. Syncing from Firebase to SQLite...');
      
      // Then refresh state from SQLite (which now has Firebase data)
      await _store.refreshData();
      print('Refresh data completed. Customers in state: ${_store.state.customers.length}');
      
      // Force a rebuild to show updated customers
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Silently fail - data will be loaded from local cache
      print('Error refreshing customers: $e');
      print('Stack trace: ${StackTrace.current}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCustomers = false;
        });
      }
    }
  }

  void _resetForm({bool clearCustomer = true}) {
    if (!mounted) return;
    setState(() {
      if (clearCustomer && widget.customer == null) {
        _selectedCustomer = null;
        _customerSearchController.clear();
      }

      // Reinitialize lists to a single empty row without disposing during this frame
      _items
        ..clear()
        ..add({'item': '', 'amount': ''});

      // Keep references new to avoid accessing disposed controllers in the same frame
      _itemControllers
        ..clear()
        ..add(TextEditingController());
      _amountControllers
        ..clear()
        ..add(TextEditingController());

      _selectedDate = DateTime.now();
      _dueDate = null;
      _formKey.currentState?.reset();
    });
  }

  void _addItem() {
    setState(() {
      _items.add({'item': '', 'amount': ''});
      _itemControllers.add(TextEditingController());
      _amountControllers.add(TextEditingController());
    });
  }

  void _removeItem(int index) {
    if (_items.length > 1) {
      final itemCtrl = _itemControllers[index];
      final amtCtrl = _amountControllers[index];
      setState(() {
        _items.removeAt(index);
        _itemControllers.removeAt(index);
        _amountControllers.removeAt(index);
      });
      // Defer disposal to next frame to avoid use-after-dispose during rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try { itemCtrl.dispose(); } catch (_) {}
        try { amtCtrl.dispose(); } catch (_) {}
      });
    }
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: now, // Prevent future dates
    );
    if (picked != null && mounted) {
      // Validate: cannot select future dates
      if (picked.isAfter(now)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot select future dates for credit entry')),
          );
        }
        return;
      }
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickDueDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: _selectedDate, // Due date should be after credit date
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null && mounted) {
      // Validate: due date should be after credit date
      if (picked.isBefore(_selectedDate)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Due date must be after credit date')),
          );
        }
        return;
      }
      setState(() {
        _dueDate = picked;
      });
    }
  }

  void _addCredit() async {
    if (_formKey.currentState!.validate()) {
      try {
        Customer customer;
        
        if (widget.customer != null) {
          // Customer is pre-selected (coming from customers page)
          customer = widget.customer!;
        } else if (_selectedCustomer != null) {
          // Customer selected from autocomplete
          customer = _selectedCustomer!;
        } else {
          // Try to find customer by typed name
          final customerName = _customerSearchController.text.trim();
          
          if (customerName.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select or type a customer name'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return;
          }

          // Check if customer exists
          final exists = await _store.customerExists(customerName);
          if (!exists) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Customer "$customerName" does not exist. Please register the customer first.'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }

          final resolved = await _store.getCustomerByName(customerName);
          if (resolved == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not resolve customer "$customerName". Please try again.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
          customer = resolved;
        }
        
        // Add each item as a separate credit (or update if exists)
        for (int i = 0; i < _items.length; i++) {
          final itemText = _itemControllers[i].text.trim();
          final amountText = _amountControllers[i].text.trim();
          
          if (itemText.isNotEmpty && amountText.isNotEmpty) {
            final double amount = double.parse(amountText);
            
            // Validate date is not in the future
            final now = DateTime.now();
            if (_selectedDate.isAfter(now)) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Credit date cannot be in the future')),
                );
              }
              return;
            }
            
            // Check credit limit before adding
            try {
              await _store.addOrUpdateCredit(
                customerId: customer.id,
                item: itemText,
                amount: amount,
                date: _selectedDate,
                dueDate: _dueDate,
              );
            } catch (e) {
              // Handle credit limit exceeded error
              if (e.toString().contains('Credit limit exceeded')) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
                return;
              }
              // Handle customer not found error
              if (e.toString().contains('Customer not found')) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: Customer not found. Please check the customer name.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
              rethrow;
            }
          }
        }

        // Refresh data to ensure UI shows latest information
        await _store.refreshData();

        // Sync the customer in memory list if missing
        final cust = await _store.getCustomerById(customer.id);
        if (cust != null) {
          _store.addCustomerToMemory(cust);
        }

        if (mounted) {
          _resetForm(clearCustomer: widget.customer == null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Credits added/updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding credits: $e')),
          );
        }
      }
    }
  }


  @override
  void dispose() {
    for (final controller in _itemControllers) {
      controller.dispose();
    }
    for (final controller in _amountControllers) {
      controller.dispose();
    }
    _customerSearchController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _limitRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        title: Text(widget.customer != null 
            ? 'Add Credit - ${widget.customer!.name}' 
            : 'Add New Credit'),
        backgroundColor: Colors.blue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _resetForm(clearCustomer: widget.customer == null);
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
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Customer Information (only show if no customer is pre-selected)
              if (widget.customer == null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Customer Information',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: _isLoadingCustomers
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh),
                              onPressed: _isLoadingCustomers ? null : _refreshCustomers,
                              tooltip: 'Refresh customers from Firebase',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Customer Name - Searchable Autocomplete
                        Consumer<DataStore>(
                          builder: (context, store, child) {
                            // Get all customers for current store owner
                            final storeOwnerId = store.state.currentUser?.id;
                            final allCustomers = store.state.customers;
                            
                            // Debug: Print customer info
                            print('Store Owner ID: $storeOwnerId');
                            print('Total customers in state: ${allCustomers.length}');
                            for (final c in allCustomers) {
                              print('Customer: ${c.name}, ID: ${c.id}, storeId: ${c.storeId}');
                            }
                            
                            // Filter customers: show all if storeId is null/empty, otherwise filter by storeId
                            var customers = storeOwnerId != null
                                ? allCustomers.where((c) => 
                                    c.storeId == null || 
                                    c.storeId == '' || 
                                    c.storeId == storeOwnerId
                                  ).toList()
                                : allCustomers;
                            
                            // If filtering by storeId returns no results, show all customers as fallback
                            if (customers.isEmpty && storeOwnerId != null && allCustomers.isNotEmpty) {
                              print('No customers found with storeId=$storeOwnerId, showing all customers as fallback');
                              customers = allCustomers;
                            }
                            
                            print('Filtered customers count: ${customers.length}');
                            
                            // Show loading or empty message
                            if (_isLoadingCustomers) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            
                            if (customers.isEmpty) {
                              return Column(
                                children: [
                                  TextFormField(
                                    controller: _customerSearchController,
                                    decoration: InputDecoration(
                                      labelText: 'Customer Name',
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.person),
                                      hintText: 'Type customer name',
                                      helperText: 'No customers found. Type a name to search or register a customer first.',
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Please enter customer name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No customers found. Make sure you have customers registered in Firebase.',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              );
                            }
                            
                            return Autocomplete<Customer>(
                              displayStringForOption: (Customer customer) => customer.name,
                              initialValue: _selectedCustomer != null 
                                  ? TextEditingValue(text: _selectedCustomer!.name)
                                  : null,
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                // If no input, return all customers
                                if (textEditingValue.text.isEmpty) {
                                  return customers;
                                }
                                
                                // Filter customers by name (case-insensitive)
                                final query = textEditingValue.text.toLowerCase();
                                return customers.where((customer) {
                                  return customer.name.toLowerCase().contains(query);
                                }).toList();
                              },
                              onSelected: (Customer customer) {
                                setState(() {
                                  _selectedCustomer = customer;
                                  _customerSearchController.text = customer.name;
                                });
                              },
                              fieldViewBuilder: (
                                BuildContext context,
                                TextEditingController textEditingController,
                                FocusNode focusNode,
                                VoidCallback onFieldSubmitted,
                              ) {
                                // Sync autocomplete controller with our main controller
                                if (textEditingController.text != _customerSearchController.text) {
                                  textEditingController.text = _customerSearchController.text;
                                }
                                
                                // Listen to changes
                                textEditingController.addListener(() {
                                  if (_customerSearchController.text != textEditingController.text) {
                                    _customerSearchController.text = textEditingController.text;
                                    // Clear selection if user types manually
                                    if (_selectedCustomer != null && 
                                        _selectedCustomer!.name != textEditingController.text) {
                                      if (mounted) {
                                        setState(() {
                                          _selectedCustomer = null;
                                        });
                                      }
                                    }
                                  }
                                });
                                
                                return TextFormField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    labelText: 'Customer Name',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.person),
                                    suffixIcon: _selectedCustomer != null
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              setState(() {
                                                _selectedCustomer = null;
                                                textEditingController.clear();
                                                _customerSearchController.clear();
                                              });
                                            },
                                            tooltip: 'Clear selection',
                                          )
                                        : null,
                                    hintText: 'Type to search or select from list',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter or select customer name';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (String value) {
                                    onFieldSubmitted();
                                  },
                                );
                              },
                              optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Customer> onSelected, Iterable<Customer> options) {
                                if (options.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'No customers found. Register the customer first.',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                }
                                
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 4.0,
                                    borderRadius: BorderRadius.circular(8),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxHeight: 200),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (BuildContext context, int index) {
                                          final Customer customer = options.elementAt(index);
                                          final balance = store.totalOutstandingForCustomer(customer.id);
                                          
                                          return InkWell(
                                            onTap: () => onSelected(customer),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12.0),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.person, size: 20),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          customer.name,
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        if (balance > 0) ...[
                                                          const SizedBox(height: 4),
                                                          Text(
                                                            'Balance: ₱${balance.toStringAsFixed(2)}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey.shade600,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  if (customer.creditLimit != null) ...[
                                                    const SizedBox(width: 8),
                                                    Icon(
                                                      Icons.account_balance_wallet,
                                                      size: 16,
                                                      color: Colors.blue.shade300,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Credit Limit Info (if customer has a credit limit)
              Builder(
                builder: (context) {
                  Customer? currentCustomer;
                  if (widget.customer != null) {
                    currentCustomer = widget.customer;
                  } else if (_selectedCustomer != null) {
                    currentCustomer = _selectedCustomer;
                  }

                  if (currentCustomer == null || currentCustomer.creditLimit == null) {
                    return const SizedBox.shrink();
                  }

                  final limit = currentCustomer.creditLimit!;
                  final outstanding = _store.totalOutstandingForCustomer(currentCustomer.id);
                  final remaining = (limit - outstanding).clamp(0, double.infinity);
                  final overLimit = remaining <= 0;

                  return Card(
                    color: overLimit ? Colors.red.shade50 : Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                overLimit ? Icons.warning_amber_rounded : Icons.info_outline,
                                color: overLimit ? Colors.red : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Credit Limit',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: overLimit ? Colors.red : Colors.blue,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _limitRow('Limit', '₱${limit.toStringAsFixed(2)}'),
                          _limitRow('Outstanding', '₱${outstanding.toStringAsFixed(2)}'),
                          _limitRow('Remaining', '₱${remaining.toStringAsFixed(2)}', valueColor: overLimit ? Colors.red : Colors.green),
                          if (overLimit) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Customer has reached the credit limit. New credits may be blocked.',
                              style: const TextStyle(fontSize: 12, color: Colors.red),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Credit Details Form
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Credit Details',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            onPressed: _addItem,
                            icon: const Icon(Icons.add_circle, color: Colors.blue),
                            tooltip: 'Add Item',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Dynamic Items List
                      ...List.generate(_items.length, (index) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _itemControllers[index],
                                    decoration: InputDecoration(
                                      labelText: 'Item ${index + 1}',
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.description),
                                    ),
                                    maxLines: 1,
                                    textInputAction: TextInputAction.next,
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Please enter item description';
                                      }
                                      // Item name cannot start with a number
                                      final trimmedValue = value.trim();
                                      if (trimmedValue.isNotEmpty && RegExp(r'^[0-9]').hasMatch(trimmedValue)) {
                                        return 'Item name cannot start with a number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _amountControllers[index],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Amount',
                                      border: OutlineInputBorder(),
                                      prefixText: '₱ ',
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Enter amount';
                                      }
                                      final double? amount = double.tryParse(value);
                                      if (amount == null) {
                                        return 'Invalid amount';
                                      }
                                      if (amount <= 0) {
                                        return 'Amount must be > 0';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                if (_items.length > 1)
                                  IconButton(
                                    onPressed: () => _removeItem(index),
                                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                                    tooltip: 'Remove Item',
                                  ),
                              ],
                            ),
                            if (index < _items.length - 1) const SizedBox(height: 12),
                          ],
                        );
                      }),

                      const SizedBox(height: 16),

                      // Credit Date
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Credit Date: ${_formatDate(_selectedDate)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: _pickDate,
                            child: const Text('Change Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Due Date
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Due Date: ${_dueDate == null ? 'None' : _formatDate(_dueDate!)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: _pickDueDate,
                            child: const Text('Set Due Date'),
                          ),
                          if (_dueDate != null)
                            TextButton(
                              onPressed: () => setState(() => _dueDate = null),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _addCredit,
                          child: const Text('Add Credits'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Recent Credits for Customer
              if (widget.customer != null || _selectedCustomer != null) ...[
                const Text(
                  'Recent Credits for This Customer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: _buildRecentCredits(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentCredits() {
    Customer? customer;
    
    if (widget.customer != null) {
      // Customer is pre-selected (coming from customers page)
      customer = widget.customer;
    } else if (_selectedCustomer != null) {
      // Customer selected from dropdown
      customer = _selectedCustomer;
    } else {
      return const SizedBox.shrink();
    }
    
    if (customer == null) {
      return const Center(
        child: Text('No customer selected'),
      );
    }

    final recentCredits = _store.state.credits
        .where((credit) => credit.customerId == customer!.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (recentCredits.isEmpty) {
      return const Center(
        child: Text('No credits for this customer yet'),
      );
    }

    return ListView.builder(
      itemCount: recentCredits.length,
      itemBuilder: (context, index) {
        final credit = recentCredits[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: credit.balance > 0 ? Colors.orange.shade100 : Colors.green.shade100,
              child: Icon(
                credit.balance > 0 ? Icons.pending : Icons.check,
                color: credit.balance > 0 ? Colors.orange : Colors.green,
              ),
            ),
            title: Text(
              credit.item,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Amount: ₱${credit.amount.toStringAsFixed(2)}',
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Balance: ₱${credit.balance.toStringAsFixed(2)}',
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Date: ${_formatDate(credit.date)}',
                  overflow: TextOverflow.ellipsis,
                ),
                if (credit.dueDate != null)
                  Text(
                    'Due: ${_formatDate(credit.dueDate!)}',
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
