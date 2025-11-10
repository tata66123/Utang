import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/data_store.dart';
import 'main_navigation.dart';

class StoreOwnerNavigation extends StatelessWidget {
  const StoreOwnerNavigation({super.key});

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
        
        // Use the actual logged-in user's email/username
        return MainNavigation(email: user.username);
      },
    );
  }
}
