import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_store.dart';
import '../../core/models/models.dart';

/// Abstract base class for pages that require authentication
abstract class AuthenticatedPage extends StatelessWidget {
  const AuthenticatedPage({super.key});

  /// Build the authenticated content
  Widget buildAuthenticatedContent(BuildContext context, User user);

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStore>(
      builder: (context, dataStore, child) {
        final user = dataStore.state.currentUser;
        
        if (user == null) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Authentication Required',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Please log in to access this page'),
                ],
              ),
            ),
          );
        }

        return buildAuthenticatedContent(context, user);
      },
    );
  }
}

/// Abstract base class for pages that require specific user roles
abstract class RoleBasedPage extends AuthenticatedPage {
  const RoleBasedPage({super.key});

  /// Required user roles for this page
  List<UserRole> get requiredRoles;

  /// Build content for authorized users
  Widget buildAuthorizedContent(BuildContext context, User user);

  @override
  Widget buildAuthenticatedContent(BuildContext context, User user) {
    if (!requiredRoles.contains(user.role)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('You do not have permission to access this page'),
            ],
          ),
        ),
      );
    }

    return buildAuthorizedContent(context, user);
  }
}

/// Abstract base class for store owner pages
abstract class StoreOwnerPage extends RoleBasedPage {
  const StoreOwnerPage({super.key});

  @override
  List<UserRole> get requiredRoles => [UserRole.storeOwner];
}

/// Abstract base class for customer pages
abstract class CustomerPage extends RoleBasedPage {
  const CustomerPage({super.key});

  @override
  List<UserRole> get requiredRoles => [UserRole.customer];
}
