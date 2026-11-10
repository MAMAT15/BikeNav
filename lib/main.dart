import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/add_path.dart';

void main() {
  runApp(const BikeNavApp());
}

class BikeNavApp extends StatelessWidget {
  const BikeNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BikeNav',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2878F0)),
        useMaterial3: true,
      ),
      home: const AppStartGate(),
    );
  }
}

class AppStartGate extends StatefulWidget {
  const AppStartGate({super.key});

  @override
  State<AppStartGate> createState() => _AppStartGateState();
}

class _AppStartGateState extends State<AppStartGate> {
  late final Future<String?> _signedInUser = AuthService.getSignedInUser();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _signedInUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final email = snapshot.data;
        return email == null ? const AuthScreen() : MapScreen(userEmail: email);
      },
    );
  }
}

class BikeProfile {
  final String name;
  final String type;
  final bool isElectric;
  final int? electricClass;

  const BikeProfile({
    required this.name,
    required this.type,
    required this.isElectric,
    this.electricClass,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'type': type,
    'isElectric': isElectric,
    'electricClass': electricClass,
  };

  factory BikeProfile.fromMap(Map<String, dynamic> map) {
    return BikeProfile(
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? '',
      isElectric: map['isElectric'] as bool? ?? false,
      electricClass: map['electricClass'] as int?,
    );
  }
}

class Account {
  final String fullName;
  final String email;
  final String password;
  final BikeProfile? bikeProfile;

  const Account({
    required this.fullName,
    required this.email,
    required this.password,
    this.bikeProfile,
  });

  Map<String, dynamic> toMap() => {
    'fullName': fullName,
    'email': email,
    'password': password,
    if (bikeProfile != null) 'bikeProfile': bikeProfile!.toMap(),
  };

  factory Account.fromMap(Map<String, dynamic> map) {
    final savedBikeProfile = map['bikeProfile'];
    return Account(
      fullName: map['fullName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      password: map['password'] as String? ?? '',
      bikeProfile: savedBikeProfile is Map
          ? BikeProfile.fromMap(Map<String, dynamic>.from(savedBikeProfile))
          : null,
    );
  }
}

class AuthService {
  static const String _accountsKey = 'bike_nav_accounts';
  static const String _currentUserKey = 'bike_nav_current_user';

  static Future<List<Account>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_accountsKey);
    if (data == null) return [];

    final accounts = jsonDecode(data) as List<dynamic>;
    return accounts
        .map((account) => Account.fromMap(account as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAccount(Account account) async {
    final accounts = await loadAccounts();
    accounts.add(account);
    await _saveAccounts(accounts);
  }

  static Future<Account?> findAccount(String email) async {
    final accounts = await loadAccounts();
    for (final account in accounts) {
      if (account.email.toLowerCase() == email.toLowerCase()) return account;
    }
    return null;
  }

  static Future<void> saveBikeProfile(
    String email,
    BikeProfile bikeProfile,
  ) async {
    final accounts = await loadAccounts();
    final accountIndex = accounts.indexWhere(
      (account) => account.email.toLowerCase() == email.toLowerCase(),
    );
    if (accountIndex == -1) {
      throw StateError('Could not find the account for this bike profile.');
    }

    final account = accounts[accountIndex];
    accounts[accountIndex] = Account(
      fullName: account.fullName,
      email: account.email,
      password: account.password,
      bikeProfile: bikeProfile,
    );
    await _saveAccounts(accounts);
  }

  static Future<void> _saveAccounts(List<Account> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _accountsKey,
      jsonEncode(accounts.map((account) => account.toMap()).toList()),
    );
    if (!saved) throw StateError('Could not save account data.');
  }

  static Future<void> saveSignedInUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, email);
  }

  static Future<String?> getSignedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentUserKey);
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }
}

class BikeProfileScreen extends StatelessWidget {
  final String userEmail;

  const BikeProfileScreen({super.key, required this.userEmail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bike profile')),
      body: FutureBuilder<Account?>(
        future: AuthService.findAccount(userEmail),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load bike profile: ${snapshot.error}'),
            );
          }
          final account = snapshot.data;
          if (account == null) {
            return const Center(child: Text('Could not find this account.'));
          }
          return _BikeProfileForm(account: account);
        },
      ),
    );
  }
}

class _BikeProfileForm extends StatefulWidget {
  final Account account;

  const _BikeProfileForm({required this.account});

  @override
  State<_BikeProfileForm> createState() => _BikeProfileFormState();
}

class _BikeProfileFormState extends State<_BikeProfileForm> {
  static const List<String> _urbanBikeTypes = [
    'City / commuter',
    'Folding',
    'Cargo / utility',
    'Hybrid',
    'Road',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String? _selectedType;
  late bool _isElectric;
  late int? _electricClass;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.account.bikeProfile;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _selectedType = profile?.type;
    _isElectric = profile?.isElectric ?? false;
    _electricClass = profile?.electricClass;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await AuthService.saveBikeProfile(
        widget.account.email,
        BikeProfile(
          name: _nameController.text.trim(),
          type: _selectedType!,
          isElectric: _isElectric,
          electricClass: _isElectric ? _electricClass : null,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bike profile saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save bike profile: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Bike name',
              hintText: 'For example, City bike',
              prefixIcon: Icon(Icons.pedal_bike),
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a bike name.'
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: const InputDecoration(
              labelText: 'Bike type',
              prefixIcon: Icon(Icons.directions_bike),
              border: OutlineInputBorder(),
            ),
            items:
                [
                      ..._urbanBikeTypes,
                      if (_selectedType != null &&
                          !_urbanBikeTypes.contains(_selectedType))
                        _selectedType!,
                    ]
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
            onChanged: (type) => setState(() => _selectedType = type),
            validator: (type) => type == null ? 'Choose a bike type.' : null,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('This is an e-bike'),
            value: _isElectric,
            onChanged: (value) {
              setState(() {
                _isElectric = value;
                if (!value) _electricClass = null;
              });
            },
          ),
          if (_isElectric) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _electricClass,
              decoration: const InputDecoration(
                labelText: 'E-bike class',
                prefixIcon: Icon(Icons.electric_bike),
                border: OutlineInputBorder(),
              ),
              items: [1, 2, 3]
                  .map(
                    (bikeClass) => DropdownMenuItem(
                      value: bikeClass,
                      child: Text('Class $bikeClass'),
                    ),
                  )
                  .toList(),
              onChanged: (bikeClass) =>
                  setState(() => _electricClass = bikeClass),
              validator: (bikeClass) =>
                  bikeClass == null ? 'Choose an e-bike class.' : null,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving...' : 'Save bike profile'),
          ),
        ],
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showLogin = true;
  bool _loginPasswordVisible = false;
  bool _signupPasswordVisible = false;
  bool _confirmPasswordVisible = false;

  @override
  void dispose() {
    _nameController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _goToMap(String email) async {
    await AuthService.saveSignedInUser(email);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MapScreen(userEmail: email)),
    );
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final accounts = await AuthService.loadAccounts();
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;

    final valid = accounts.any(
      (account) =>
          account.email.toLowerCase() == email.toLowerCase() &&
          account.password == password,
    );

    if (!valid) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Invalid email or password.')),
      );
      return;
    }

    if (!mounted) return;
    await _goToMap(email);
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = _nameController.text.trim();
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (password != confirm) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    final accounts = await AuthService.loadAccounts();
    final exists = accounts.any(
      (account) => account.email.toLowerCase() == email.toLowerCase(),
    );

    if (exists) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('This account already exists.')),
      );
      return;
    }

    await AuthService.saveAccount(
      Account(fullName: name, email: email, password: password),
    );

    if (!mounted) return;
    await _goToMap(email);
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your email';
    if (!value.contains('@')) return 'Enter a valid email';
    return null;
  }

  Widget _emailField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email',
        prefixIcon: Icon(Icons.email_outlined),
        border: OutlineInputBorder(),
      ),
      validator: _validateEmail,
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool visible,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: onToggleVisibility,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: validator,
    );
  }

  Widget _submitButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.directions_bike,
                    size: 64,
                    color: Color(0xFF2878F0),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _showLogin ? 'Welcome back' : 'Create account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _showLogin
                        ? 'Sign in to continue'
                        : 'Set up your BikeNav profile',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Sign in'),
                            selected: _showLogin,
                            onSelected: (_) =>
                                setState(() => _showLogin = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Create account'),
                            selected: !_showLogin,
                            onSelected: (_) =>
                                setState(() => _showLogin = false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_showLogin) _buildLoginForm() else _buildSignupForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          _emailField(_loginEmailController),
          const SizedBox(height: 16),
          _passwordField(
            controller: _loginPasswordController,
            label: 'Password',
            icon: Icons.lock_outline,
            visible: _loginPasswordVisible,
            onToggleVisibility: () =>
                setState(() => _loginPasswordVisible = !_loginPasswordVisible),
            validator: (value) =>
                value == null || value.isEmpty ? 'Enter your password' : null,
          ),
          const SizedBox(height: 24),
          _submitButton('Sign in', _handleLogin),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter your name'
                : null,
          ),
          const SizedBox(height: 16),
          _emailField(_signupEmailController),
          const SizedBox(height: 16),
          _passwordField(
            controller: _signupPasswordController,
            label: 'Password',
            icon: Icons.lock_outline,
            visible: _signupPasswordVisible,
            onToggleVisibility: () => setState(
              () => _signupPasswordVisible = !_signupPasswordVisible,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter your password';
              if (value.length < 6) return 'Use at least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _passwordField(
            controller: _confirmPasswordController,
            label: 'Confirm password',
            icon: Icons.lock_reset_outlined,
            visible: _confirmPasswordVisible,
            onToggleVisibility: () => setState(
              () => _confirmPasswordVisible = !_confirmPasswordVisible,
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Confirm your password' : null,
          ),
          const SizedBox(height: 24),
          _submitButton('Create account', _handleSignup),
        ],
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  final String userEmail;

  const MapScreen({super.key, required this.userEmail});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _originController = TextEditingController(
    text: 'Current location',
  );
  final TextEditingController _destinationController = TextEditingController();
  Timer? _originSearchTimer;
  Timer? _destinationSearchTimer;
  int _originSearchVersion = 0;
  int _destinationSearchVersion = 0;
  List<PlaceSuggestion> _originSuggestions = const [];
  List<PlaceSuggestion> _destinationSuggestions = const [];
  PlaceSuggestion? _selectedOrigin;
  PlaceSuggestion? _selectedDestination;
  LatLng? _currentLocation;
  LatLng? _routeStart;
  LatLng? _routeEnd;
  List<LatLng> _routePoints = const [];
  List<RouteInstruction> _directions = const [];
  StreamSubscription<Position>? _positionSubscription;
  int _nextDirectionIndex = 0;
  String _routeSummary = 'Search for a destination to plan your ride.';
  String _navigationMessage = '';
  bool _isLoading = false;
  bool _isNavigating = false;
  bool _isRecalculating = false;
  bool _avoidFerries = false;
  bool _showAllDirections = false;
  DateTime? _lastRecalculation;

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _originSearchTimer?.cancel();
    _destinationSearchTimer?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<LatLng> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on location services and try again.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw Exception('Allow location access to use your current position.');
    }

    final position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  }

  Future<void> _useCurrentLocation() async {
    try {
      final location = await _getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _currentLocation = location;
        _originController.text = 'Current location';
        _selectedOrigin = null;
        _originSuggestions = const [];
      });
      _mapController.move(location, 15);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _searchPlaces(String query, {required bool isOrigin}) {
    final trimmedQuery = query.trim();
    final searchVersion = isOrigin
        ? ++_originSearchVersion
        : ++_destinationSearchVersion;
    final timer = isOrigin ? _originSearchTimer : _destinationSearchTimer;
    timer?.cancel();

    setState(() {
      if (isOrigin) {
        _selectedOrigin = null;
        _originSuggestions = const [];
      } else {
        _selectedDestination = null;
        _destinationSuggestions = const [];
      }
    });

    if (trimmedQuery.length < 3) return;
    final nextTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final suggestions = await PlaceService.searchLocations(
          trimmedQuery,
          near: _currentLocation ?? _mapController.camera.center,
        );
        if (!mounted) return;
        if (isOrigin &&
            searchVersion == _originSearchVersion &&
            _originController.text.trim() == trimmedQuery) {
          setState(() => _originSuggestions = suggestions);
        } else if (!isOrigin &&
            searchVersion == _destinationSearchVersion &&
            _destinationController.text.trim() == trimmedQuery) {
          setState(() => _destinationSuggestions = suggestions);
        }
      } catch (_) {
        if (!mounted) return;
        if (isOrigin && searchVersion == _originSearchVersion) {
          setState(() => _originSuggestions = const []);
        } else if (!isOrigin && searchVersion == _destinationSearchVersion) {
          setState(() => _destinationSuggestions = const []);
        }
      }
    });

    if (isOrigin) {
      _originSearchTimer = nextTimer;
    } else {
      _destinationSearchTimer = nextTimer;
    }
  }

  void _selectPlace(PlaceSuggestion suggestion, {required bool isOrigin}) {
    setState(() {
      if (isOrigin) {
        _originController.text = suggestion.label;
        _selectedOrigin = suggestion;
        _originSuggestions = const [];
      } else {
        _destinationController.text = suggestion.label;
        _selectedDestination = suggestion;
        _destinationSuggestions = const [];
      }
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _planRoute() async {
    final origin = _originController.text.trim();
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a destination first.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _routeSummary = 'Finding a bike route...';
      _directions = const [];
    });

    try {
      final start = origin.toLowerCase() == 'current location'
          ? (_currentLocation ?? await _getCurrentLocation())
          : (_selectedOrigin?.label == origin
                ? _selectedOrigin!.point
                : await PlaceService.findLocation(
                    origin,
                    near: _currentLocation ?? _mapController.camera.center,
                  ));
      final end = _selectedDestination?.label == destination
          ? _selectedDestination!.point
          : await PlaceService.findLocation(
              destination,
              near: _currentLocation ?? _mapController.camera.center,
            );
      final route = await RouteService.fetchBikeRoute(
        start: start,
        end: end,
        avoidFerries: _avoidFerries,
      );

      if (!mounted) return;
      setState(() {
        _routeStart = start;
        _routeEnd = end;
        _routePoints = route.points;
        _directions = route.directions;
        _routeSummary = route.summary;
        _nextDirectionIndex = 0;
        _showAllDirections = false;
        _navigationMessage = '';
        _isLoading = false;
      });

      _mapController.move(
        LatLng(
          (start.latitude + end.latitude) / 2,
          (start.longitude + end.longitude) / 2,
        ),
        13,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _routeSummary = error.toString().replaceFirst('Exception: ', '');
        _routePoints = const [];
        _routeStart = null;
        _routeEnd = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _startNavigation() async {
    if (_routePoints.isEmpty || _routeEnd == null) return;

    try {
      final location = await _getCurrentLocation();
      if (!mounted) return;
      await _positionSubscription?.cancel();
      setState(() {
        _currentLocation = location;
        _isNavigating = true;
        _navigationMessage = 'Following your location';
        _nextDirectionIndex = 0;
      });
      _mapController.move(location, 16);
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            _handlePosition,
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                _isNavigating = false;
                _navigationMessage =
                    'Location updates stopped. Check location permission.';
              });
            },
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _stopNavigation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    setState(() {
      _isNavigating = false;
      _isRecalculating = false;
      _navigationMessage = 'Navigation paused';
    });
  }

  void _handlePosition(Position position) {
    if (!mounted || !_isNavigating) return;
    final location = LatLng(position.latitude, position.longitude);
    _updateNextDirection(location);
    setState(() => _currentLocation = location);
    _mapController.move(location, 16);

    final now = DateTime.now();
    final lastRecalculation = _lastRecalculation;
    final canRecalculate =
        lastRecalculation == null ||
        now.difference(lastRecalculation) >= const Duration(seconds: 12);
    if (!_isRecalculating &&
        canRecalculate &&
        _routePoints.isNotEmpty &&
        _distanceFromRoute(location) > 50) {
      _lastRecalculation = now;
      _recalculateRoute(location);
    }
  }

  void _updateNextDirection(LatLng location) {
    while (_nextDirectionIndex < _directions.length - 1) {
      final point = _directions[_nextDirectionIndex].endLocation;
      if (point == null ||
          const Distance().as(LengthUnit.Meter, location, point) > 25) {
        break;
      }
      _nextDirectionIndex++;
    }
  }

  double _distanceFromRoute(LatLng location) {
    final distance = const Distance();
    var closest = double.infinity;
    for (final point in _routePoints) {
      final meters = distance.as(LengthUnit.Meter, location, point);
      if (meters < closest) closest = meters;
    }
    return closest;
  }

  Future<void> _recalculateRoute(LatLng location) async {
    final destination = _routeEnd;
    if (destination == null) return;
    setState(() {
      _isRecalculating = true;
      _navigationMessage = 'Recalculating route...';
    });

    RouteResult? result;
    String? errorMessage;
    try {
      result = await RouteService.fetchBikeRoute(
        start: location,
        end: destination,
        avoidFerries: _avoidFerries,
      );
    } catch (_) {
      errorMessage = 'Could not update route. Staying on the current route.';
    }

    if (!mounted) return;
    setState(() {
      _isRecalculating = false;
      if (result != null && _isNavigating) {
        _routeStart = location;
        _routePoints = result.points;
        _directions = result.directions;
        _routeSummary = result.summary;
        _nextDirectionIndex = 0;
        _showAllDirections = false;
        _navigationMessage = 'Route updated';
      } else if (errorMessage != null) {
        _navigationMessage = errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeInstruction = _directions.isNotEmpty
        ? _directions[_nextDirectionIndex.clamp(0, _directions.length - 1)]
        : null;
    final distanceToNextStep =
        _currentLocation != null && activeInstruction?.endLocation != null
        ? const Distance().as(
            LengthUnit.Meter,
            _currentLocation!,
            activeInstruction!.endLocation!,
          )
        : null;
    final markers = <Marker>[];
    if (_routeStart != null) {
      markers.add(
        Marker(
          point: _routeStart!,
          width: 36,
          height: 36,
          child: const Icon(
            Icons.trip_origin,
            color: Color(0xFF168A65),
            size: 28,
          ),
        ),
      );
    }
    if (_routeEnd != null) {
      markers.add(
        Marker(
          point: _routeEnd!,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFFDB4437),
            size: 38,
          ),
        ),
      );
    }
    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(40.7128, -74.0060),
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bike_nav',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 6,
                      color: const Color(0xFF4285F4),
                    ),
                  ],
                ),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                elevation: 5,
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_bike,
                            color: Color(0xFF4285F4),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'BikeNav',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            widget.userEmail.split('@').first,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Account',
                            onSelected: (action) async {
                              if (action == 'add_path') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AddPathScreen(),
                                  ),
                                );
                                return;
                              }
                              if (action == 'bike_profile') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => BikeProfileScreen(
                                      userEmail: widget.userEmail,
                                    ),
                                  ),
                                );
                                return;
                              }
                              final navigator = Navigator.of(context);
                              await AuthService.signOut();
                              if (!mounted) return;
                              navigator.pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const AuthScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'add_path',
                                child: ListTile(
                                  leading: Icon(Icons.add_road),
                                  title: Text('Add Path'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'bike_profile',
                                child: ListTile(
                                  leading: Icon(Icons.pedal_bike),
                                  title: Text('Bike profile'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'log_out',
                                child: ListTile(
                                  leading: Icon(Icons.logout),
                                  title: Text('Log out'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.account_circle_outlined),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      Row(
                        children: [
                          const Icon(
                            Icons.trip_origin,
                            color: Color(0xFF168A65),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _originController,
                              textInputAction: TextInputAction.next,
                              onChanged: (value) =>
                                  _searchPlaces(value, isOrigin: true),
                              decoration: const InputDecoration(
                                hintText: 'Starting point',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Use current location',
                            onPressed: _useCurrentLocation,
                            icon: const Icon(Icons.my_location),
                          ),
                        ],
                      ),
                      if (_originSuggestions.isNotEmpty)
                        _buildSuggestionList(
                          _originSuggestions,
                          isOrigin: true,
                        ),
                      const Divider(height: 1, indent: 30),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Color(0xFFDB4437),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _destinationController,
                              textInputAction: TextInputAction.search,
                              onChanged: (value) =>
                                  _searchPlaces(value, isOrigin: false),
                              onSubmitted: (_) => _planRoute(),
                              decoration: const InputDecoration(
                                hintText: 'Where to?',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Plan bike route',
                            onPressed: _isLoading ? null : _planRoute,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search),
                          ),
                        ],
                      ),
                      if (_destinationSuggestions.isNotEmpty)
                        _buildSuggestionList(
                          _destinationSuggestions,
                          isOrigin: false,
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              avatar: const Icon(
                                Icons.directions_boat,
                                size: 18,
                              ),
                              label: const Text('Avoid ferries'),
                              selected: _avoidFerries,
                              onSelected: _isNavigating
                                  ? null
                                  : (value) {
                                      setState(() => _avoidFerries = value);
                                      if (_destinationController.text
                                          .trim()
                                          .isNotEmpty) {
                                        _planRoute();
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 230,
            child: FloatingActionButton.small(
              heroTag: 'current-location',
              tooltip: 'Center on current location',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF343A40),
              onPressed: _useCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: _showAllDirections
                      ? MediaQuery.sizeOf(context).height * 0.65
                      : 220,
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -3),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 34,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_bike,
                            color: Color(0xFF4285F4),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _routeSummary,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      if (_navigationMessage.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _navigationMessage,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: _isRecalculating
                                      ? const Color(0xFFB05A00)
                                      : Colors.black54,
                                ),
                          ),
                        ),
                      ],
                      if (_isNavigating && activeInstruction != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.turn_right,
                                color: Color(0xFF1A73E8),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeInstruction.text,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (distanceToNextStep != null)
                                      Text(
                                        'Next step in ${RouteService.formatDistance(distanceToNextStep)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_routePoints.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isNavigating
                                ? _stopNavigation
                                : _startNavigation,
                            icon: Icon(
                              _isNavigating ? Icons.stop : Icons.navigation,
                            ),
                            label: Text(
                              _isNavigating
                                  ? 'Stop navigation'
                                  : 'Start navigation',
                            ),
                          ),
                        ),
                      ],
                      if (_directions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        if (_directions.length - _nextDirectionIndex > 4)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => _showAllDirections = !_showAllDirections,
                              ),
                              icon: Icon(
                                _showAllDirections
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                              label: Text(
                                _showAllDirections
                                    ? 'Show fewer directions'
                                    : 'Show all ${_directions.length - _nextDirectionIndex} directions',
                              ),
                            ),
                          ),
                        for (
                          var index = _nextDirectionIndex;
                          index < _directions.length &&
                              (_showAllDirections ||
                                  index < _nextDirectionIndex + 4);
                          index++
                        )
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Row(
                              children: [
                                Icon(
                                  index == _nextDirectionIndex
                                      ? Icons.arrow_forward
                                      : Icons.turn_right,
                                  size: 17,
                                  color: index == _nextDirectionIndex
                                      ? const Color(0xFF1A73E8)
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _directions[index].text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: index == _nextDirectionIndex
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                Text(
                                  RouteService.formatDistance(
                                    _directions[index].distanceMeters,
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Map data: OpenStreetMap contributors',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionList(
    List<PlaceSuggestion> suggestions, {
    required bool isOrigin,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 38),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ListTile(
            dense: true,
            leading: Icon(
              suggestion.category == 'Train station'
                  ? Icons.train_outlined
                  : suggestion.category == 'Ferry terminal'
                  ? Icons.directions_boat_outlined
                  : Icons.place_outlined,
              size: 20,
            ),
            title: Text(
              suggestion.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: suggestion.detail.isEmpty
                ? null
                : Text(
                    suggestion.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () => _selectPlace(suggestion, isOrigin: isOrigin),
          );
        },
      ),
    );
  }
}

class PlaceSuggestion {
  final String label;
  final String detail;
  final String category;
  final LatLng point;

  const PlaceSuggestion({
    required this.label,
    required this.detail,
    required this.category,
    required this.point,
  });
}

class PlaceService {
  static Uri searchUri(String query, {LatLng? near}) {
    return Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '8',
      if (near != null) 'lat': near.latitude.toString(),
      if (near != null) 'lon': near.longitude.toString(),
    });
  }

  static Future<List<PlaceSuggestion>> searchLocations(
    String query, {
    LatLng? near,
  }) async {
    final uri = searchUri(query, near: near);
    final response = await http.get(
      uri,
      headers: const {'User-Agent': 'BikeNav/1.0'},
    );
    if (response.statusCode != 200) {
      throw Exception('Place search is unavailable. Try again shortly.');
    }

    return parseSuggestions(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static List<PlaceSuggestion> parseSuggestions(Map<String, dynamic> body) {
    final features = body['features'] as List<dynamic>? ?? const [];
    return features.map((feature) {
      final item = feature as Map<String, dynamic>;
      final properties =
          item['properties'] as Map<String, dynamic>? ?? const {};
      final geometry = item['geometry'] as Map<String, dynamic>? ?? const {};
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final name =
          (properties['name'] as String? ??
                  properties['street'] as String? ??
                  properties['city'] as String? ??
                  properties['locality'] as String? ??
                  'Place')
              .trim();
      final details = [
        if (properties['street'] is String && properties['street'] != name)
          properties['street'] as String,
        if (properties['city'] is String) properties['city'] as String,
        if (properties['state'] is String) properties['state'] as String,
        if (properties['country'] is String) properties['country'] as String,
      ];
      final osmKey = properties['osm_key'] as String? ?? '';
      final osmValue = properties['osm_value'] as String? ?? '';
      final category =
          osmKey == 'railway' &&
              (osmValue == 'station' ||
                  osmValue == 'halt' ||
                  osmValue == 'tram_stop')
          ? 'Train station'
          : osmValue == 'ferry_terminal'
          ? 'Ferry terminal'
          : (properties['type'] as String? ?? 'Place');

      return PlaceSuggestion(
        label: name,
        detail: [
          ...details,
          category == 'Place' ? null : category,
        ].whereType<String>().join(', '),
        category: category,
        point: LatLng(
          (coordinates[1] as num).toDouble(),
          (coordinates[0] as num).toDouble(),
        ),
      );
    }).toList();
  }

  static Future<LatLng> findLocation(String query, {LatLng? near}) async {
    final results = await searchLocations(query, near: near);
    if (results.isEmpty) {
      throw Exception(
        'Could not find "$query". Try a nearby street or landmark.',
      );
    }
    return results.first.point;
  }
}

class RouteService {
  static Future<RouteResult> fetchBikeRoute({
    required LatLng start,
    required LatLng end,
    bool avoidFerries = false,
  }) async {
    final response = await http.post(
      Uri.https('valhalla1.openstreetmap.de', '/route'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        requestBody(start: start, end: end, avoidFerries: avoidFerries),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Bike route request failed (${response.statusCode}).');
    }

    return parseValhallaResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
      avoidFerries: avoidFerries,
    );
  }

  static Map<String, dynamic> requestBody({
    required LatLng start,
    required LatLng end,
    required bool avoidFerries,
  }) {
    return {
      'locations': [
        {'lat': start.latitude, 'lon': start.longitude},
        {'lat': end.latitude, 'lon': end.longitude},
      ],
      'costing': 'bicycle',
      if (avoidFerries)
        'costing_options': {
          'bicycle': {'use_ferry': 0},
        },
      'units': 'kilometers',
      'shape_format': 'polyline6',
    };
  }

  static RouteResult parseValhallaResponse(
    Map<String, dynamic> body, {
    bool avoidFerries = false,
  }) {
    final trip = body['trip'] as Map<String, dynamic>? ?? const {};
    final summary = trip['summary'] as Map<String, dynamic>? ?? const {};
    if (avoidFerries && summary['has_ferry'] == true) {
      throw Exception('No ferry-free bike route is available for this trip.');
    }
    final legs = trip['legs'] as List<dynamic>? ?? const [];
    if (legs.isEmpty) throw Exception('No bike route was returned.');

    final points = <LatLng>[];
    final directions = <RouteInstruction>[];
    for (final leg in legs) {
      final legMap = leg as Map<String, dynamic>;
      final shape = legMap['shape'] as String? ?? '';
      final coordinates = decodePolyline(shape, accuracyExponent: 6);
      final legPoints = coordinates
          .map(
            (coordinate) =>
                LatLng(coordinate[0].toDouble(), coordinate[1].toDouble()),
          )
          .toList();
      points.addAll(points.isEmpty ? legPoints : legPoints.skip(1));

      LatLng? shapePoint(int? index) {
        if (index == null || index < 0 || index >= legPoints.length) {
          return null;
        }
        return legPoints[index];
      }

      final maneuvers = legMap['maneuvers'] as List<dynamic>? ?? const [];
      for (final item in maneuvers) {
        final maneuver = item as Map<String, dynamic>;
        final beginShapeIndex = maneuver['begin_shape_index'] as int?;
        final endShapeIndex = maneuver['end_shape_index'] as int?;
        directions.add(
          RouteInstruction(
            text:
                maneuver['instruction'] as String? ??
                'Continue along the route',
            distanceMeters: (maneuver['length'] as num? ?? 0).toDouble() * 1000,
            beginLocation: shapePoint(beginShapeIndex),
            endLocation: shapePoint(endShapeIndex),
          ),
        );
      }
    }

    if (directions.isEmpty) {
      directions.add(
        const RouteInstruction(
          text: 'Follow the highlighted bike route to your destination.',
          distanceMeters: 0,
        ),
      );
    }

    final distanceMeters = (summary['length'] as num? ?? 0).toDouble() * 1000;
    final durationSeconds = (summary['time'] as num? ?? 0).toDouble();
    return RouteResult(
      points: points,
      summary:
          '${formatDistance(distanceMeters)} · about ${formatDuration(durationSeconds)}',
      directions: directions,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours hr'
        : '$hours hr $remainingMinutes min';
  }
}

class RouteInstruction {
  final String text;
  final double distanceMeters;
  final LatLng? beginLocation;
  final LatLng? endLocation;

  const RouteInstruction({
    required this.text,
    required this.distanceMeters,
    this.beginLocation,
    this.endLocation,
  });
}

class RouteResult {
  final List<LatLng> points;
  final String summary;
  final List<RouteInstruction> directions;
  final double distanceMeters;
  final double durationSeconds;

  const RouteResult({
    required this.points,
    required this.summary,
    required this.directions,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}
