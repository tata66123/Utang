import 'package:flutter/material.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';
import 'auth/login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DataStore get _store => DataStore.instance;
  final TextEditingController _creditLimitController = TextEditingController();
  bool _isLoading = false;
  double? _lastCreditLimit; // Track the last known credit limit value

  void _logout() {
    showDialog(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              DataStore.instance.logoutUser();
              Navigator.of(ctx).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _clearAllData() {
    final user = _store.state.currentUser;
    if (user == null || user.role != UserRole.storeOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only store owners can clear transaction data')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Clear Store Transaction Data'),
        content: Text(
          'This will permanently delete all credits, payments, and transaction history for "${user.storeName}".\n\n'
          'This will:\n'
          '• Delete all credits and payments for this store\n'
          '• Clear customer search history (customers with no remaining credits)\n'
          '• Reset monthly analytics and totals\n\n'
          'This will NOT:\n'
          '• Delete registered users\n'
          '• Delete other stores\' data\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              setState(() => _isLoading = true);
              try {
                await _store.clearStoreTransactionData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Store transaction data cleared successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error clearing data: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear Data', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _exportData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export functionality not implemented')),
    );
  }

  void _importData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import functionality not implemented')),
    );
  }


  @override
  void initState() {
    super.initState();
    _updateCreditLimitController();
    // Listen to state changes to keep credit limit field in sync
    // But only update if the credit limit value actually changed
    _store.addListener(_updateCreditLimitController);
    _lastCreditLimit = _store.state.currentUser?.creditLimit;
  }

  void _updateCreditLimitController() {
    final user = _store.state.currentUser;
    final currentCreditLimit = user?.creditLimit;
    
    // Only update the controller if the credit limit value actually changed
    // This prevents refreshing the field when credits are added (which triggers notifyListeners)
    if (currentCreditLimit != _lastCreditLimit) {
      _lastCreditLimit = currentCreditLimit;
      
      if (currentCreditLimit != null) {
        final currentText = _creditLimitController.text;
        final newText = currentCreditLimit.toStringAsFixed(2);
        // Only update if different to avoid cursor jumping
        if (currentText != newText) {
          _creditLimitController.text = newText;
        }
      } else {
        // Credit limit was cleared
        if (_creditLimitController.text.isNotEmpty) {
          _creditLimitController.clear();
        }
      }
    }
  }

  @override
  void dispose() {
    _store.removeListener(_updateCreditLimitController);
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _saveCreditLimit() async {
    if (_store.state.currentUser?.role != UserRole.storeOwner) {
      return; // Only for store owners
    }

    final limitText = _creditLimitController.text.trim();
    if (limitText.isEmpty) {
      // Clear credit limit
      setState(() => _isLoading = true);
      try {
        await _store.updateUserCreditLimit(null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Credit limit cleared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating credit limit: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
      return;
    }

    final limit = double.tryParse(limitText);
    if (limit == null || limit < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid positive number'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _store.updateUserCreditLimit(limit);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Credit limit set to ₱${limit.toStringAsFixed(2)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating credit limit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _store.state.currentUser;
    final totalCustomers = _store.state.customers.length;
    final totalCredits = _store.state.credits.length;
    final totalOutstanding = _store.totalOutstanding();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // User Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (user != null) ...[
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text('Username'),
                      subtitle: Text(user.username),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email),
                      title: const Text('Email'),
                      subtitle: Text(user.email),
                    ),
                    ListTile(
                      leading: const Icon(Icons.store),
                      title: const Text('Store Name'),
                      subtitle: Text(user.storeName),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Credit Limit Settings Card (only for store owners)
          if (user != null && user.role == UserRole.storeOwner) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Credit Limit Settings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Set a credit limit per transaction for your store. When adding a credit transaction that exceeds this limit, you will receive a warning (but can still proceed).',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _creditLimitController,
                      decoration: InputDecoration(
                        labelText: 'Credit Limit (₱)',
                        hintText: 'Enter amount or leave empty to remove limit',
                        prefixIcon: const Icon(Icons.account_balance_wallet),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: _creditLimitController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _creditLimitController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 12),
                    if (user.creditLimit != null) ...[
                      Text(
                        'Current Limit (Per Transaction): ₱${user.creditLimit!.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveCreditLimit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save Credit Limit'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // App Statistics Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Statistics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.people, color: Colors.blue),
                    title: const Text('Total Customers'),
                    subtitle: Text('$totalCustomers customers'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long, color: Colors.green),
                    title: const Text('Total Credits'),
                    subtitle: Text('$totalCredits credit entries'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet, color: Colors.orange),
                    title: const Text('Total Outstanding'),
                    subtitle: Text('₱${totalOutstanding.toStringAsFixed(2)}'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Data Management Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Data Management',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.green),
                    title: const Text('Export Data'),
                    subtitle: const Text('Export all data to file'),
                    onTap: _exportData,
                  ),
                  ListTile(
                    leading: const Icon(Icons.upload, color: Colors.green),
                    title: const Text('Import Data'),
                    subtitle: const Text('Import data from file'),
                    onTap: _importData,
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Clear All Data'),
                    subtitle: const Text('Permanently delete all data'),
                    onTap: _clearAllData,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // App Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.info, color: Colors.blue),
                    title: const Text('App Version'),
                    subtitle: const Text('1.0.0'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Colors.green),
                    title: const Text('Help & Support'),
                    subtitle: const Text('Get help and support'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Help & Support coming soon')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip, color: Colors.orange),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('View privacy policy'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Privacy Policy coming soon')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Logout Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _logout,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}
