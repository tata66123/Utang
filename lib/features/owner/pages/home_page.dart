import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'auth/login_page.dart';
import 'customers_page.dart';
import 'summary_page.dart';
import 'overview_outstanding_page.dart';
import 'overview_paid_page.dart';
import 'history_page.dart';
import 'reminders_page.dart';
import 'analysis_page.dart';
import 'settings_page.dart';
import '../../../core/services/data_store.dart';
import '../../../core/models/models.dart';

class HomePage extends StatefulWidget {
  final String email;
  const HomePage({super.key, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, store, child) {
        final String displayName = store.state.currentUser?.username ?? 
            (widget.email.contains('@') && widget.email.indexOf('@') > 0
                ? widget.email.substring(0, widget.email.indexOf('@'))
                : widget.email);
        final String storeName = store.state.currentUser?.storeName ?? 'Your Store';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text("Dashboard")),

      //  DRAWER MENU
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(displayName.isNotEmpty ? displayName : 'User'),
              accountEmail: Text(storeName), // STORE NAME UNDER USERNAME
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blue),
              ),
              decoration: const BoxDecoration(color: Colors.blue),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text("Dashboard"),
              onTap: () {
                Navigator.pop(context); // NEED ICON DRAWER AUTO CLOSE WHEN BACKING TO PAGE
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text("Customers"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CustomersPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.summarize),
              title: const Text("Outstanding Summary"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SummaryPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("Transaction History"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HistoryPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text("Due Dates & Reminders"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RemindersPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text("Payment Analysis"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AnalysisPage()),
                );
              },
            ),
            const Divider(),
            // Theme Mode Toggle
            Consumer<DataStore>(
              builder: (context, store, child) {
                return ListTile(
                  leading: Icon(
                    store.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    color: store.isDarkMode ? Colors.orange : Colors.amber,
                  ),
                  title: const Text("Theme Mode"),
                  subtitle: Text(store.isDarkMode ? 'Dark Mode' : 'Light Mode'),
                  trailing: Switch(
                    value: store.isDarkMode,
                    onChanged: (value) async {
                      // Toggle theme
                      await store.toggleTheme();
                    },
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("Settings"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red)),
              onTap: () {
                DataStore.instance.logoutUser();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginPage(),
                  ),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),

        body: _DashboardBody(email: widget.email, displayName: displayName, storeName: storeName, store: store),
      );
      },
    );
  }
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody({required this.email, required this.displayName, required this.storeName, required this.store});
  final String email;
  final String displayName;
  final String storeName;
  final DataStore store;

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  // Cache for expensive computations
  List<FlSpot>? _cachedCreditSpots;
  List<FlSpot>? _cachedPaymentSpots;
  int? _cachedCreditsHashCode;
  DateTime? _cachedMonth;

  Widget _buildRecentActivity(DataStore store) {
    // Get recent credits (last 3) - optimized with single sort
    final credits = store.state.credits;
    if (credits.isEmpty) {
      return Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Column(
            children: [
              Icon(
                Icons.inbox,
                size: 48,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              Text(
                'No recent activity',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          );
        },
      );
    }

    // Sort and take only what we need
    final sortedCredits = List<CreditEntry>.from(credits)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recentCreditsList = sortedCredits.take(3).toList();

    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return Column(
          children: recentCreditsList.map((credit) {
            // Pre-fetch customer data to avoid FutureBuilder overhead
            return _RecentActivityItem(
              credit: credit,
              store: store,
              isDark: isDark,
            );
          }).toList(),
        );
      },
    );
  }




  Widget _buildSimpleChart(DataStore store) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final creditsHash = store.state.credits.length;
    
    // Check cache validity
    if (_cachedCreditSpots == null || 
        _cachedPaymentSpots == null ||
        _cachedMonth != currentMonth ||
        _cachedCreditsHashCode != creditsHash) {
      // Regenerate only if cache is invalid
      _cachedCreditSpots = _generateChartData(store);
      _cachedPaymentSpots = _generatePaymentData(store);
      _cachedMonth = currentMonth;
      _cachedCreditsHashCode = creditsHash;
    }
    
    final creditSpots = _cachedCreditSpots!;
    final paymentSpots = _cachedPaymentSpots!;
    final daysInMonth = DateTime(now.year, now.month + 1, 1).difference(DateTime(now.year, now.month, 1)).inDays;
    
    // Find max value for scaling
    double maxValue = 0;
    for (final spot in [...creditSpots, ...paymentSpots]) {
      if (spot.y > maxValue) maxValue = spot.y;
    }
    
    // Simple scaling
    double maxY = maxValue > 0 ? (maxValue * 1.2).ceilToDouble() : 1000;
    if (maxY < 100) maxY = 100;
    
    // If no data, show empty state
    if (creditSpots.isEmpty && paymentSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No data available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          drawHorizontalLine: true,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                if (value < 0) return const SizedBox();
                String text;
                if (value >= 1000) {
                  text = '₱${(value / 1000).toStringAsFixed(1)}k';
                } else {
                  text = '₱${value.toStringAsFixed(0)}';
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 25,
              interval: daysInMonth > 15 ? 7.0 : 5.0,
              getTitlesWidget: (value, meta) {
                final day = value.toInt();
                if (day < 1 || day > daysInMonth || day != value) {
                  return const SizedBox();
                }
                return Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade600,
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
        lineBarsData: [
          // Credits line
          LineChartBarData(
            spots: creditSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.blue.shade400,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: false,
            ),
          ),
          // Payments line
          LineChartBarData(
            spots: paymentSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.green.shade400,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: false,
            ),
          ),
        ],
        minX: 1,
        maxX: daysInMonth.toDouble(),
        minY: 0,
        maxY: maxY,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((touchedSpot) {
                final isCredit = touchedSpot.barIndex == 0;
                final label = isCredit ? 'Credits' : 'Payments';
                final amount = touchedSpot.y;
                final day = touchedSpot.x.toInt();
                
                return LineTooltipItem(
                  '$label\nDay $day: ₱${amount.toStringAsFixed(2)}',
                  TextStyle(
                    color: isCredit ? Colors.blue.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }


  List<FlSpot> _generateChartData(DataStore store) {
    try {
      final now = DateTime.now();
      final List<FlSpot> spots = [];
      
      // Get data for the current month only (daily breakdown)
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 1);
      final daysInMonth = monthEnd.difference(monthStart).inDays;
      
      // Pre-filter credits for current month to avoid repeated checks
      final monthCredits = store.state.credits.where((credit) {
        final creditDate = credit.date;
        return creditDate.isAfter(monthStart.subtract(const Duration(days: 1))) && 
               creditDate.isBefore(monthEnd);
      }).toList();
      
      // Generate daily data points for current month
      for (int day = 1; day <= daysInMonth; day++) {
        final currentDay = DateTime(now.year, now.month, day);
        final nextDay = DateTime(now.year, now.month, day + 1);
        
        // Calculate credits for this day - only check filtered credits
        double dailyCredits = 0;
        for (final credit in monthCredits) {
          final creditDate = credit.date;
          if (creditDate.isAfter(currentDay.subtract(const Duration(days: 1))) && 
              creditDate.isBefore(nextDay)) {
            dailyCredits += credit.amount;
          }
        }
        
        spots.add(FlSpot(day.toDouble(), dailyCredits));
      }
      
      return spots;
    } catch (e) {
      return [];
    }
  }

  List<FlSpot> _generatePaymentData(DataStore store) {
    try {
      final now = DateTime.now();
      final List<FlSpot> spots = [];
      
      // Get data for the current month only (daily breakdown)
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 1);
      final daysInMonth = monthEnd.difference(monthStart).inDays;
      
      // Pre-filter credits and collect all payments for the month
      final monthPayments = <DateTime, double>{};
      for (final credit in store.state.credits) {
        for (final payment in credit.payments) {
          final paymentDate = payment.date;
          if (paymentDate.isAfter(monthStart.subtract(const Duration(days: 1))) && 
              paymentDate.isBefore(monthEnd)) {
            final dayKey = DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
            monthPayments[dayKey] = (monthPayments[dayKey] ?? 0) + payment.amount;
          }
        }
      }
      
      // Generate daily data points for current month
      for (int day = 1; day <= daysInMonth; day++) {
        final currentDay = DateTime(now.year, now.month, day);
        final dailyPayments = monthPayments[currentDay] ?? 0.0;
        spots.add(FlSpot(day.toDouble(), dailyPayments));
      }
      
      return spots;
    } catch (e) {
      return [];
    }
  }




  @override
  Widget build(BuildContext context) {
    final DateTime lastSynced = DateTime.now();
    final String lastSyncedText = 'Last synced: ${lastSynced.day}/${lastSynced.month}/${lastSynced.year} ${lastSynced.hour.toString().padLeft(2, '0')}:${lastSynced.minute.toString().padLeft(2, '0')}';

    return Selector<DataStore, AppState>(
      selector: (_, store) => store.state,
      builder: (context, state, child) {
        final dataStore = Provider.of<DataStore>(context, listen: false);
        return RefreshIndicator(
          onRefresh: () async {
            // Manual refresh - sync data when user pulls down
            try {
              await dataStore.syncNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Data refreshed successfully'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Refresh error: $e'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
          // Welcome section with store name
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.blue.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome, ${widget.displayName}!",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Text(
                  "Store: ${widget.storeName}",
                  style: TextStyle(fontSize: 16, color: Colors.blue.shade700),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Data Visualization Section - SIMPLIFIED VERSION WITH SMALL GRAPH
          Text(
            "This Month Summary",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          
          // Simple compact graph
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daily Overview',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Credits',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Payments',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    child: _buildSimpleChart(dataStore),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Clickable stats grid
          Text(
            "Overview",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            childAspectRatio: 0.9,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              _EnhancedStatCard(
                title: 'Total Outstanding', 
                value: '₱${dataStore.totalOutstanding().toStringAsFixed(2)}', 
                subtitle: '',
                icon: Icons.account_balance_wallet, 
                color: Colors.blue,
                lastSynced: lastSyncedText,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OutstandingDetailsPage()),
                ),
              ),
              _TotalPaidCard(store: dataStore),
              _ClickableStatCard(
                title: 'Customers', 
                value: '${state.customers.length}', 
                icon: Icons.group, 
                color: Colors.teal,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomersPage())),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Recent Activity Section
          Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
              
              return Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.history,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.grey.shade200 : Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRecentActivity(dataStore),
                  ],
                ),
              );
            },
          ),
        ],
            ),
          ),
        );
      },
    );
  }
}

// Optimized widget for recent activity items to avoid FutureBuilder overhead
class _RecentActivityItem extends StatelessWidget {
  const _RecentActivityItem({
    required this.credit,
    required this.store,
    required this.isDark,
  });

  final CreditEntry credit;
  final DataStore store;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Try to get customer from state first (synchronous)
    final customer = store.state.customers.firstWhere(
      (c) => c.id == credit.customerId,
      orElse: () => Customer(id: '', name: 'Unknown'),
    );
    
    final name = customer.name.isNotEmpty ? customer.name : 'Unknown';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: credit.balance > 0
                ? (isDark ? Colors.orange.shade900.withOpacity(0.3) : Colors.orange.shade100)
                : (isDark ? Colors.green.shade900.withOpacity(0.3) : Colors.green.shade100),
            child: Icon(
              credit.balance > 0 ? Icons.receipt : Icons.check,
              size: 16,
              color: credit.balance > 0 ? Colors.orange : Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name - ${credit.item}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade100 : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Qty: ${credit.quantity} ${credit.unit ?? 'pcs'} × ₱${credit.effectiveUnitPrice.toStringAsFixed(2)} = ₱${credit.amount.toStringAsFixed(2)} • ${_formatDateTime(credit.date)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    
    if (difference == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference == 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference < 7) {
      return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }
}

class _ClickableStatCard extends StatelessWidget {
  const _ClickableStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    foregroundColor: color,
                    child: Icon(icon, size: 18),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnhancedStatCard extends StatelessWidget {
  const _EnhancedStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.lastSynced,
    required this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String lastSynced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    foregroundColor: color,
                    child: Icon(icon, size: 18),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
              Text(
                lastSynced,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 8),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalPaidCard extends StatelessWidget {
  const _TotalPaidCard({required this.store});
  final DataStore store;

  @override
  Widget build(BuildContext context) {
    final totalPaid = store.getTotalAmountPaid();
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PaidDetailsPage()),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    foregroundColor: Colors.green,
                    child: const Icon(Icons.payments, size: 18),
                  ),
                  const Spacer(),
                  Icon(Icons.open_in_new, size: 14, color: Colors.grey.shade400),
                ],
              ),
              Text(
                'Total Amount Paid',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                '₱${totalPaid.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 6),
              Text(
                'Tap to view paid items by customer',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }


}




