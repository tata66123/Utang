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
      if (e.dueDate == null) continue;
      double cumulative = 0;
      final DateTime due = e.dueDate!;
      final List<Payment> pays = List<Payment>.from(e.payments)..sort((Payment a, Payment b) => a.date.compareTo(b.date));
      for (final Payment p in pays) {
        cumulative += p.amount;
        if (cumulative + 1e-6 >= e.amount) {
          total++;
          if (!p.date.isAfter(due)) onTime++;
          break;
        }
      }
    }
    if (total == 0) return 0;
    final double ratio = onTime / total;
    return (ratio * 100).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final DataStore store = DataStore.instance;
    final List<Customer> customers = store.state.customers;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Behavior Analysis'), backgroundColor: Colors.blue),
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
                  backgroundColor = Colors.green.shade50;
                  scoreIcon = Icons.check_circle;
                } else if (score >= 60) {
                  scoreColor = Colors.orange;
                  backgroundColor = Colors.orange.shade50;
                  scoreIcon = Icons.warning;
                } else {
                  scoreColor = Colors.red;
                  backgroundColor = Colors.red.shade50;
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
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text('Outstanding: ₱${store.totalOutstandingForCustomer(c.id).toStringAsFixed(2)}'),
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


