import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert'; // utf8, json
import 'dart:typed_data'; // Uint8List
import 'dart:io'; // 파일 시스템

// 패키지들
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();

  // 🔥 [핵심 변경 1] 시스템 바를 투명하게 만들고 Edge-to-Edge 모드 활성화
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent, // 하단 바 투명
    systemNavigationBarIconBrightness: Brightness.light, // 아이콘 흰색
    statusBarColor: Colors.transparent, // 상단 바 투명
  ));
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Master',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFBB86FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ==========================================
// 1. 스플래시 스크린
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  String _authStatus = "Initializing...";

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    bool canCheckBiometrics = false;
    try {
      canCheckBiometrics = await auth.canCheckBiometrics;
    } catch (e) {
      print("Biometric check error: $e");
    }

    if (!canCheckBiometrics) {
      _navigateToHome();
      return;
    }

    _authenticate();
  }

  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      setState(() => _authStatus = "Please authenticate...");
      
      authenticated = await auth.authenticate(
        localizedReason: 'Scan fingerprint to access SSH Master',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (e) {
      print(e);
      setState(() => _authStatus = "Error: ${e.message}");
      return;
    }

    if (!mounted) return;

    if (authenticated) {
      setState(() => _authStatus = "Access Granted");
      _navigateToHome();
    } else {
      setState(() => _authStatus = "Authentication Failed\nTap to retry");
    }
  }

  void _navigateToHome() {
    Timer(const Duration(milliseconds: 500), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ServerListPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InkWell(
        onTap: () => _authenticate(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.fingerprint, size: 60, color: Color(0xFFBB86FC)),
              ),
              const SizedBox(height: 20),
              const Text(
                "SSH MASTER",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2.0, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                _authStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. 서버 목록 화면
// ==========================================
class ServerListPage extends StatefulWidget {
  const ServerListPage({super.key});

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  List<Map<String, String>> _allServers = [];
  List<Map<String, String>> _filteredServers = [];
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadServers();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', 
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          print('Failed to load a banner ad: ${err.message}');
          _isBannerAdReady = false;
          ad.dispose();
        },
      ),
    );
    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? serverString = prefs.getString('saved_servers');
    
    if (serverString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(serverString);
        setState(() {
          _allServers = decoded.map((e) => Map<String, String>.from(e)).toList();
          _filteredServers = _allServers;
        });
      } catch (e) {
        print("Error loading servers: $e");
      }
    }
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_allServers);
    await prefs.setString('saved_servers', encoded);
  }

  void _runFilter(String keyword) {
    List<Map<String, String>> results = [];
    if (keyword.isEmpty) {
      results = _allServers;
    } else {
      results = _allServers
          .where((server) => server["name"]!.toLowerCase().contains(keyword.toLowerCase()))
          .toList();
    }
    setState(() {
      _filteredServers = results;
    });
  }

  void _navigateToAddPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SSHConnectPage()), 
    );

    if (result != null && result is Map<String, String>) {
      setState(() {
        _allServers.add(result);
        _filteredServers = _allServers;
      });
      _saveServers();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'${result['name']}' added!")));
    }
  }

  void _editServer(int index) async {
    final serverToEdit = _filteredServers[index];
    final originalIndex = _allServers.indexOf(serverToEdit);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SSHConnectPage(initialData: serverToEdit),
      ),
    );

    if (result != null && result is Map<String, String>) {
      setState(() {
        _allServers[originalIndex] = result; 
        _filteredServers = _allServers;      
      });
      _saveServers();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Updated successfully!")));
    }
  }

  void _deleteServer(int index) {
    final serverToDelete = _filteredServers[index];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Server"),
        content: Text("Are you sure you want to delete '${serverToDelete['name']}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _allServers.remove(serverToDelete);
                _filteredServers = _allServers;
              });
              _saveServers();
              Navigator.of(ctx).pop(); 
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted.")));
            },
            child: const Text("Delete", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        // 🔥 [핵심] BottomSheet 하단 여백 처리
        // 시스템 바 높이만큼 패딩을 주어 가려지지 않게 함
        return Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_shared, color: Colors.orangeAccent),
                title: const Text("SFTP File Manager", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SFTPPage(serverInfo: _filteredServers[index]),
                    ),
                  );
                },
              ),
              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blueAccent),
                title: const Text("Edit Info", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _editServer(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text("Delete", style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  _deleteServer(index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                onChanged: (value) => _runFilter(value),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
                autofocus: true,
              )
            : const Text("Server List", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_allServers.isNotEmpty)
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                    _filteredServers = _allServers;
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFFBB86FC)),
              onPressed: _navigateToAddPage,
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _filteredServers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(_isSearching ? Icons.search_off : Icons.dns_outlined, size: 50, color: Colors.grey),
                                const SizedBox(height: 10),
                                Text(
                                  _isSearching
                                      ? "No results found."
                                      : "No servers saved.\nTap + to add a new connection.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            // 리스트 마지막 아이템이 광고나 하단바에 가려지지 않도록 여유 패딩 추가
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: _filteredServers.length,
                            itemBuilder: (context, index) {
                              final server = _filteredServers[index];
                              return Card(
                                color: const Color(0xFF1E1E1E),
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2C2C2C),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.dns, color: Colors.white70),
                                  ),
                                  title: Text(server['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                  subtitle: Text(server['host']!, style: const TextStyle(fontFamily: 'Courier', color: Colors.grey, fontSize: 12)),
                                  
                                  trailing: IconButton(
                                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                                    onPressed: () {
                                      _showOptions(index); 
                                    },
                                  ),

                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TerminalPage(serverInfo: server),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          
          if (_isBannerAdReady)
            // 🔥 [핵심] 광고는 정책상 클릭 가능한 영역과 겹치면 안 되므로 SafeArea를 유지하는 게 안전함
            // 하지만 배경색과 일체감을 위해 SafeArea(top: false) 사용
            SafeArea(
              top: false,
              child: Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. 접속 정보 입력 화면
// ==========================================
class SSHConnectPage extends StatefulWidget {
  final Map<String, String>? initialData;

  const SSHConnectPage({super.key, this.initialData});

  @override
  State<SSHConnectPage> createState() => _SSHConnectPageState();
}

class _SSHConnectPageState extends State<SSHConnectPage> {
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _userController;
  late TextEditingController _passwordController;

  bool _useKeyFile = false;
  String? _keyContent;
  String? _keyFileName;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    _nameController = TextEditingController(text: data?['name'] ?? '');
    _hostController = TextEditingController(text: data?['ip'] ?? '');
    _portController = TextEditingController(text: data?['port'] ?? '22');
    _userController = TextEditingController(text: data?['user'] ?? '');
    _passwordController = TextEditingController(text: data?['password'] ?? '');
    
    if (data != null && data['key'] != null && data['key']!.isNotEmpty) {
      _useKeyFile = true;
      _keyContent = data['key'];
      _keyFileName = "Previously saved key";
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        
        setState(() {
          _keyContent = content;
          _keyFileName = result.files.single.name;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Key selected: $_keyFileName")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking file: $e")),
      );
    }
  }

  void _saveAndConnect() {
    if (_nameController.text.isEmpty || _hostController.text.isEmpty || _userController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill in Name, Host, and User.")));
      return;
    }

    if (_useKeyFile && (_keyContent == null || _keyContent!.isEmpty)) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a Private Key file.")));
       return;
    }

    final newServerData = {
      "name": _nameController.text,
      "host": "${_userController.text}@${_hostController.text}:${_portController.text}",
      "ip": _hostController.text,
      "port": _portController.text,
      "user": _userController.text,
      "password": _useKeyFile ? "" : _passwordController.text,
      "key": _useKeyFile ? _keyContent! : "",
    };

    Navigator.pop(context, newServerData);
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.initialData != null;
    
    // 🔥 [핵심] 하단 내비게이션 바 높이만큼 패딩을 계산하여 동적으로 적용
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(title: Text(isEditMode ? "Edit Connection" : "New Connection")),
      // SafeArea 제거: 배경색이 바닥까지 꽉 차게 하기 위함
      body: SingleChildScrollView(
        child: Padding(
          // 마지막 요소 아래에 시스템 바 높이만큼 패딩을 추가
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(controller: _nameController, label: "Alias (Name)", icon: Icons.label_outline),
              const SizedBox(height: 15),
              Row(children: [
                Expanded(flex: 2, child: _buildTextField(controller: _hostController, label: "Host IP", icon: Icons.dns)),
                const SizedBox(width: 10),
                Expanded(flex: 1, child: _buildTextField(controller: _portController, label: "Port", icon: Icons.numbers, isNumber: true)),
              ]),
              const SizedBox(height: 30),
              _buildTextField(controller: _userController, label: "Username", icon: Icons.person_outline),
              
              const SizedBox(height: 30),
              const Text("Authentication Method", style: TextStyle(color: Color(0xFFBB86FC), fontWeight: FontWeight.bold)),
              
              SwitchListTile(
                title: const Text("Use Private Key (PEM)", style: TextStyle(color: Colors.white)),
                subtitle: const Text("Toggle off to use Password", style: TextStyle(color: Colors.grey, fontSize: 12)),
                value: _useKeyFile,
                activeColor: const Color(0xFFBB86FC),
                onChanged: (bool value) {
                  setState(() {
                    _useKeyFile = value;
                  });
                },
              ),
    
              const SizedBox(height: 10),
    
              if (_useKeyFile) 
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickKeyFile,
                        icon: const Icon(Icons.file_open),
                        label: const Text("Pick Private Key File"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                        ),
                      ),
                      if (_keyFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            "Selected: $_keyFileName",
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                )
              else 
                _buildTextField(controller: _passwordController, label: "Password", icon: Icons.lock_outline, isPassword: true),
    
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _saveAndConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFBB86FC),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEditMode ? "Save Changes" : "Connect & Save", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

// ==========================================
// 4. 터미널 접속 화면
// ==========================================
class TerminalPage extends StatefulWidget {
  final Map<String, String> serverInfo;

  const TerminalPage({super.key, required this.serverInfo});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal terminal;
  SSHClient? client;
  SSHSession? session;
  String statusMessage = "Initializing...";
  
  InterstitialAd? _interstitialAd;

  final List<Map<String, String>> snippets = [
    {'label': 'ESC', 'cmd': '\x1b'},
    {'label': 'TAB', 'cmd': '\t'},
    {'label': 'Ctrl+C', 'cmd': '\x03'},
    {'label': 'Ctrl+Z', 'cmd': '\x1a'},
    {'label': 'Home', 'cmd': '\x1b[1~'},
    {'label': 'End', 'cmd': '\x1b[4~'},
    {'label': 'PgUp', 'cmd': '\x1b[5~'},
    {'label': 'PgDn', 'cmd': '\x1b[6~'},
    {'label': '⬆', 'cmd': '\x1b[A'},
    {'label': '⬇', 'cmd': '\x1b[B'},
    {'label': '⬅', 'cmd': '\x1b[D'},
    {'label': '➡', 'cmd': '\x1b[C'},
    {'label': 'ls -la', 'cmd': 'ls -la\r'},
    {'label': 'top', 'cmd': 'top\r'},
    {'label': 'exit', 'cmd': 'exit\r'},
  ];

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    _connectSSH();
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', 
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _closeConnectionAndPop();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _closeConnectionAndPop();
            },
          );
        },
        onAdFailedToLoad: (err) {
          print('Failed to load an interstitial ad: ${err.message}');
        },
      ),
    );
  }

  void _closeConnectionAndPop() {
    client?.close();
    if (mounted) Navigator.pop(context);
  }

  void _handleExit() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      _closeConnectionAndPop();
    }
  }

  Future<void> _connectSSH() async {
    setState(() => statusMessage = "Connecting to ${widget.serverInfo['ip']}...");
    terminal.write('Connecting to ${widget.serverInfo['host']}...\r\n');

    try {
      final socket = await SSHSocket.connect(
        widget.serverInfo['ip']!,
        int.parse(widget.serverInfo['port']!),
        timeout: const Duration(seconds: 10),
      );

      setState(() => statusMessage = "Authenticating...");
      terminal.write('Connected. Authenticating...\r\n');

      if (widget.serverInfo['key'] != null && widget.serverInfo['key']!.isNotEmpty) {
        terminal.write('Using Key Authentication...\r\n');
        client = SSHClient(
          socket,
          username: widget.serverInfo['user']!,
          identities: SSHKeyPair.fromPem(widget.serverInfo['key']!), 
        );
      } else {
        client = SSHClient(
          socket,
          username: widget.serverInfo['user']!,
          onPasswordRequest: () => widget.serverInfo['password']!,
        );
      }

      await client!.authenticated;
      setState(() => statusMessage = "Connected");
      terminal.write('Access Granted.\r\n\r\n');

      session = await client!.shell(
        pty: SSHPtyConfig(width: 80, height: 24),
      );
      
      session!.stdout.listen((data) {
        terminal.write(String.fromCharCodes(data));
      });
      
      session!.stderr.listen((data) {
        terminal.write(String.fromCharCodes(data));
      });

      terminal.onOutput = (data) {
        session?.write(Uint8List.fromList(utf8.encode(data)));
      };

    } catch (e) {
      setState(() => statusMessage = "Connection Failed");
      terminal.write('\r\nError: $e\r\n');
    }
  }

  void _sendSnippet(String cmd) {
    if (session != null) {
      session!.write(Uint8List.fromList(utf8.encode(cmd)));
    }
  }

  @override
  void dispose() {
    client?.close();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 [핵심] 하단 바 높이 가져오기
    double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.serverInfo['name']!, style: const TextStyle(fontSize: 16)),
            Text(statusMessage, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            onPressed: _handleExit,
          ),
        ],
      ),
      // SafeArea 대신 Column 사용
      body: Column(
        children: [
          Expanded(
            child: TerminalView(
              terminal,
              autofocus: true,
              textStyle: const TerminalStyle(
                fontFamily: 'Courier',
                fontSize: 14,
              ),
            ),
          ),
          Container(
            // 높이 = 원래높이(48) + 시스템 바 높이
            height: 48 + bottomPadding, 
            color: const Color(0xFF2C2C2C), // 배경색은 시스템 바 뒤까지 칠해짐
            // 실제 버튼 목록은 시스템 바 위로 밀어올림
            padding: EdgeInsets.only(bottom: bottomPadding), 
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: snippets.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ElevatedButton(
                    onPressed: () => _sendSnippet(snippets[index]['cmd']!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF444444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(40, 0),
                    ),
                    child: Text(
                      snippets[index]['label']!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. SFTP 파일 관리자 화면
// ==========================================
class SFTPPage extends StatefulWidget {
  final Map<String, String> serverInfo;

  const SFTPPage({super.key, required this.serverInfo});

  @override
  State<SFTPPage> createState() => _SFTPPageState();
}

class _SFTPPageState extends State<SFTPPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  SSHClient? client;
  SftpClient? sftp;
  
  bool isLoading = false;
  String statusMessage = "Connecting...";
  
  String localPath = "";
  String remotePath = ".";
  
  List<FileSystemEntity> localFiles = [];
  List<SftpName> remoteFiles = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initSFTP();
  }

  Future<void> _initSFTP() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      localPath = dir.path;
      _refreshLocal();

      final socket = await SSHSocket.connect(
        widget.serverInfo['ip']!,
        int.parse(widget.serverInfo['port']!),
        timeout: const Duration(seconds: 10),
      );

      if (widget.serverInfo['key'] != null && widget.serverInfo['key']!.isNotEmpty) {
        client = SSHClient(
          socket,
          username: widget.serverInfo['user']!,
          identities: SSHKeyPair.fromPem(widget.serverInfo['key']!),
        );
      } else {
        client = SSHClient(
          socket,
          username: widget.serverInfo['user']!,
          onPasswordRequest: () => widget.serverInfo['password']!,
        );
      }

      await client!.authenticated;
      sftp = await client!.sftp();
      
      _refreshRemote();

      if (mounted) setState(() => statusMessage = "Connected");

    } catch (e) {
      if (mounted) setState(() => statusMessage = "Error: $e");
    }
  }

  void _refreshLocal() {
    setState(() {
      try {
        localFiles = Directory(localPath).listSync();
        localFiles.sort((a, b) {
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return 0;
        });
      } catch (e) {
        print("Error listing local files: $e");
      }
    });
  }

  Future<void> _refreshRemote() async {
    if (sftp == null) return;
    setState(() => isLoading = true);
    try {
      final files = await sftp!.listdir(remotePath);
      
      files.sort((a, b) {
        final aIsDir = a.attr.isDirectory;
        final bIsDir = b.attr.isDirectory;
        
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return 0;
      });
      
      if (mounted) {
        setState(() {
          remoteFiles = files;
          isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _downloadFile(SftpName remoteFile) async {
    if (sftp == null) return;
    setState(() => isLoading = true);
    try {
      final remoteFilePath = p.join(remotePath, remoteFile.filename);
      final localFilePath = p.join(localPath, remoteFile.filename);

      final remoteHandle = await sftp!.open(remoteFilePath);
      final stream = remoteHandle.read(); 
      
      final localFile = File(localFilePath);
      final sink = localFile.openWrite();

      await stream.cast<List<int>>().pipe(sink); 
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Complete!")));
        _refreshLocal();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download Failed: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _uploadFile(File localFile) async {
    if (sftp == null) return;
    setState(() => isLoading = true);
    try {
      final fileName = p.basename(localFile.path);
      final remoteFilePath = p.join(remotePath, fileName);

      final remoteFile = await sftp!.open(
        remoteFilePath, 
        mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate
      );
      
      await remoteFile.write(localFile.openRead().cast()); 
      await remoteFile.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload Complete!")));
        _refreshRemote();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _navigateLocal(Directory dir) {
    setState(() {
      localPath = dir.path;
      _refreshLocal();
    });
  }

  void _navigateRemote(String folderName) {
    setState(() {
      remotePath = p.join(remotePath, folderName);
      _refreshRemote();
    });
  }

  void _goUpLocal() {
    final parent = Directory(localPath).parent;
    setState(() {
      localPath = parent.path;
      _refreshLocal();
    });
  }

  void _goUpRemote() {
    setState(() {
      remotePath = p.dirname(remotePath);
      _refreshRemote();
    });
  }

  @override
  void dispose() {
    client?.close();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 하단 바 높이 가져오기
    double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${widget.serverInfo['name']} - SFTP", style: const TextStyle(fontSize: 16)),
            Text(statusMessage, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "📱 My Phone", icon: Icon(Icons.phone_android)),
            Tab(text: "☁️ Remote Server", icon: Icon(Icons.cloud)),
          ],
        ),
      ),
      // SafeArea 제거
      body: isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : TabBarView(
          controller: _tabController,
          children: [
            _buildLocalView(bottomPadding),
            _buildRemoteView(bottomPadding),
          ],
        ),
    );
  }

  // 🔥 [수정] bottomPadding을 인자로 받아서 ListView 패딩에 추가
  Widget _buildLocalView(double bottomPadding) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[900],
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goUpLocal),
              Expanded(child: Text(localPath, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            // 🔥 리스트 마지막 아이템이 하단 바에 가려지지 않게 패딩 추가
            padding: EdgeInsets.only(bottom: bottomPadding),
            itemCount: localFiles.length,
            itemBuilder: (context, index) {
              final file = localFiles[index];
              final isDir = file is Directory;
              final fileName = p.basename(file.path);

              return ListTile(
                leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.yellow : Colors.white),
                title: Text(fileName, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  if (isDir) {
                    _navigateLocal(file);
                  } else {
                    _showFileOptions(fileName, isLocal: true, fileEntity: file);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 🔥 [수정] bottomPadding을 인자로 받아서 ListView 패딩에 추가
  Widget _buildRemoteView(double bottomPadding) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[900],
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goUpRemote),
              Expanded(child: Text(remotePath, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            // 🔥 리스트 마지막 아이템이 하단 바에 가려지지 않게 패딩 추가
            padding: EdgeInsets.only(bottom: bottomPadding),
            itemCount: remoteFiles.length,
            itemBuilder: (context, index) {
              final file = remoteFiles[index];
              final isDir = file.attr.isDirectory;
              
              if (file.filename == '.' || file.filename == '..') return const SizedBox.shrink();

              return ListTile(
                leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.yellow : Colors.white),
                title: Text(file.filename, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  if (isDir) {
                    _navigateRemote(file.filename);
                  } else {
                    _showFileOptions(file.filename, isLocal: false, sftpFile: file);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showFileOptions(String fileName, {required bool isLocal, FileSystemEntity? fileEntity, SftpName? sftpFile}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        // 🔥 BottomSheet도 하단 시스템 바만큼 패딩 추가
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(isLocal ? Icons.cloud_upload : Icons.cloud_download, color: const Color(0xFFBB86FC)),
              title: Text(isLocal ? "Upload to Server" : "Download to Phone"),
              onTap: () {
                Navigator.pop(ctx);
                if (isLocal && fileEntity is File) {
                  _uploadFile(fileEntity);
                } else if (!isLocal && sftpFile != null) {
                  _downloadFile(sftpFile);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text("Delete"),
              onTap: () {
                 Navigator.pop(ctx);
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Delete function disabled for safety.")));
              },
            ),
          ],
        ),
      ),
    );
  }
}