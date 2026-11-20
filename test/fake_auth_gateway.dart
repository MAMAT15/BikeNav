import 'package:bike_nav/auth_gateway.dart';

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.currentEmail, this.fullName});

  @override
  String? currentEmail;

  @override
  String? fullName;

  @override
  String? get accessToken => currentEmail == null ? null : 'test-token';

  @override
  Future<void> signIn(String email, String password) async {
    currentEmail = email;
  }

  @override
  Future<void> signUp(String fullName, String email, String password) async {
    this.fullName = fullName;
    currentEmail = email;
  }

  @override
  Future<void> signOut() async {
    currentEmail = null;
  }
}
