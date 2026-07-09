import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/config/supabase_config.dart';
import 'lib/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase identical to your app
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  final authService = AuthService(Supabase.instance.client);

  try {
    // ----👉 CHANGE YOUR DESIRED USERNAME AND PASSWORD HERE 👈----
    final username = 'admin';
    final password = 'password123';
    
    print('Creating user: $username...');
    final response = await authService.signUp(username, password);
    
    if (response.user != null) {
      print('✅ SUCCESS! User created successfully.');
      print('You can now log into the app using:');
      print('Username: $username');
      print('Password: $password');
    } else {
      print('⚠️ User creation returned no user, but no error was thrown.');
    }
  } catch (e) {
    print('❌ FAILED to create user: $e');
  }
}
