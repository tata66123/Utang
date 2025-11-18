import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import '../../../core/services/notification_service.dart';
import '../../owner/pages/auth/login_page.dart';
import 'customer_home_page.dart';
import 'customer_credits_page.dart';
import 'customer_payments_page.dart';
import 'customer_notifications_page.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  late NotificationService _notificationService;
  int _currentIndex = 0;

  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService();
    _checkNotifications();
    _refreshData();
    
    _pages.addAll([
      const CustomerHomePage(),
      const CustomerCreditsPage(),
      const CustomerPaymentsPage(),
      const CustomerNotificationsPage(),
    ]);
  }

  void _refreshData() async {
    final dataStore = Provider.of<DataStore>(context, listen: false);
    await dataStore.refreshData();
  }

  void _checkNotifications() async {
    final dataStore = Provider.of<DataStore>(context, listen: false);
    final user = dataStore.state.currentUser;
    
    if (user != null) {
      // Check for overdue credits
      final overdueCredits = dataStore.getCustomerOverdueCredits(user.id);
      if (overdueCredits.isNotEmpty) {
        await _notificationService.showOverdueNotification(context);
      }
      
      // Check for due soon credits
      final dueSoonCredits = dataStore.getCustomerDueSoonCredits(user.id);
      if (dueSoonCredits.isNotEmpty) {
        final totalAmount = dueSoonCredits.fold(0.0, (sum, credit) => sum + credit.amount);
        await _notificationService.showDueSoonNotification(context, totalAmount);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, dataStore, child) {
        final user = dataStore.state.currentUser;
        if (user == null) {
          return const Scaffold(
            body: Center(child: Text('No user logged in')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Customer Dashboard'),
            leading: Consumer<DataStore>(
              builder: (context, store, child) {
                return IconButton(
                  icon: Icon(
                    store.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    color: store.isDarkMode ? Colors.orange : Colors.amber,
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await store.toggleTheme();
                  },
                  tooltip: store.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                );
              },
            ),
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await dataStore.logoutUser();
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                    );
                  }
                },
                tooltip: 'Logout',
              ),
            ],
          ),
          body: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          bottomNavigationBar: Consumer<DataStore>(
            builder: (context, store, child) {
              final isDark = store.isDarkMode;
              return BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentIndex = index;
                  });
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: isDark ? Colors.grey.shade800 : Colors.blue,
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white70,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.credit_card),
                label: 'Credits',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.payment),
                label: 'Payments',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications),
                label: 'Notifications',
              ),
            ],
              );
            },
          ),
        );
      },
    );
  }
}
