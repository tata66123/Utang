import 'package:flutter/material.dart';
import '../../../../routes/role_based_navigation.dart';
import '../../../../core/services/data_store.dart';
import '../../../../core/models/models.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      final String username = _usernameController.text.trim();
      final String password = _passwordController.text;

      try {
        final bool success = await DataStore.instance.loginUser(username, password);
        if (mounted) {
          if (success) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (BuildContext context) => const RoleBasedNavigation(),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid username or password')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login error: $e')),
          );
        }
      }
    }
  }


  void _forgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forgot Password clicked')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 8),
                      const Text('Welcome Back', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Sign in to continue', style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                        validator: (String? v) {
                          if (v == null || v.isEmpty) return 'Please enter your username';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (String? v) {
                          if (v == null || v.isEmpty) return 'Please enter your password';
                          if (v.length < 6) return 'Password must be at least 6 characters';
                          return null;
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _forgotPassword, child: const Text('Forgot Password?')),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _login, child: const Text('Login')),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) => const SignUpPage())),
                        child: const Text("Don't have an account? Sign up"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  UserRole? _selectedRole;

  @override
  void initState() {
    super.initState();
    // Show role selection modal when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRoleSelectionModal();
    });
  }

  Future<void> _showRoleSelectionModal() async {
    final UserRole? role = await showDialog<UserRole>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _RoleSelectionDialog();
      },
    );

    if (role != null && mounted) {
      setState(() {
        _selectedRole = role;
      });
    } else if (mounted && role == null) {
      // If user dismissed without selecting, go back
      Navigator.pop(context);
    }
  }

  void _signUp() async {
    if (_formKey.currentState!.validate()) {
      final String username = _usernameController.text.trim();
      final String name = _nameController.text.trim();
      final String password = _passwordController.text;
      
      try {
        await DataStore.instance.addUser(
          email: '', // No email field anymore
          username: username,
          storeName: name, // This will be the store name for store owners or full name for customers
          password: password,
          role: _selectedRole!,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Account created for $username'))
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating account: $e'))
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show form until role is selected
    if (_selectedRole == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sign Up')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Show role-specific title based on selected role
                      Text(
                        _selectedRole == UserRole.storeOwner 
                            ? 'Store Owner Registration' 
                            : 'Customer Registration',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedRole == UserRole.storeOwner 
                            ? 'Register your store' 
                            : 'Create your account',
                        style: TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                        validator: (String? v) {
                          if (v == null || v.isEmpty) return 'Please enter your username';
                          if (v.length < 3) return 'Username must be at least 3 characters';
                          // Username validation: only letters and numbers, no spaces or special characters
                          final trimmedValue = v.trim();
                          if (trimmedValue.contains(' ')) {
                            return 'Username cannot contain spaces';
                          }
                          if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(trimmedValue)) {
                            return 'Username can only contain letters and numbers';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: _selectedRole == UserRole.storeOwner ? 'Store Name' : 'Full Name',
                          prefixIcon: Icon(_selectedRole == UserRole.storeOwner ? Icons.store : Icons.person_outline),
                        ),
                        validator: (String? v) {
                          if (v == null || v.isEmpty) {
                            return _selectedRole == UserRole.storeOwner 
                                ? 'Please enter your store name' 
                                : 'Please enter your full name';
                          }
                          if (v.length < 2) {
                            return _selectedRole == UserRole.storeOwner 
                                ? 'Store name must be at least 2 characters'
                                : 'Name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (String? v) {
                          if (v == null || v.isEmpty) return 'Please enter your password';
                          if (v.length < 6) return 'Password must be at least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _signUp, child: const Text('Sign Up')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleSelectionDialog extends StatefulWidget {
  @override
  State<_RoleSelectionDialog> createState() => _RoleSelectionDialogState();
}

class _RoleSelectionDialogState extends State<_RoleSelectionDialog> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    _animationController.reverse().then((_) {
      Navigator.of(context).pop(role);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Your Role',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how you want to use the app',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Use single column layout on very small screens (< 350px)
                  if (constraints.maxWidth < 350) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RoleCard(
                          icon: '🏪',
                          title: 'Store Owner',
                          description: 'Manage customers, track credits, and record payments',
                          role: UserRole.storeOwner,
                          color: Colors.blue,
                          onTap: () => _selectRole(UserRole.storeOwner),
                          isFlexible: true,
                        ),
                        const SizedBox(height: 16),
                        _RoleCard(
                          icon: '👤',
                          title: 'Customer',
                          description: 'View your credits and payment history',
                          role: UserRole.customer,
                          color: Colors.green,
                          onTap: () => _selectRole(UserRole.customer),
                          isFlexible: true,
                        ),
                      ],
                    );
                  }
                  // Use row layout with Flexible widgets for responsive design
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: _RoleCard(
                          icon: '🏪',
                          title: 'Store Owner',
                          description: 'Manage customers, track credits, and record payments',
                          role: UserRole.storeOwner,
                          color: Colors.blue,
                          onTap: () => _selectRole(UserRole.storeOwner),
                          isFlexible: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: _RoleCard(
                          icon: '👤',
                          title: 'Customer',
                          description: 'View your credits and payment history',
                          role: UserRole.customer,
                          color: Colors.green,
                          onTap: () => _selectRole(UserRole.customer),
                          isFlexible: false,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final String icon;
  final String title;
  final String description;
  final UserRole role;
  final Color color;
  final VoidCallback onTap;
  final bool isFlexible;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.role,
    required this.color,
    required this.onTap,
    this.isFlexible = false,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: InkWell(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _controller.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.isFlexible ? double.infinity : null,
          constraints: BoxConstraints(
            minWidth: widget.isFlexible ? double.infinity : 140,
            maxWidth: widget.isFlexible ? double.infinity : 180,
            minHeight: 180,
            maxHeight: 220,
          ),
          padding: EdgeInsets.all(widget.isFlexible ? 20 : 18),
          decoration: BoxDecoration(
            color: _isPressed ? widget.color.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isPressed ? widget.color : widget.color.withOpacity(0.3),
              width: _isPressed ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _isPressed 
                    ? widget.color.withOpacity(0.3)
                    : widget.color.withOpacity(0.1),
                blurRadius: _isPressed ? 12 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.icon,
                style: const TextStyle(fontSize: 56),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


