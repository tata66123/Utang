import 'package:flutter/material.dart';
import '../../../core/models/models.dart';
import '../../../core/services/data_store.dart';
import '../../../core/services/connectivity_service.dart';

enum PaymentType { partial, full }

class EnhancedPaymentDialog extends StatefulWidget {
  final Customer customer;
  final DataStore store;

  const EnhancedPaymentDialog({
    super.key,
    required this.customer,
    required this.store,
  });

  @override
  State<EnhancedPaymentDialog> createState() => _EnhancedPaymentDialogState();
}

class _EnhancedPaymentDialogState extends State<EnhancedPaymentDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  PaymentType _paymentType = PaymentType.partial;
  final Map<String, TextEditingController> _partialAmountControllers = {};
  final Set<String> _selectedPartialCreditIds = <String>{};
  final Set<String> _selectedFullCreditIds = <String>{};
  DateTime _paymentDate = DateTime.now();
  bool _isProcessing = false;

  List<CreditEntry> get _customerCredits {
    return widget.store
        .getCustomerCredits(widget.customer.id)
        .where((credit) => credit.balance > 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  TextEditingController _partialControllerFor(String creditId) {
    return _partialAmountControllers.putIfAbsent(
      creditId,
      () => TextEditingController(),
    );
  }

  double _outstandingFor(String creditId) {
    final credit = _customerCredits.firstWhere(
      (c) => c.id == creditId,
      orElse: () => CreditEntry(
        id: '',
        customerId: '',
        item: '',
        amount: 0,
        date: DateTime.now(),
      ),
    );
    return credit.balance;
  }

  double get _partialTotal {
    double total = 0;
    for (final creditId in _selectedPartialCreditIds) {
      final controller = _partialAmountControllers[creditId];
      if (controller == null) continue;
      final value = double.tryParse(controller.text.trim());
      if (value != null) {
        total += value;
      }
    }
    return total;
  }

  double get _fullTotal {
    double total = 0;
    for (final creditId in _selectedFullCreditIds) {
      total += _outstandingFor(creditId);
    }
    return total;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null && mounted) {
      if (picked.isAfter(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot select future dates')),
        );
        return;
      }
      setState(() => _paymentDate = picked);
    }
  }

  void _switchPaymentType(PaymentType type) {
    if (_paymentType == type) return;
    setState(() {
      _paymentType = type;
      _selectedPartialCreditIds.clear();
      _selectedFullCreditIds.clear();
      for (final controller in _partialAmountControllers.values) {
        controller.clear();
      }
    });
  }

  void _togglePartialSelection(String creditId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedPartialCreditIds.add(creditId);
      } else {
        _selectedPartialCreditIds.remove(creditId);
        _partialAmountControllers[creditId]?.clear();
      }
    });
  }

  void _toggleFullSelection(String creditId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedFullCreditIds.add(creditId);
      } else {
        _selectedFullCreditIds.remove(creditId);
      }
    });
  }

  void _toggleSelectAllFull() {
    setState(() {
      final credits = _customerCredits;
      final allSelected = credits.every((credit) => _selectedFullCreditIds.contains(credit.id));
      
      if (allSelected) {
        // Deselect all
        _selectedFullCreditIds.clear();
      } else {
        // Select all
        _selectedFullCreditIds.clear();
        for (final credit in credits) {
          if (credit.balance > 0) {
            _selectedFullCreditIds.add(credit.id);
          }
        }
      }
    });
  }

  bool get _areAllFullSelected {
    final credits = _customerCredits;
    if (credits.isEmpty) return false;
    return credits.every((credit) => _selectedFullCreditIds.contains(credit.id));
  }

  void _autoFillPartial(CreditEntry credit) {
    final controller = _partialControllerFor(credit.id);
    controller.text = credit.balance.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _confirmPartialPayments() async {
    if (_selectedPartialCreditIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one item to pay partially')),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      for (final creditId in _selectedPartialCreditIds) {
        final controller = _partialAmountControllers[creditId];
        if (controller == null) continue;
        final amount = double.tryParse(controller.text.trim()) ?? 0;
        final outstanding = _outstandingFor(creditId);
        if (amount <= 0 || amount > outstanding) {
          throw StateError(
            'Invalid amount entered. Amount must be greater than 0 and not exceed ₱${outstanding.toStringAsFixed(2)}.',
          );
        }

        await widget.store.addPayment(
          creditId: creditId,
          amount: amount,
          date: _paymentDate,
        );
      }

      // Use selective refresh for better performance - only refresh affected credits
      for (final creditId in _selectedPartialCreditIds) {
        await widget.store.refreshCredit(creditId);
      }

      if (!mounted) return;
      
      // Check connectivity status to show appropriate message
      final connectivityService = ConnectivityService();
      await connectivityService.initialize();
      final isOnline = connectivityService.isOnline;
      
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isOnline ? Icons.check_circle : Icons.cloud_upload,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isOnline 
                    ? 'Partial payments recorded successfully'
                    : 'Payments saved offline. They will sync automatically when you\'re back online.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: isOnline ? Colors.green : Colors.orange,
          duration: Duration(seconds: isOnline ? 3 : 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing payment: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _confirmFullPayments() async {
    if (_selectedFullCreditIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one item to pay in full')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      for (final creditId in _selectedFullCreditIds) {
        final outstanding = _outstandingFor(creditId);
        if (outstanding <= 0) {
          continue;
        }
        await widget.store.addPayment(
          creditId: creditId,
          amount: outstanding,
          date: _paymentDate,
        );
      }

      // Use selective refresh for better performance - only refresh affected credits
      for (final creditId in _selectedFullCreditIds) {
        await widget.store.refreshCredit(creditId);
      }

      if (!mounted) return;
      
      // Check connectivity status to show appropriate message
      final connectivityService = ConnectivityService();
      await connectivityService.initialize();
      final isOnline = connectivityService.isOnline;
      
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isOnline ? Icons.check_circle : Icons.cloud_upload,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isOnline 
                    ? 'Full payments recorded successfully'
                    : 'Payments saved offline. They will sync automatically when you\'re back online.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: isOnline ? Colors.green : Colors.orange,
          duration: Duration(seconds: isOnline ? 3 : 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing payment: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // Removed bulk Auto Pay for safety

  @override
  void dispose() {
    for (final controller in _partialAmountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildPartialContent(List<CreditEntry> credits) {
    if (credits.isEmpty) {
      return const Text('No outstanding credits to pay.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...credits.map(_buildPartialCard),
        const SizedBox(height: 12),
        _buildTotalRow('Total Partial Payment', _partialTotal),
      ],
    );
  }

  Widget _buildPartialCard(CreditEntry credit) {
    final isSelected = _selectedPartialCreditIds.contains(credit.id);
    final controller = _partialControllerFor(credit.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        credit.item,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Outstanding: ₱${credit.balance.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Total: ₱${credit.amount.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Paid: ₱${credit.paidAmount.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Date: ${_formatDate(credit.date)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: isSelected,
                  onChanged: (value) => _togglePartialSelection(credit.id, value ?? false),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount to pay',
                        prefixText: '₱ ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (!_selectedPartialCreditIds.contains(credit.id)) {
                          return null;
                        }
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter amount';
                        }
                        final parsed = double.tryParse(value);
                        if (parsed == null || parsed <= 0) {
                          return 'Amount must be greater than 0';
                        }
                        if (parsed > credit.balance) {
                          return 'Cannot exceed ₱${credit.balance.toStringAsFixed(2)}';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _autoFillPartial(credit),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Auto'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFullContent(List<CreditEntry> credits) {
    if (credits.isEmpty) {
      return const Text('No outstanding credits to pay.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...credits.map(_buildFullCard),
        const SizedBox(height: 12),
        _buildTotalRow('Total Full Payment', _fullTotal),
      ],
    );
  }

  Widget _buildFullCard(CreditEntry credit) {
    final isSelected = _selectedFullCreditIds.contains(credit.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        credit.item,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Outstanding: ₱${credit.balance.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Total: ₱${credit.amount.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Paid: ₱${credit.paidAmount.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Date: ${_formatDate(credit.date)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: isSelected,
                  onChanged: (value) => _toggleFullSelection(credit.id, value ?? false),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 12),
              TextFormField(
                initialValue: '₱${credit.balance.toStringAsFixed(2)}',
                readOnly: true,
                enableInteractiveSelection: false,
                decoration: const InputDecoration(
                  labelText: 'Amount to pay',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount) {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₱${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.green.shade300 : Colors.green,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final credits = _customerCredits;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (credits.isEmpty) {
      return AlertDialog(
        title: const Text('No Outstanding Credits'),
        content: const Text('This customer has no outstanding credits to pay.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.green.shade900.withOpacity(0.3)
                    : Colors.green.shade50,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.customer.name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.grey.shade100 : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Outstanding: ₱${widget.store.totalOutstandingForCustomer(widget.customer.id).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Type',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<PaymentType>(
                        segments: const [
                          ButtonSegment(
                            value: PaymentType.partial,
                            label: Text('Partial Payment'),
                            icon: Icon(Icons.payments, size: 18),
                          ),
                          ButtonSegment(
                            value: PaymentType.full,
                            label: Text('Full Payment'),
                            icon: Icon(Icons.verified, size: 18),
                          ),
                        ],
                        selected: {_paymentType},
                        onSelectionChanged: (selection) {
                          _switchPaymentType(selection.first);
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _paymentType == PaymentType.partial
                                  ? 'Select item(s) for partial payment'
                                  : 'Select item(s) to pay in full',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_paymentType == PaymentType.full && credits.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: TextButton.icon(
                                onPressed: _toggleSelectAllFull,
                                icon: Icon(
                                  _areAllFullSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 18,
                                ),
                                label: Text(_areAllFullSelected ? 'Deselect All' : 'Select All'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_paymentType == PaymentType.partial)
                        _buildPartialContent(credits)
                      else
                        _buildFullContent(credits),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Payment Date: ${_formatDate(_paymentDate)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _pickDate,
                            child: const Text('Change Date'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: ElevatedButton(
                      onPressed: _isProcessing
                          ? null
                          : (_paymentType == PaymentType.partial
                              ? _confirmPartialPayments
                              : _confirmFullPayments),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

