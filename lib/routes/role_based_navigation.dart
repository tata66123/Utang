import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config/build_config.dart';
import '../core/services/data_store.dart';
import '../core/models/models.dart';
import '../features/owner/pages/store_owner_navigation.dart';
import '../features/customer/pages/customer_dashboard.dart';

class RoleBasedNavigation extends StatelessWidget {
  const RoleBasedNavigation({super.key});

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

        if (BuildConfig.customerOnly) {
          return const CustomerDashboard();
        }

        // Route based on user role
        switch (user.role) {
          case UserRole.storeOwner:
            return const StoreOwnerNavigation();
          case UserRole.customer:
            return const CustomerDashboard();
        }
      },
    );
  }
}
