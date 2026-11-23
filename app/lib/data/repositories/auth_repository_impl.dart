import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/network/token_store.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  Future<void> _activate(String? token) async {
    _api.setToken(token);
    await _tokens.write(token);
  }

  Future<AuthSession> _session(Map<String, dynamic> j) async {
    final token = j['token'] as String;
    await _activate(token);
    return AuthSession(token, UserProfile.fromJson(j['user']));
  }

  @override
  Future<bool> restoreSession() async {
    final token = await _tokens.read();
    _api.setToken(token);
    return token != null;
  }

  @override
  Future<AuthSession> login(String email, String password, {String? role}) async =>
      _session(await _api.post('/auth/login', {'email': email, 'password': password, if (role != null) 'role': role}));

  @override
  Future<AuthSession> register(Map<String, dynamic> body) async => _session(await _api.post('/auth/register', body));

  @override
  Future<CurrentUser> currentUser() async {
    final j = await _api.get('/me');
    return CurrentUser(UserProfile.fromJson(j['user']), (j['unread'] ?? 0) as int);
  }

  @override
  Future<UserProfile> updateProfile(Map<String, dynamic> changes) async {
    final j = await _api.patch('/me', changes);
    return UserProfile.fromJson(j['user']);
  }

  @override
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Signing out locally must work even when the server is unreachable.
    }
    await clearSession();
  }

  @override
  Future<void> clearSession() => _activate(null);
}
