import 'package:flutter/material.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class AnalysisPage extends StatelessWidget {
  const AnalysisPage({super.key});

  double _reliabilityScoreForCustomer(DataStore store, String customerId) {
    final List<CreditEntry> entries = store.state.credits.where((CreditEntry e) => e.customerId == customerId).toList();
    if (entries.isEmpty) return 0;
    int onTime = 0;
    int total = 0;
    for (final CreditEntry e in entries) {
      // Only count credits with due dates
      if (e.dueDate == null) continue;
      double cumulative = 0;
      final DateTime due = e.dueDate!;
      // Sort payments by date to process chronologically
      final List<Payment> pays = List<Payment>.from(e.payments)..sort((Payment a, Payment b) => a.date.compareTo(b.date));
      for (final Payment p in pays) {
        cumulative += p.amount;
        // Check if credit is fully paid (using small epsilon for floating point comparison)
        if (cumulative + 1e-6 >= e.amount) {
          total++;
          // Check if the payment that completed the credit was on or before due date
          if (!p.date.isAfter(due)) onTime++;
          break;
        }
      }
    }
    if (total == 0) return 0;
    // Calculate percentage: (onTime / total) * 100, clamped between 0 and 100
    final double ratio = onTime / total;
    return (ratio * 100).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final DataStore store = DataStore.instance;
    final List<Customer> customers = store.state.customers;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Behavior Analysis')),
      body: customers.isEmpty
          ? const Center(child: Text('No customers'))
          : ListView.builder(
              itemCount: customers.length,
              itemBuilder: (BuildContext context, int index) {
                final Customer c = customers[index];
                final double score = _reliabilityScoreForCustomer(store, c.id);
                
                // Determine color based on score
                Color scoreColor;
                Color backgroundColor;
                IconData scoreIcon;
                
                if (score >= 80) {
                  scoreColor = Colors.green;
                  backgroundColor = isDark 
                      ? Colors.green.shade900.withOpacity(0.3)
                      : Colors.green.shade50;
                  scoreIcon = Icons.check_circle;
                } else if (score >= 60) {
                  scoreColor = Colors.orange;
                  backgroundColor = isDark 
                      ? Colors.orange.shade900.withOpacity(0.3)
                      : Colors.orange.shade50;
                  scoreIcon = Icons.warning;
                } else {
                  scoreColor = Colors.red;
                  backgroundColor = isDark 
                      ? Colors.red.shade900.withOpacity(0.3)
                      : Colors.red.shade50;
                  scoreIcon = Icons.error;
                }
                
                return Card(
                  child: Container(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scoreColor.withOpacity(0.2),
                        child: Icon(scoreIcon, color: scoreColor),
                      ),
                      title: Text(
                        c.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey.shade100 : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        'Outstanding: ₱${store.totalOutstandingForCustomer(c.id).toStringAsFixed(2)}',
                        style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: scoreColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${score.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}


