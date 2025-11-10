import 'package:flutter/material.dart';
import 'home_page.dart';
import 'payment_page.dart';
import 'credits/add_credit_page.dart';
import '../../../core/widgets/offline_banner.dart';

class MainNavigation extends StatefulWidget {
  final String email;
  
  const MainNavigation({super.key, required this.email});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      HomePage(email: widget.email),
      AddCreditPage(hideAppBar: false, onBackPressed: () => setState(() => _currentIndex = 0)),
      PaymentPage(hideAppBar: false, onBackPressed: () => setState(() => _currentIndex = 0)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OfflineBanner(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            // Recreate pages to reset forms whenever visiting Add Credit or Payment
            if (index == 1) {
              _pages[1] = AddCreditPage(hideAppBar: false, onBackPressed: () => setState(() => _currentIndex = 0));
            } else if (index == 2) {
              _pages[2] = PaymentPage(hideAppBar: false, onBackPressed: () => setState(() => _currentIndex = 0));
            }
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add Credit',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payment),
            label: 'Payment',
          ),
        ],
      ),
    );
  }
}
