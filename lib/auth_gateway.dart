import 'package:supabase_flutter/supabase_flutter.dart';

/// A sign-in problem with a message that's safe to show the rider.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// What the app needs from a sign-in provider. The app uses Supabase;
/// widget tests use a fake (test/fake_auth_gateway.dart).
abstract class AuthGateway {
  String? get currentEmail;
  String? get fullName;
  String? get accessToken;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String fullName, String email, String password);
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  String? get fullName =>
      _auth.currentUser?.userMetadata?['full_name'] as String?;

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw AuthFailure(
        error.message.toLowerCase().contains('invalid login')
            ? 'Invalid email or password.'
            : error.message,
      );
    } on Exception {
      throw const AuthFailure(
        'Could not reach the sign-in server. Check your connection.',
      );
    }
  }

  @override
  Future<void> signUp(String fullName, String email, String password) async {
    final AuthResponse response;
    try {
      response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
    } on AuthException catch (error) {
      throw AuthFailure(
        error.message.toLowerCase().contains('already registered')
            ? 'This account already exists.'
            : error.message,
      );
    } on Exception {
      throw const AuthFailure(
        'Could not reach the sign-in server. Check your connection.',
      );
    }
    if (response.session == null) {
      // Only happens if "Confirm email" is turned on in the dashboard.
      throw const AuthFailure(
        'Check your email to confirm your account, then sign in.',
      );
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// The sign-in provider the whole app uses. Tests replace it with a fake.
AuthGateway authGateway = SupabaseAuthGateway();
