import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// NOTE:
// This full main.dart keeps your current working Nike tracking flow,
// keeps auto-scan paused, and adds the first cross-retailer deal section.
// It calls:
//   /product
// then:
//   /search-deals
// and displays the top Google Shopping results under each tracked item.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SaleScoutApp());
}

class SaleScoutApp extends StatelessWidget {
  const SaleScoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sale Scout',
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) return const HomePage();

        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  String errorMessage = '';

  final Color cream = const Color(0xFFF0E4C5);
  final Color green = const Color(0xFF0B1A13);
  final Color lightGreen = const Color(0xFFA7C97A);
  final Color fieldGreen = const Color(0xFF102219);

  Future<void> submit() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set({
          'email': credential.user!.email,
          'plan': 'Scout',
          'itemLimit': 5,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'trackedItems': [],
        }, SetOptions(merge: true));
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        errorMessage = e.message ?? 'Something went wrong.';
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: green,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isPhone ? 22 : 28),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Image.asset(
                    'assets/sale_scout_logo.png',
                    height: isPhone ? 130 : 190,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isLogin ? 'Welcome back, Scout' : 'Create your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cream,
                      fontSize: isPhone ? 26 : 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Track deals, save your watchlist, and monitor prices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cream.withOpacity(.7),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: emailController,
                    style: TextStyle(color: cream),
                    decoration: InputDecoration(
                      hintText: 'Email',
                      hintStyle: TextStyle(color: cream.withOpacity(.5)),
                      filled: true,
                      fillColor: fieldGreen,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: TextStyle(color: cream),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: TextStyle(color: cream.withOpacity(.5)),
                      filled: true,
                      fillColor: fieldGreen,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: lightGreen,
                        foregroundColor: green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        isLoading
                            ? 'Please wait...'
                            : isLogin
                                ? 'Log In'
                                : 'Sign Up',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        isLogin = !isLogin;
                        errorMessage = '';
                      });
                    },
                    child: Text(
                      isLogin
                          ? 'Need an account? Sign up'
                          : 'Already have an account? Log in',
                      style: TextStyle(color: cream),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DealResult {
  final String title;
  final int price;
  final String source;
  final String link;
  final String thumbnail;

  DealResult({
    required this.title,
    required this.price,
    required this.source,
    required this.link,
    required this.thumbnail,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'price': price,
        'source': source,
        'link': link,
        'thumbnail': thumbnail,
      };

  factory DealResult.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];

    return DealResult(
      title: json['title']?.toString() ?? '',
      price: rawPrice is num
          ? rawPrice.round()
          : int.tryParse((rawPrice ?? '0').toString()) ?? 0,
      source: json['source']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
    );
  }
}

class ProductItem {
  final String url;
  final String title;
  final String sku;
  final String retailer;
  final int currentPrice;
  final int originalPrice;
  final bool originalPriceAvailable;
  final String imageUrl;
  final int betterDealPrice;
  final String betterDealStore;
  final int confidence;
  final String lastChecked;
  final bool priceDropped;
  final String source;
  final List<Map<String, dynamic>> priceHistory;
  final List<DealResult> dealResults;

  ProductItem({
    required this.url,
    required this.title,
    required this.sku,
    required this.retailer,
    required this.currentPrice,
    required this.originalPrice,
    required this.originalPriceAvailable,
    required this.imageUrl,
    required this.betterDealPrice,
    required this.betterDealStore,
    required this.confidence,
    required this.lastChecked,
    required this.priceDropped,
    required this.source,
    required this.priceHistory,
    required this.dealResults,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'sku': sku,
        'retailer': retailer,
        'currentPrice': currentPrice,
        'originalPrice': originalPrice,
        'originalPriceAvailable': originalPriceAvailable,
        'imageUrl': imageUrl,
        'betterDealPrice': betterDealPrice,
        'betterDealStore': betterDealStore,
        'confidence': confidence,
        'lastChecked': lastChecked,
        'priceDropped': priceDropped,
        'source': source,
        'priceHistory': priceHistory
            .map(
              (entry) => {
                'price': entry['price'],
                'timestamp': entry['timestamp'],
              },
            )
            .toList(),
        'dealResults': dealResults.map((deal) => deal.toJson()).toList(),
      };

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    return ProductItem(
      url: json['url'] ?? '',
      title: json['title'] ?? 'Unknown Product',
      sku: json['sku'] ?? '',
      retailer: json['retailer'] ?? 'Unknown',
      currentPrice: (json['currentPrice'] ?? 0).round(),
      originalPrice: (json['originalPrice'] ?? 0).round(),
      originalPriceAvailable: json['originalPriceAvailable'] ?? false,
      imageUrl: json['imageUrl'] ?? '',
      betterDealPrice: (json['betterDealPrice'] ?? 0).round(),
      betterDealStore: json['betterDealStore'] ?? 'Unknown',
      confidence: (json['confidence'] ?? 0).round(),
      lastChecked: json['lastChecked'] ?? 'Not checked yet',
      priceDropped: json['priceDropped'] ?? false,
      source: json['source'] ?? 'unknown',
      priceHistory: List<Map<String, dynamic>>.from(
        (json['priceHistory'] ?? []).map(
          (entry) {
            if (entry is num) {
              return {
                'price': entry.round(),
                'timestamp': DateTime.now().toIso8601String(),
              };
            }

            return {
              'price': ((entry['price'] ?? 0) as num).round(),
              'timestamp':
                  entry['timestamp'] ?? DateTime.now().toIso8601String(),
            };
          },
        ),
      ),
      dealResults: List<DealResult>.from(
        (json['dealResults'] ?? []).map(
          (deal) => DealResult.fromJson(Map<String, dynamic>.from(deal)),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController urlController = TextEditingController();

  final Color cream = const Color(0xFFF0E4C5);
  final Color green = const Color(0xFF0B1A13);
  final Color lightGreen = const Color(0xFFA7C97A);
  final Color cardGreen = const Color(0xFF13281E);
  final Color fieldGreen = const Color(0xFF102219);
  final Color gold = const Color(0xFFE0A24A);

  List<ProductItem> trackedItems = [];
  bool isLoading = false;
  bool isRefreshing = false;
  bool apiScanInProgress = false;
  bool showDropAlert = false;

  String plan = 'Scout';
  int itemLimit = 5;

  Timer? monitorTimer;
  int countdown = 1800;

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get userDoc =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  @override
  void initState() {
    super.initState();
    loadUserData();

    // Auto background scanning is temporarily disabled.
    // This prevents repeated Nike scans and backend "Scanner busy" issues.
    // startMonitoring();
  }

  @override
  void dispose() {
    monitorTimer?.cancel();
    urlController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void startMonitoring() {
    monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        countdown--;
      });

      if (countdown <= 0) {
        countdown = 1800;

        // Auto scan temporarily disabled.
        // refreshPrices(autoScan: true);
      }
    });
  }

  Future<void> loadUserData() async {
    final snapshot = await userDoc.get();

    if (!snapshot.exists) {
      await userDoc.set({
        'email': FirebaseAuth.instance.currentUser?.email,
        'plan': 'Scout',
        'itemLimit': 5,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'trackedItems': [],
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        trackedItems = [];
        plan = 'Scout';
        itemLimit = 5;
      });

      return;
    }

    final data = snapshot.data() ?? {};

    final items = List<Map<String, dynamic>>.from(
      (data['trackedItems'] ?? []).map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );

    if (!mounted) return;

    setState(() {
      plan = data['plan'] ?? 'Scout';
      itemLimit = data['itemLimit'] ?? 5;
      trackedItems = items.map((item) => ProductItem.fromJson(item)).toList();
    });
  }

  Future<void> saveUserData() async {
    await userDoc.set({
      'email': FirebaseAuth.instance.currentUser?.email,
      'plan': plan,
      'itemLimit': itemLimit,
      'updatedAt': FieldValue.serverTimestamp(),
      'trackedItems': trackedItems.map((item) => item.toJson()).toList(),
    }, SetOptions(merge: true));
  }

  Future<List<DealResult>> searchDealsForProduct(
    String title,
    String sku,
  ) async {
    try {
      final searchQuery = sku.isNotEmpty ? '$title $sku' : title;

      final encodedQuery = Uri.encodeComponent(searchQuery);

      final response = await http
          .get(
            Uri.parse(
              'https://sale-scout-api.onrender.com/search-deals?q=$encodedQuery',
            ),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        print('Search deals bad status: ${response.statusCode}');
        print(response.body);
        return [];
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final rawResults = decoded['results'];

      if (rawResults is! List) {
        return [];
      }

      final deals = rawResults
          .map((item) => DealResult.fromJson(Map<String, dynamic>.from(item)))
          .where((deal) =>
              deal.title.isNotEmpty && deal.source.isNotEmpty && deal.price > 0)
          .toList();

      deals.sort((a, b) => a.price.compareTo(b.price));

      return deals.take(8).toList();
    } catch (e) {
      print('SEARCH DEALS ERROR: $e');
      return [];
    }
  }

  Future<ProductItem?> getProductFromApi(
    String url, {
    ProductItem? oldItem,
  }) async {
    try {
      final encodedUrl = Uri.encodeComponent(url);

      final response = await http
          .get(
            Uri.parse(
              'https://sale-scout-api.onrender.com/product?url=$encodedUrl',
            ),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        print('Sale Scout API bad status: ${response.statusCode}');
        print(response.body);

        if (response.statusCode == 429) {
          showMessage('Scanner is busy. Please wait a moment and try again.');
        } else {
          showMessage('Product scan failed. Please try again.');
        }

        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        print('Sale Scout API returned invalid JSON.');
        showMessage('Product scan returned invalid data.');
        return null;
      }

      final data = decoded;

      if (data['error'] != null) {
        print('Sale Scout API error: ${data['error']}');
        showMessage(data['error'].toString());
        return null;
      }

      final title = (data['title'] ?? '').toString().trim();
      final retailer = (data['retailer'] ?? '').toString().trim();
      final currentPriceValue = data['currentPrice'];

      final newPrice = currentPriceValue is num
          ? currentPriceValue.round()
          : int.tryParse((currentPriceValue ?? '').toString()) ?? 0;

      if (title.isEmpty ||
          title == 'Unknown Product' ||
          retailer.isEmpty ||
          retailer == 'Unknown' ||
          newPrice <= 0) {
        print('Rejected bad product response: $data');
        showMessage('Sale Scout could not read this product yet. Try again.');
        return null;
      }

      final oldPrice = oldItem?.currentPrice;

      final history = oldItem == null
          ? createInitialHistory(newPrice)
          : [
              ...oldItem.priceHistory,
              {
                'price': newPrice,
                'timestamp': DateTime.now().toIso8601String(),
              }
            ];

      final originalAvailable = data['originalPriceAvailable'] ?? false;
      final rawOriginal = data['originalPrice'];
      final betterDeal = data['betterDeal'];
      final sku = (data['sku'] ?? '').toString().trim();

      final deals = await searchDealsForProduct(title, sku);
      final cheapestDeal =
          deals.isEmpty ? null : deals.reduce((a, b) => a.price < b.price ? a : b);

      return ProductItem(
        url: url,
        title: title,
        sku: sku,
        retailer: retailer,
        currentPrice: newPrice,
        originalPrice: rawOriginal is num ? rawOriginal.round() : 0,
        originalPriceAvailable: originalAvailable == true,
        imageUrl: data['imageUrl'] ?? '',
        betterDealPrice: cheapestDeal?.price ??
            (betterDeal is Map && betterDeal['price'] is num
                ? (betterDeal['price'] as num).round()
                : newPrice),
        betterDealStore: cheapestDeal?.source ??
            (betterDeal is Map
                ? (betterDeal['store'] ?? 'Unknown').toString()
                : 'Unknown'),
        confidence: betterDeal is Map && betterDeal['confidence'] is num
            ? (betterDeal['confidence'] as num).round()
            : 0,
        lastChecked: DateTime.now().toLocal().toString().substring(0, 16),
        priceDropped: oldPrice != null && newPrice > 0 && newPrice < oldPrice,
        source: data['source'] ?? 'unknown',
        priceHistory: history,
        dealResults: deals,
      );
    } catch (e) {
      print(e);
      showMessage('Product scan timed out or failed. Please try again.');
      return null;
    }
  }

  List<Map<String, dynamic>> createInitialHistory(int currentPrice) {
    return [
      {
        'price': currentPrice,
        'timestamp': DateTime.now().toIso8601String(),
      }
    ];
  }

  Future<void> fetchProduct() async {
    if (apiScanInProgress) {
      showMessage('A scan is already running. Please wait.');
      return;
    }

    final url = urlController.text.trim();

    if (url.isEmpty) return;

    if (trackedItems.length >= itemLimit) {
      showLimitDialog();
      return;
    }

    if (!mounted) return;

    setState(() {
      isLoading = true;
      apiScanInProgress = true;
    });

    try {
      final item = await getProductFromApi(url);

      if (item != null) {
        if (!mounted) return;

        setState(() {
          trackedItems.insert(0, item);
          urlController.clear();
        });

        await saveUserData();
      }
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        apiScanInProgress = false;
      });
    }
  }

  Future<void> refreshPrices({bool autoScan = false}) async {
    if (apiScanInProgress) return;
    if (trackedItems.isEmpty) return;

    if (!mounted) return;

    setState(() {
      isRefreshing = true;
      apiScanInProgress = true;
    });

    final updatedItems = <ProductItem>[];
    bool anyDrop = false;

    try {
      for (final item in trackedItems) {
        final updated = await getProductFromApi(item.url, oldItem: item);

        if (updated != null && updated.priceDropped) {
          anyDrop = true;
        }

        updatedItems.add(updated ?? item);

        await Future.delayed(const Duration(seconds: 3));
      }

      if (!mounted) return;

      setState(() {
        trackedItems = updatedItems;
        showDropAlert = anyDrop;
      });

      await saveUserData();

      if (anyDrop) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              showDropAlert = false;
            });
          }
        });
      }
    } finally {
      if (!mounted) return;

      setState(() {
        isRefreshing = false;
        apiScanInProgress = false;
      });
    }
  }

  Future<void> removeItem(int index) async {
    setState(() {
      trackedItems.removeAt(index);
    });

    await saveUserData();
  }

  void showLimitDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardGreen,
        title: Text(
          'Scout Limit Reached',
          style: TextStyle(
            color: cream,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Your Scout plan tracks up to $itemLimit items.\n\nUpgrade to Marksman or Hot Shot later for more tracking power.',
          style: TextStyle(
            color: cream.withOpacity(.85),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: TextStyle(color: lightGreen),
            ),
          ),
        ],
      ),
    );
  }

  int lowestPrice(ProductItem item) {
    if (item.priceHistory.isEmpty) return item.currentPrice;

    return item.priceHistory.map((entry) => entry['price'] as int).reduce(min);
  }

  int highestPrice(ProductItem item) {
    if (item.priceHistory.isEmpty) return item.currentPrice;

    return item.priceHistory.map((entry) => entry['price'] as int).reduce(max);
  }

  String trendLabel(ProductItem item) {
    if (item.priceHistory.length < 2) return 'Tracking';

    final last = item.priceHistory.last['price'] as int;
    final previous =
        item.priceHistory[item.priceHistory.length - 2]['price'] as int;

    if (last < previous) return 'Trending Down';
    if (last > previous) return 'Trending Up';

    return 'Stable';
  }

  IconData trendIcon(ProductItem item) {
    final trend = trendLabel(item);

    if (trend == 'Trending Down') return Icons.trending_down;
    if (trend == 'Trending Up') return Icons.trending_up;

    return Icons.trending_flat;
  }

  Color trendColor(ProductItem item) {
    final trend = trendLabel(item);

    if (trend == 'Trending Down') return lightGreen;
    if (trend == 'Trending Up') return Colors.redAccent;

    return cream.withOpacity(.72);
  }

  Future<void> openDealLink(String link) async {
    final trimmedLink = link.trim();

    if (trimmedLink.isEmpty) {
      showMessage('No retailer link available yet.');
      return;
    }

    final uri = Uri.tryParse(trimmedLink);

    if (uri == null || !uri.hasScheme) {
      showMessage('Invalid retailer link.');
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );

    if (!opened) {
      showMessage('Could not open retailer link.');
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final remaining = itemLimit - trackedItems.length;
    final isPhone = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: green,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isPhone ? 14 : 22,
            isPhone ? 6 : 10,
            isPhone ? 14 : 22,
            isPhone ? 12 : 22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDropAlert)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: lightGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '🚨 Price drop detected!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: green,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cream.withOpacity(.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: logout,
                    child: Text(
                      'Logout',
                      style: TextStyle(color: cream),
                    ),
                  ),
                ],
              ),
              Center(
                child: Image.asset(
                  'assets/sale_scout_logo.png',
                  height: isPhone ? 85 : 165,
                ),
              ),
              SizedBox(height: isPhone ? 4 : 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('🎖 $plan Plan', lightGreen, green),
                  _pill(
                    'Watching ${trackedItems.length}/$itemLimit',
                    cream,
                    green,
                  ),
                ],
              ),
              SizedBox(height: isPhone ? 8 : 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: lightGreen.withOpacity(.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: lightGreen.withOpacity(.42)),
                    ),
                    child: Text(
                      apiScanInProgress
                          ? '🟡 Scan Running'
                          : '🟢 Monitoring Active',
                      style: TextStyle(
                        color: lightGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: isPhone ? 12 : 14,
                      ),
                    ),
                  ),
                  Text(
                    'Auto scan paused',
                    style: TextStyle(
                      color: cream.withOpacity(.68),
                      fontSize: isPhone ? 12 : 14,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isPhone ? 10 : 17),
              Text(
                'Track prices across the internet',
                style: TextStyle(
                  color: cream,
                  fontSize: isPhone ? 23 : 31,
                  height: 1.05,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: isPhone ? 6 : 9),
              Text(
                'Paste a product URL and Sale Scout will monitor it for price drops.',
                style: TextStyle(
                  color: cream.withOpacity(.72),
                  fontSize: isPhone ? 13 : 16,
                ),
              ),
              SizedBox(height: isPhone ? 12 : 21),
              TextField(
                controller: urlController,
                style: TextStyle(color: cream, fontSize: isPhone ? 14 : 17),
                decoration: InputDecoration(
                  hintText: remaining > 0
                      ? 'Paste product URL...'
                      : 'Scout item limit reached',
                  hintStyle: TextStyle(color: cream.withOpacity(.52)),
                  prefixIcon: Icon(Icons.link, color: cream.withOpacity(.64)),
                  filled: true,
                  fillColor: fieldGreen,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: isPhone ? 12 : 16,
                  ),
                  enabled: remaining > 0 && !apiScanInProgress,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: cream.withOpacity(.28)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: gold.withOpacity(.5)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: lightGreen, width: 1.8),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              SizedBox(height: isPhone ? 10 : 15),
              SizedBox(
                width: double.infinity,
                height: isPhone ? 48 : 56,
                child: ElevatedButton.icon(
                  onPressed:
                      (isLoading || apiScanInProgress) ? null : fetchProduct,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore),
                  label: Text(
                    isLoading || apiScanInProgress
                        ? 'Scouting... please wait'
                        : (remaining > 0 ? 'Track Item' : 'Upgrade Tracking'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isPhone ? 14 : 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lightGreen,
                    foregroundColor: green,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              SizedBox(height: isPhone ? 8 : 11),
              SizedBox(
                width: double.infinity,
                height: isPhone ? 44 : 50,
                child: OutlinedButton.icon(
                  onPressed: (isRefreshing || apiScanInProgress)
                      ? null
                      : () => refreshPrices(),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    isRefreshing || apiScanInProgress
                        ? 'Scanning Prices...'
                        : 'Scan Now',
                    style: TextStyle(fontSize: isPhone ? 14 : 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cream,
                    side: BorderSide(color: cream.withOpacity(.28)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              SizedBox(height: isPhone ? 12 : 23),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tracked Items',
                    style: TextStyle(
                      color: cream,
                      fontSize: isPhone ? 23 : 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$remaining left',
                    style: TextStyle(
                      color: remaining > 0 ? lightGreen : gold,
                      fontWeight: FontWeight.bold,
                      fontSize: isPhone ? 12 : 14,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isPhone ? 8 : 13),
              Expanded(
                child: trackedItems.isEmpty
                    ? Center(
                        child: Container(
                          padding: EdgeInsets.all(isPhone ? 16 : 22),
                          decoration: BoxDecoration(
                            color: cardGreen,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: cream.withOpacity(.14)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.travel_explore,
                                color: lightGreen,
                                size: isPhone ? 34 : 42,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Scout your first deal',
                                style: TextStyle(
                                  color: cream,
                                  fontSize: isPhone ? 19 : 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Paste a product URL above. Your Scout plan includes $itemLimit tracked items.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cream.withOpacity(.68),
                                  fontSize: isPhone ? 13 : 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: trackedItems.length,
                        itemBuilder: (context, index) {
                          final item = trackedItems[index];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 17),
                            padding: EdgeInsets.all(isPhone ? 13 : 17),
                            decoration: BoxDecoration(
                              color: cardGreen,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: cream.withOpacity(.14)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.22),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: isPhone
                                ? _mobileProductCard(item, index)
                                : _desktopProductCard(item, index),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopProductCard(ProductItem item, int index) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _productImage(item, 98),
        const SizedBox(width: 16),
        Expanded(child: _productDetails(item)),
        IconButton(
          onPressed: () => removeItem(index),
          icon: Icon(Icons.delete_outline, color: cream.withOpacity(.72)),
        ),
      ],
    );
  }

  Widget _mobileProductCard(ProductItem item, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _productImage(item, 74),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cream,
                  fontSize: 17,
                  height: 1.1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              onPressed: () => removeItem(index),
              icon: Icon(Icons.delete_outline, color: cream.withOpacity(.72)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _productDetails(item, compact: true),
      ],
    );
  }

  Widget _productImage(ProductItem item, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image.network(
        item.imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: fieldGreen,
          child: Icon(Icons.shopping_bag, color: cream.withOpacity(.7)),
        ),
      ),
    );
  }

  Widget _productDetails(ProductItem item, {bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cream,
              fontSize: 21,
              height: 1.08,
              fontWeight: FontWeight.bold,
            ),
          ),
        if (item.priceDropped)
          _badge('⬇️ Price Dropped', lightGreen, green),
        const SizedBox(height: 5),
        Text(
          item.retailer,
          style: TextStyle(
            color: lightGreen,
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Current Price: \$${item.currentPrice}',
          style: TextStyle(
            color: lightGreen,
            fontSize: compact ? 18 : 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          item.originalPriceAvailable
              ? 'Original Price: \$${item.originalPrice}'
              : 'Original Price: Not available',
          style: TextStyle(
            color: cream.withOpacity(.82),
            fontSize: compact ? 14 : 16,
          ),
        ),
        Text(
          item.originalPriceAvailable
              ? 'Savings: \$${item.originalPrice - item.currentPrice}'
              : 'Savings: Tracking...',
          style: TextStyle(
            color: gold,
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        _dealResultsSection(item),
        const SizedBox(height: 9),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon(item), color: trendColor(item), size: 20),
                const SizedBox(width: 7),
                Text(
                  trendLabel(item),
                  style: TextStyle(
                    color: trendColor(item),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Text(
              'Low: \$${lowestPrice(item)}',
              style: TextStyle(
                color: cream.withOpacity(.68),
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (item.priceHistory.isNotEmpty)
          SizedBox(
            height: compact ? 44 : 52,
            child: LineChart(
              LineChartData(
                minY: lowestPrice(item).toDouble() - 5,
                maxY: highestPrice(item).toDouble() + 5,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: item.priceHistory
                        .asMap()
                        .entries
                        .map(
                          (entry) => FlSpot(
                            entry.key.toDouble(),
                            (entry.value['price'] as int).toDouble(),
                          ),
                        )
                        .toList(),
                    isCurved: true,
                    barWidth: 1.8,
                    color: cream.withOpacity(.92),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lightGreen.withOpacity(.09),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 7),
        Text(
          'Last checked: ${item.lastChecked}',
          style: TextStyle(
            color: cream.withOpacity(.58),
            fontSize: 12,
          ),
        ),
        Text(
          'Source: ${item.source}',
          style: TextStyle(
            color: cream.withOpacity(.45),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _dealResultsSection(ProductItem item) {
    if (item.dealResults.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: fieldGreen.withOpacity(.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cream.withOpacity(.12)),
        ),
        child: Text(
          'Cross-retailer deals: Searching soon...',
          style: TextStyle(
            color: cream.withOpacity(.62),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final cheapest = item.dealResults.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fieldGreen.withOpacity(.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lightGreen.withOpacity(.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cheapest.price < item.currentPrice
                ? 'Found cheaper elsewhere'
                : 'Cross-retailer prices',
            style: TextStyle(
              color: cheapest.price < item.currentPrice ? lightGreen : cream,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          ...item.dealResults.take(4).map((deal) {
            final cheaper = deal.price < item.currentPrice;
            final hasLink = deal.link.trim().isNotEmpty;

            return InkWell(
              onTap: hasLink ? () => openDealLink(deal.link) : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: cheaper
                      ? lightGreen.withOpacity(.10)
                      : cream.withOpacity(.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: cheaper
                        ? lightGreen.withOpacity(.22)
                        : cream.withOpacity(.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      cheaper ? Icons.local_offer : Icons.storefront,
                      size: 16,
                      color: cheaper ? lightGreen : cream.withOpacity(.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${deal.source}: \$${deal.price}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cheaper ? lightGreen : cream.withOpacity(.88),
                          fontSize: 13,
                          fontWeight:
                              cheaper ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasLink) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new,
                        size: 15,
                        color: cream.withOpacity(.62),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withOpacity(.88),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg.withOpacity(.88),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
