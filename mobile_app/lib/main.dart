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
      title: 'PCU Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFD70F64),
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD70F64),
          primary: const Color(0xFFD70F64),
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
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.15');
  int _selectedIndex = 0;

  Map<String, dynamic>? _customer;
  List<dynamic> _products = [];
  bool _isLoadingProducts = false;
  bool _isScanningNfc = false;

  String get baseUrl => 'http://${_ipController.text.trim()}:5000';

  @override
  void initState() {
    super.initState();
    _fetchProducts();
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
        setState(() => _customer = data);
        _showMessage('ID Verified 🐼', 'Welcome back, ${data['name']}!');
      } else {
        _showMessage('Card Not Found', 'No student registered for tag: $rfid');
      }
    } catch (e) {
      _showMessage('Connection Error', 'Cannot reach Flask server at $baseUrl');
    }
  }

  Future<void> _startNfcScan() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _showMessage('NFC Unavailable', 'NFC hardware is not supported or disabled on this device.');
      return;
    }

    setState(() => _isScanningNfc = true);
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      final ndef = tag.data;
      String scannedTag = 'RFID-1001';
      if (ndef.containsKey('isodep')) {
        scannedTag = ndef['isodep']['identifier']?.toString() ?? 'RFID-1001';
      }
      await _fetchCustomer(scannedTag);
      NfcManager.instance.stopSession();
      setState(() => _isScanningNfc = false);
    });
  }

  Future<void> _redeemProduct(Map<String, dynamic> product) async {
    if (_customer == null) {
      _showMessage('Scan Card First', 'Please scan your Student ID before placing an order.');
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
        _showMessage('Success! 🎉', result['message']);
        setState(() {
          _customer!['points'] = result['remaining_points'];
        });
        _fetchProducts();
      } else {
        _showMessage('Order Failed', result['error'] ?? 'Transaction failed.');
      }
    } catch (e) {
      _showMessage('Error', 'Failed to communicate with Flask server.');
    }
  }

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFFD70F64))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFD70F64),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PCU CAMPUS KIOSK', style: TextStyle(fontSize: 10, letterSpacing: 1)),
            Text('foodpanda 🐼', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProducts,
            tooltip: 'Refresh Menu',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Flask Server IP: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Expanded(
                  child: SizedBox(
                    height: 35,
                    child: TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        fillColor: Colors.grey[200],
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedIndex == 0 ? _buildScanTab() : _buildMenuTab(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFD70F64),
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.credit_card), label: 'Scan ID'),
          BottomNavigationBarItem(icon: Icon(Icons.fastfood), label: 'Menu & Redeem'),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFD70F64),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Scan Student ID', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Hold your physical PCU Student ID near the back of your Android or iPhone device.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFD70F64),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isScanningNfc ? null : _startNfcScan,
                  icon: _isScanningNfc
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFD70F64), strokeWidth: 2))
                      : const Icon(Icons.nfc),
                  label: Text(_isScanningNfc ? 'Scanning...' : 'Scan CARD / ID', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white30),
              const Text('Or test manually with registered tags:', style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _demoChip('Alexondre (1001)', 'RFID-1001'),
                  _demoChip('Hussein (1002)', 'RFID-1002'),
                  _demoChip('Calvin (1003)', 'RFID-1003'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_customer != null) _buildProfileCard() else _buildEmptyState(),
      ],
    );
  }

  Widget _demoChip(String label, String rfid) {
    return ActionChip(
      backgroundColor: Colors.white24,
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      onPressed: () => _fetchCustomer(rfid),
    );
  }

  Widget _buildProfileCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFD70F64),
                  child: Text(_customer!['name'][0], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_customer!['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Student ID: ${_customer!['student_id']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('RFID Tag: ${_customer!['rfid_number']}', style: const TextStyle(color: Color(0xFFD70F64), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD6E5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Available Points Balance', style: TextStyle(color: Color(0xFFD70F64), fontWeight: FontWeight.w600)),
                  Text('${_customer!['points']} pts', style: const TextStyle(color: Color(0xFFD70F64), fontSize: 20, fontWeight: FontWeight.bold)),
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
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.phone_android, size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No active card scanned yet. Tap "Scan CARD / ID" or select a demo tag above.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTab() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD70F64)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final item = _products[index];
        final bool inStock = item['stock'] > 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['price']} Points / ₱${(item['price'] as num).toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFD70F64), fontWeight: FontWeight.bold)),
                Text(inStock ? 'Stock: ${item['stock']} left' : 'Out of Stock', style: TextStyle(fontSize: 11, color: inStock ? Colors.green : Colors.red)),
              ],
            ),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: inStock ? const Color(0xFFD70F64) : Colors.grey,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              onPressed: inStock ? () => _redeemProduct(item) : null,
              child: const Text('Redeem'),
            ),
          ),
        );
      },
    );
  }
}
