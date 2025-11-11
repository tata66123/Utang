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

    // Auto-open the drawer shortly after build to make it pop when arriving here
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scaffoldKey.currentState?.openDrawer();
      }
    });

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
                    onChanged: (value) => store.toggleTheme(),
                  ),
                );
              },
            ),
            // Sync Now Button
            Consumer<DataStore>(
              builder: (context, store, child) {
                return ListTile(
                  leading: store.isSyncing 
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        )
                      : const Icon(Icons.sync, color: Colors.blue),
                  title: const Text("Sync Now"),
                  subtitle: store.isSyncing 
                      ? const Text('Syncing data...')
                      : const Text('Sync data with cloud'),
                  onTap: store.isSyncing ? null : () => store.syncNow(),
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.email, required this.displayName, required this.storeName, required this.store});
  final String email;
  final String displayName;
  final String storeName;
  final DataStore store;

  Widget _buildRecentActivity(DataStore store) {
    // Get recent credits (last 5)
    final recentCredits = store.state.credits
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    
    final recentCreditsList = recentCredits.take(3).toList();
    
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        if (recentCreditsList.isEmpty) {
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
        }

        return Column(
          children: recentCreditsList.map((credit) {
            return FutureBuilder<Customer?>(
              future: store.getCustomerById(credit.customerId),
              builder: (context, snapshot) {
                final name = (snapshot.hasData && snapshot.data != null && snapshot.data!.name.isNotEmpty)
                  ? snapshot.data!.name
                  : 'Unknown';
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
                              '₱${credit.amount.toStringAsFixed(2)} • ${_formatDateTime(credit.date)}',
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
              },
            );
          }).toList(),
        );
      },
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

  String _getMonthTotalCredits(DataStore store) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);
    
    double total = 0;
    for (final credit in store.state.credits) {
      if (credit.date.isAfter(monthStart.subtract(const Duration(days: 1))) && 
          credit.date.isBefore(monthEnd)) {
        total += credit.amount;
      }
    }
    
    return '₱${total.toStringAsFixed(2)}';
  }

  String _getMonthTotalPayments(DataStore store) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);
    
    double total = 0;
    for (final credit in store.state.credits) {
      for (final payment in credit.payments) {
        if (payment.date.isAfter(monthStart.subtract(const Duration(days: 1))) && 
            payment.date.isBefore(monthEnd)) {
          total += payment.amount;
        }
      }
    }
    
    return '₱${total.toStringAsFixed(2)}';
  }

  Widget _buildSimpleChart(DataStore store) {
    final creditSpots = _generateChartData(store);
    final paymentSpots = _generatePaymentData(store);
    final now = DateTime.now();
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
    final now = DateTime.now();
    final List<FlSpot> spots = [];
    
    // Get data for the current month only (daily breakdown)
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);
    final daysInMonth = monthEnd.difference(monthStart).inDays;
    
    // Generate daily data points for current month
    for (int day = 1; day <= daysInMonth; day++) {
      final currentDay = DateTime(now.year, now.month, day);
      final nextDay = DateTime(now.year, now.month, day + 1);
      
      // Calculate credits for this day
      double dailyCredits = 0;
      for (final credit in store.state.credits) {
        if (credit.date.isAfter(currentDay.subtract(const Duration(days: 1))) && 
            credit.date.isBefore(nextDay)) {
          dailyCredits += credit.amount;
        }
      }
      
      spots.add(FlSpot(day.toDouble(), dailyCredits));
    }
    
    return spots;
  }

  List<FlSpot> _generatePaymentData(DataStore store) {
    final now = DateTime.now();
    final List<FlSpot> spots = [];
    
    // Get data for the current month only (daily breakdown)
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);
    final daysInMonth = monthEnd.difference(monthStart).inDays;
    
    // Generate daily data points for current month
    for (int day = 1; day <= daysInMonth; day++) {
      final currentDay = DateTime(now.year, now.month, day);
      final nextDay = DateTime(now.year, now.month, day + 1);
      
      // Calculate payments for this day
      double dailyPayments = 0;
      for (final credit in store.state.credits) {
        for (final payment in credit.payments) {
          if (payment.date.isAfter(currentDay.subtract(const Duration(days: 1))) && 
              payment.date.isBefore(nextDay)) {
            dailyPayments += payment.amount;
          }
        }
      }
      
      spots.add(FlSpot(day.toDouble(), dailyPayments));
    }
    
    return spots;
  }

  Widget _buildChart(DataStore store) {
    final creditSpots = _generateChartData(store);
    final paymentSpots = _generatePaymentData(store);
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 1).difference(DateTime(now.year, now.month, 1)).inDays;
    
    // Find max value for dynamic scaling
    double maxValue = 0;
    for (final spot in [...creditSpots, ...paymentSpots]) {
      if (spot.y > maxValue) maxValue = spot.y;
    }
    
    // Calculate optimal Y-axis range with proper padding
    double minY = 0;
    double maxY;
    int yAxisDivisions = 5;
    
    if (maxValue == 0) {
      maxY = 1000; // Default max if no data
    } else if (maxValue < 100) {
      // For small values, round up to next 10
      maxY = ((maxValue * 1.2) / 10).ceil() * 10;
      maxY = maxY < 50 ? 50 : maxY;
    } else if (maxValue < 1000) {
      // For medium values, round up to next 100
      maxY = ((maxValue * 1.2) / 100).ceil() * 100;
    } else {
      // For large values, round up to next 1000
      maxY = ((maxValue * 1.2) / 1000).ceil() * 1000;
    }
    
    // Calculate optimal interval for Y-axis labels
    double yInterval = maxY / yAxisDivisions;
    
    // Calculate average values for average line
    double creditAvg = 0;
    double paymentAvg = 0;
    if (creditSpots.isNotEmpty) {
      creditAvg = creditSpots.map((s) => s.y).reduce((a, b) => a + b) / creditSpots.length;
    }
    if (paymentSpots.isNotEmpty) {
      paymentAvg = paymentSpots.map((s) => s.y).reduce((a, b) => a + b) / paymentSpots.length;
    }
    
    // Ensure we have valid spots
    if (creditSpots.isEmpty && paymentSpots.isEmpty) {
      return Container(
        height: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey.shade50, Colors.grey.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No Data Available',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Add some credits and payments to see the chart',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    // Calculate X-axis interval based on days in month for even distribution
    double xInterval;
    if (daysInMonth <= 15) {
      xInterval = 2.0;
    } else if (daysInMonth <= 31) {
      xInterval = 5.0;
    } else {
      xInterval = 7.0;
    }
    
    // Get the latest data points for highlighting
    final lastCreditIndex = creditSpots.isNotEmpty ? creditSpots.length - 1 : -1;
    final lastPaymentIndex = paymentSpots.isNotEmpty ? paymentSpots.length - 1 : -1;
    
    return Container(
      height: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade50,
            Colors.white,
            Colors.blue.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.blue.shade100.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: daysInMonth * 15.0, // Make chart scrollable horizontally
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              );
            },
            child: LineChart(
              key: ValueKey('chart_${creditSpots.length}_${paymentSpots.length}'),
              LineChartData(
                gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                drawHorizontalLine: true,
                horizontalInterval: yInterval,
                verticalInterval: xInterval,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey.shade200.withOpacity(0.5),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.grey.shade200.withOpacity(0.3),
                    strokeWidth: 1,
                    dashArray: [2, 4],
                  );
                },
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  axisNameWidget: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      '₱ Amount',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value < 0) return const SizedBox();
                      String text;
                      if (value >= 1000) {
                        text = '₱${(value / 1000).toStringAsFixed(1)}k';
                      } else if (value >= 100) {
                        text = '₱${value.toStringAsFixed(0)}';
                      } else {
                        text = '₱${value.toStringAsFixed(1)}';
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(
                          text,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Day of Month',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      final day = value.toInt();
                      if (day < 1 || day > daysInMonth || day != value) {
                        return const SizedBox();
                      }
                      return Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
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
                  width: 1.5,
                ),
              ),
              lineBarsData: [
                // Credits line with gradient
                LineChartBarData(
                  spots: creditSpots,
                  isCurved: true,
                  curveSmoothness: 0.4,
                  gradient: LinearGradient(
                    colors: [
                      Colors.lightBlue.shade300, // Sky blue
                      const Color(0xFF2563EB), // Royal blue
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      final isLatest = index == lastCreditIndex;
                      return FlDotCirclePainter(
                        radius: isLatest ? 6 : 5,
                        color: isLatest 
                            ? Colors.blue.shade700 
                            : const Color(0xFF2563EB),
                        strokeWidth: isLatest ? 4 : 3,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  shadow: Shadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  belowBarData: BarAreaData(
                    show: false,
                  ),
                ),
                // Payments line with gradient
                LineChartBarData(
                  spots: paymentSpots,
                  isCurved: true,
                  curveSmoothness: 0.4,
                  gradient: LinearGradient(
                    colors: [
                      Colors.teal.shade300, // Mint green
                      const Color(0xFF059669), // Emerald green
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      final isLatest = index == lastPaymentIndex;
                      return FlDotCirclePainter(
                        radius: isLatest ? 6 : 5,
                        color: isLatest 
                            ? Colors.teal.shade700 
                            : const Color(0xFF059669),
                        strokeWidth: isLatest ? 4 : 3,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  shadow: Shadow(
                    color: Colors.teal.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  belowBarData: BarAreaData(
                    show: false,
                  ),
                ),
                // Average line for credits (dashed)
                if (creditAvg > 0)
                  LineChartBarData(
                    spots: creditSpots.map((s) => FlSpot(s.x, creditAvg)).toList(),
                    isCurved: false,
                    color: Colors.blue.shade300.withOpacity(0.6),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
                // Average line for payments (dashed)
                if (paymentAvg > 0)
                  LineChartBarData(
                    spots: paymentSpots.map((s) => FlSpot(s.x, paymentAvg)).toList(),
                    isCurved: false,
                    color: Colors.teal.shade300.withOpacity(0.6),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
              ],
              minX: 1,
              maxX: daysInMonth.toDouble(),
              minY: minY,
              maxY: maxY,
              lineTouchData: LineTouchData(
                enabled: true,
                touchSpotThreshold: 20,
                getTouchLineStart: (data, index) => double.minPositive,
                getTouchLineEnd: (data, index) => double.infinity,
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 16,
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  tooltipMargin: 10,
                  getTooltipColor: (touchedSpot) => Colors.grey.shade900.withOpacity(0.95),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((touchedSpot) {
                      final isCredit = touchedSpot.barIndex == 0;
                      
                      // Skip average lines in tooltip (barIndex >= 2)
                      if (touchedSpot.barIndex >= 2) {
                        return const LineTooltipItem('', TextStyle());
                      }
                      
                      final label = isCredit ? 'Credits' : 'Payments';
                      final icon = isCredit ? '🛒' : '💸';
                      final color = isCredit ? const Color(0xFF2563EB) : const Color(0xFF059669);
                      final day = touchedSpot.x.toInt();
                      final amount = touchedSpot.y;
                      
                      // Format date
                      final date = DateTime(now.year, now.month, day);
                      final monthName = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                         'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1];
                      
                      return LineTooltipItem(
                        '',
                        const TextStyle(),
                        children: [
                          TextSpan(
                            text: '$icon $label\n',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          TextSpan(
                            text: '$monthName $day, ${date.year}\n',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                          const TextSpan(text: '\n'),
                          TextSpan(
                            text: '₱',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                            ),
                          ),
                          TextSpan(
                            text: amount.toStringAsFixed(2),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      );
                    }).where((item) => item.children != null && item.children!.isNotEmpty).toList();
                  },
                ),
                // Highlight touched spots
                handleBuiltInTouches: true,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final DateTime lastSynced = DateTime.now();
    final String lastSyncedText = 'Last synced: ${lastSynced.day}/${lastSynced.month}/${lastSynced.year} ${lastSynced.hour.toString().padLeft(2, '0')}:${lastSynced.minute.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
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
                  "Welcome, $displayName!",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Text(
                  "Store: $storeName",
                  style: TextStyle(fontSize: 16, color: Colors.blue.shade700),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Data Visualization Section - SIMPLIFIED VERSION WITH SMALL GRAPH
          // TO REVERT: Uncomment the complex chart section below and remove this simple version
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
                    child: _buildSimpleChart(store),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Month totals
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.add_circle, color: Colors.blue.shade600, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Total Credits',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getMonthTotalCredits(store),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.payment, color: Colors.green.shade600, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Total Payments',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getMonthTotalPayments(store),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          /* ORIGINAL COMPLEX CHART - UNCOMMENT TO REVERT
          Text("Data Visualization", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bar_chart, color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Current Month Overview',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildChart(store),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Credits', 
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Payments', 
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          */
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
                value: '₱${store.totalOutstanding().toStringAsFixed(2)}', 
                subtitle: '',
                icon: Icons.account_balance_wallet, 
                color: Colors.blue,
                lastSynced: lastSyncedText,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OutstandingDetailsPage()),
                ),
              ),
              _TotalPaidCard(store: store),
              _ClickableStatCard(
                title: 'Customers', 
                value: '${store.state.customers.length}', 
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
                    _buildRecentActivity(store),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
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




