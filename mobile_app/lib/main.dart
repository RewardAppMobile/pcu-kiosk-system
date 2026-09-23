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
      title: 'PCU Rewards Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFD70F64), // Foodpanda Pink
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD70F64),
          primary: const Color(0xFFD70F64),
          secondary: const Color(0xFF003366), // PCU Navy Blue
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
  static const String baseUrl = 'https://RewardAppMobile.pythonanywhere.com';

  int _selectedIndex = 0;
  Map<String, dynamic>? _customer;
  List<dynamic> _products = [];
  bool _isLoadingProducts = false;
  bool _isNfcActive = false;
  String _cardStatusMessage = 'Ready to scan PCU Student ID';
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

  Future<void> _initAutoNfcScanner() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      if (mounted) {
        setState(() {
          _cardStatusMessage = 'NFC sensor not available on this device';
          _isNfcActive = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isNfcActive = true);
    }

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        List<String> rfidVariants = _generateRfidVariants(tag);
        await _fetchCustomerWithVariants(rfidVariants);
      },
      onError: (error) async {
        _initAutoNfcScanner();
      },
    );
  }

  // Generates Hex, Dec, and Reverse Endian variations for 100% backward compatibility
  List<String> _generateRfidVariants(NfcTag tag) {
    final Map<dynamic, dynamic> data = tag.data;
    List<int>? bytes;

    for (final key in [
      'isodep',
      'nfca',
      'nfcb',
      'nfcf',
      'nfcv',
      'mifareclassic',
      'mifareultralight',
      'mifare',
      'ndef'
    ]) {
      if (data.containsKey(key) && data[key] is Map) {
        final techMap = data[key] as Map;
        if (techMap.containsKey('identifier') && techMap['identifier'] != null) {
          bytes = List<int>.from(techMap['identifier']);
          break;
        } else if (techMap.containsKey('id') && techMap['id'] != null) {
          bytes = List<int>.from(techMap['id']);
          break;
        }
      }
    }

    Set<String> candidates = {};

    if (bytes != null && bytes.isNotEmpty) {
      // 1. Direct Hex
      String hexForward = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      candidates.add(hexForward);

      // 2. Direct Decimal
      try {
        BigInt decForward = BigInt.parse(hexForward, radix: 16);
        candidates.add(decForward.toString());
      } catch (_) {}

      // 3. Reversed Hex (Little Endian)
      List<int> reversedBytes = bytes.reversed.toList();
      String hexReversed = reversedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      candidates.add(hexReversed);

      // 4. Reversed Decimal
      try {
        BigInt decReversed = BigInt.parse(hexReversed, radix: 16);
        candidates.add(decReversed.toString());
      } catch (_) {}

      // 5. Add "RFID-" prefix variations for legacy entries
      List<String> currentList = List.from(candidates);
      for (var item in currentList) {
        candidates.add('RFID-$item');
      }
    } else {
      candidates.addAll(['RFID-1001', '1001']);
    }

    return candidates.toList();
  }

  Future<void> _fetchProducts() async {
    if (mounted) setState(() => _isLoadingProducts = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/products'));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _products = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _fetchCustomerWithVariants(List<String> variants) async {
    for (String rfid in variants) {
      try {
        final response = await http.get(Uri.parse('$baseUrl/api/customer/$rfid'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (mounted) {
            setState(() {
              _customer = data;
              _isLastScanValid = true;
              _cardStatusMessage = 'Card Verified: ${data['name']}';
            });
          }
          _showCardPrompt(
            isValid: true,
            title: '🎉 Welcome Back!',
            message: 'Member: ${data['name']}\nStudent ID: ${data['student_id']}\nAvailable Balance: ${data['points']} PTS',
          );
          return;
        }
      } catch (e) {
        debugPrint('Checking $rfid failed: $e');
      }
    }

    String hexId = variants.isNotEmpty ? variants.first : 'Unknown';
    String decId = variants.length > 1 ? variants[1] : 'Unknown';

    if (mounted) {
      setState(() {
        _customer = null;
        _isLastScanValid = false;
        _cardStatusMessage = 'Unregistered Card ($hexId)';
      });
    }

    _showCardPrompt(
      isValid: false,
      title: '❌ Unregistered Card',
      message: 'This ID card is not in the system.\n\nDetected Tag Formats:\n• Hex ID: $hexId\n• Dec ID: $decId\n\nRegister either value in your Admin Web App.',
    );
  }

  Future<void> _redeemProduct(Map<String, dynamic> product) async {
    if (_customer == null) {
      _showCardPrompt(
        isValid: false,
        title: 'Scan ID First',
        message: 'Tap a registered PCU Student ID card before redeeming rewards.',
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
          title: '🎉 Reward Claimed!',
          message: '${result['message']}\nRemaining Points: ${result['remaining_points']} PTS',
        );
        if (mounted) {
          setState(() {
            _customer!['points'] = result['remaining_points'];
          });
        }
        _fetchProducts();
      } else {
        _showCardPrompt(
          isValid: false,
          title: 'Redemption Failed',
          message: result['error'] ?? 'Insufficient points or out of stock.',
        );
      }
    } catch (e) {
      _showCardPrompt(
        isValid: false,
        title: 'Connection Error',
        message: 'Could not complete transaction with the server.',
      );
    }
  }

  void _showCardPrompt({required bool isValid, required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isValid ? Colors.green.shade100 : Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isValid ? Icons.check_circle : Icons.error_outline,
                color: isValid ? Colors.green.shade800 : Colors.red.shade800,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isValid ? const Color(0xFFD70F64) : const Color(0xFF003366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
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
        backgroundColor: const Color(0xFFD70F64),
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stars_rounded, color: Color(0xFFFFC107)),
            SizedBox(width: 8),
            Text('PCU REWARDS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchProducts,
            tooltip: 'Refresh Kiosk',
          ),
        ],
      ),
      body: _selectedIndex == 0 ? _buildScanTab() : _buildMenuTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFD70F64),
        unselectedItemColor: Colors.grey.shade600,
        backgroundColor: Colors.white,
        elevation: 10,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.nfc_rounded), label: 'My Pass'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Redeem Menu'),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isLastScanValid == true
                ? Colors.green.shade50
                : (_isLastScanValid == false ? Colors.red.shade50 : const Color(0xFFFFF0F5)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isLastScanValid == true
                  ? Colors.green
                  : (_isLastScanValid == false ? Colors.red : const Color(0xFFFFD6E5)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isNfcActive ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                color: const Color(0xFFD70F64),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NFC Auto-Detector Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF003366))),
                    Text(_cardStatusMessage, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_customer != null) _buildProfileCard() else _buildEmptyState(),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF003366), Color(0xFF001A33)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF003366).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('MEMBER PASS', style: TextStyle(color: Color(0xFF003366), fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.8)),
                ),
                const Text('PHILIPPINE CHRISTIAN UNIV', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFD70F64),
                  child: Text(
                    _customer!['name'][0],
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_customer!['name'], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Student ID: ${_customer!['student_id']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('Tag ID: ${_customer!['rfid_number']}', style: const TextStyle(color: Color(0xFFFFC107), fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('REWARD POINTS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('Ready to spend', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: Color(0xFFFFC107), size: 28),
                      const SizedBox(width: 6),
                      Text('${_customer!['points']}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                      const Text(' PTS', style: TextStyle(color: Color(0xFFFFC107), fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF0F5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.contactless_rounded, size: 48, color: Color(0xFFD70F64)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tap PCU Card to Begin',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF003366)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hold your PCU Student ID card against the back of this phone to automatically fetch your member account & point balance.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTab() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD70F64)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Kiosk Inventory',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF003366)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_products.length} Items Available',
                style: const TextStyle(color: Color(0xFFD70F64), fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _customer != null
              ? 'Active Member: ${_customer!['name']} (${_customer!['points']} PTS)'
              : 'Tap ID card on "My Pass" tab to select member',
          style: TextStyle(
            fontSize: 12,
            color: _customer != null ? Colors.green.shade800 : Colors.red.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._products.map((item) {
          final bool inStock = (item['stock'] ?? 0) > 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded, color: Color(0xFFFFC107), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${item['price']} Points',
                          style: const TextStyle(color: Color(0xFFD70F64), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      inStock ? 'In Stock: ${item['stock']} available' : 'Out of Stock',
                      style: TextStyle(fontSize: 12, color: inStock ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: inStock ? const Color(0xFFD70F64) : Colors.grey.shade300,
                  foregroundColor: inStock ? Colors.white : Colors.grey.shade600,
                  elevation: inStock ? 2 : 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: inStock ? () => _redeemProduct(item) : null,
                child: const Text('Redeem', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          );
        }),
      ],
    );
  }
}
