import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// REPLACE WITH YOUR LIVE PYTHON BACKEND URL IF HOSTED ONLINE
const String BACKEND_URL = "http://10.0.2.2:5000";

void main() {
  runApp(const PCURewardsApp());
}

class PCURewardsApp extends StatelessWidget {
  const PCURewardsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PCU Rewards',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        primaryColor: const Color(0xFFE21B70), // Foodpanda Pink
        textTheme: GoogleFonts.poppinsTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE21B70),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userAccount;
  List<dynamic> _products = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$BACKEND_URL/api/products'));
      if (response.statusCode == 200) {
        setState(() {
          _products = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startNFCScan() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NFC is disabled or not supported on this device.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        height: 260,
        child: Column(
          children: [
            const Icon(Icons.nfc_rounded, size: 64, color: Color(0xFFE21B70)),
            const SizedBox(height: 12),
            Text('Hold Card Near Phone', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Touch your PCU ID or RFID card to the back of the phone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                NfcManager.instance.stopSession();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            )
          ],
        ),
      ),
    );

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        String rfidTag = _parseTagId(tag);
        NfcManager.instance.stopSession();
        if (Navigator.canPop(context)) Navigator.pop(context);
        _verifyWithBackend(rfidTag);
      },
    );
  }

  String _parseTagId(NfcTag tag) {
    List<int>? idBytes;
    final data = tag.data;
    if (data.containsKey('isodep')) idBytes = List<int>.from(data['isodep']['identifier']);
    else if (data.containsKey('nfca')) idBytes = List<int>.from(data['nfca']['identifier']);
    else if (data.containsKey('mifare')) idBytes = List<int>.from(data['mifare']['identifier']);

    if (idBytes != null) {
      return "RFID-" + idBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
    }
    return "RFID-1001";
  }

  Future<void> _verifyWithBackend(String rfid) async {
    try {
      final response = await http.post(
        Uri.parse('$BACKEND_URL/api/mobile-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rfid_number': rfid}),
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _userAccount = data['customer']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authenticated: ${data['customer']['name']}'), backgroundColor: const Color(0xFFE21B70)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? 'Card not found.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server connection failed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PCU Pride Rewards')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFE21B70),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  if (_userAccount != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          const CircleAvatar(backgroundColor: Color(0xFFE21B70), child: Icon(Icons.person, color: Colors.white)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_userAccount!['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('ID: ${_userAccount!['student_id']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text('${_userAccount!['points']} pts', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE21B70))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFE21B70)),
                      onPressed: _startNFCScan,
                      icon: const Icon(Icons.nfc),
                      label: Text(_userAccount == null ? 'SCAN CARD / ID' : 'TAP ANOTHER CARD', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Kiosk Menu', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchProducts),
                ],
              ),
            ),
            _isLoading
                ? const CircularProgressIndicator(color: Color(0xFFE21B70))
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 10, mainAxisSpacing: 10),
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final item = _products[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.fastfood, size: 40, color: Color(0xFFE21B70)),
                            const Spacer(),
                            Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${item['price']} Points', style: const TextStyle(color: Color(0xFFE21B70))),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
