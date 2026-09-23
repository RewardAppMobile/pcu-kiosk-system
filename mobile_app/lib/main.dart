import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:nfc_manager/nfc_manager.dart';

void main() {
  runApp(const KioskApp());
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PCU Kiosk System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF003366), // PCU Navy Blue
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003366),
          primary: const Color(0xFF003366),
        ),
        useMaterial3: true,
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
  // -------------------------------------------------------------
  // CHANGE THIS TO YOUR ACTUAL PYTHONANYWHERE DOMAIN
  // -------------------------------------------------------------
  static const String baseUrl = 'https://RewardAppMobile.pythonanywhere.com';

  int _selectedIndex = 0;
  Map<String, dynamic>? _customer;
  List<dynamic> _products = [];
  bool _isLoadingProducts = false;
  bool _isNfcActive = false;
  String _cardStatusMessage = 'Place PCU Card on back of phone to scan';
  bool? _isLastScanValid;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _initAutoNfcScanner();
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  // Automatically listens for NFC tags continuously
  Future<void> _initAutoNfcScanner() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _cardStatusMessage = 'NFC is not supported or enabled on this device.';
        _isNfcActive = false;
      });
      return;
    }

    setState(() => _isNfcActive = true);

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        String scannedTag = _extractTagId(tag);
        await _fetchCustomer(scannedTag);
      },
      onError: (error) async {
        _initAutoNfcScanner(); // Restart listener if session drops
      },
    );
  }

  // Extract ID string from physical NFC Tag
  String _extractTagId(NfcTag tag) {
    final data = tag.data;
    if (data.containsKey('isodep')) {
      final idList = data['isodep']['identifier'] as List<dynamic>?;
      if (idList != null) {
        return idList.map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      }
    } else if (data.containsKey('nfca')) {
      final idList = data['nfca']['identifier'] as List<dynamic>?;
      if (idList != null) {
        return idList.map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      }
    }
    return 'RFID-1001'; // Fallback
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/products'));
      if (response.statusCode == 200) {
        setState(() {
          _products = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _fetchCustomer(String rfid) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/customer/$rfid'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _customer = data;
          _isLastScanValid = true;
          _cardStatusMessage = 'Valid Card Detected!';
        });
        _showCardPrompt(
          isValid: true,
          title: '✅ Valid Card',
          message: 'Welcome, ${data['name']}!\nPoints Balance: ${data['points']} pts',
        );
      } else {
        setState(() {
          _customer = null;
          _isLastScanValid = false;
          _cardStatusMessage = 'Invalid Card ($rfid)';
        });
        _showCardPrompt(
          isValid: false,
          title: '❌ Invalid Card',
          message: 'Card ID ($rfid) is not registered in the kiosk database.',
        );
      }
    } catch (e) {
      _showCardPrompt(
        isValid: false,
        title: 'Connection Error',
        message: 'Unable to reach backend server.',
      );
    }
  }

  Future<void> _redeemProduct(Map<String, dynamic> product) async {
    if (_customer == null) {
      _showCardPrompt(
        isValid: false,
        title: 'Scan Card First',
        message: 'Please tap a valid PCU Student ID card before redeeming items.',
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/redeem'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rfid_number': _customer!['rfid_number'],
          'product_id': product['id'],
        }),
      );

      final result = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showCardPrompt(
          isValid: true,
          title: '🎉 Redemption Successful!',
          message: '${result['message']}\nRemaining Points: ${result['remaining_points']}',
        );
        setState(() {
          _customer!['points'] = result['remaining_points'];
        });
        _fetchProducts();
      } else {
        _showCardPrompt(
          isValid: false,
          title: 'Transaction Failed',
          message: result['error'] ?? 'Could not complete redemption.',
        );
      }
    } catch (e) {
      _showCardPrompt(
        isValid: false,
        title: 'Error',
        message: 'Server transaction failed.',
      );
    }
  }

  void _showCardPrompt({required bool isValid, required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isValid ? Icons.check_circle : Icons.cancel,
              color: isValid ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Column(
          children: [
            Text('PCU KIOSK SYSTEM', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Student Reward & Inventory Management', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProducts,
            tooltip: 'Refresh Inventory',
          ),
        ],
      ),
      body: _selectedIndex == 0 ? _buildScanTab() : _buildMenuTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF003366),
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.nfc), label: 'Scan Card'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Kiosk Inventory'),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Auto-detect NFC status bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isLastScanValid == true
                ? Colors.green.shade50
                : (_isLastScanValid == false ? Colors.red.shade50 : Colors.blue.shade50),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isLastScanValid == true
                  ? Colors.green
                  : (_isLastScanValid == false ? Colors.red : const Color(0xFF003366)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isNfcActive ? Icons.sensors : Icons.sensors_off,
                color: const Color(0xFF003366),
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NFC Auto-Scanner Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(_cardStatusMessage, style: const TextStyle(fontSize: 12, color: Colors.black80)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Display Scanned Card Info
        if (_customer != null) _buildProfileCard() else _buildEmptyState(),

        const SizedBox(height: 16),

        // Manual Demo Buttons for Testing
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('Quick Test Tags (Manual Tap):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(label: const Text('Alexondre (1001)'), onPressed: () => _fetchCustomer('RFID-1001')),
                  ActionChip(label: const Text('Hussein (1002)'), onPressed: () => _fetchCustomer('RFID-1002')),
                  ActionChip(label: const Text('Invalid Tag'), onPressed: () => _fetchCustomer('INVALID-9999')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF003366),
                  child: Text(_customer!['name'][0], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_customer!['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Student ID: ${_customer!['student_id']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      Text('RFID Tag: ${_customer!['rfid_number']}', style: const TextStyle(color: Color(0xFF003366), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Available Reward Points', style: TextStyle(color: Color(0xFF003366), fontWeight: FontWeight.bold)),
                  Text('${_customer!['points']} PTS', style: const TextStyle(color: Color(0xFF003366), fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.credit_card_sharp, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No Student ID Card Scanned',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Hold your PCU Student ID card against the back of this phone to automatically display points and rewards.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTab() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF003366)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Kiosk Inventory & Rewards',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003366)),
        ),
        const SizedBox(height: 4),
        Text(
          _customer != null ? 'Redeeming for: ${_customer!['name']} (${_customer!['points']} pts)' : 'Scan Student ID card to redeem items',
          style: TextStyle(fontSize: 12, color: _customer != null ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ..._products.map((item) {
          final bool inStock = (item['stock'] ?? 0) > 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['price']} Points Required', style: const TextStyle(color: Color(0xFF003366), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      inStock ? 'In Stock: ${item['stock']} available' : 'Out of Stock',
                      style: TextStyle(fontSize: 12, color: inStock ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: inStock ? const Color(0xFF003366) : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: inStock ? () => _redeemProduct(item) : null,
                child: const Text('Redeem'),
              ),
            ),
          );
        }),
      ],
    );
  }
}
