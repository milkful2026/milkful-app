import 'package:flutter/material.dart';

/// Minimal placeholder — MA-1's spec explicitly puts a real Home (catalog,
/// cart, subscriptions) out of scope, and MA-21 (not built yet) is what
/// adds the role-aware indicator and logout action on top of this. Exists
/// only as somewhere for the registration flow to land.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text("You're signed in.")),
    );
  }
}
