import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// NOTE:
// This full main.dart keeps your current working Nike tracking flow,
// enables safe hourly auto-scans and keeps the cross-retailer deal section.
// It calls:
//   /product
// then:
//   /search-deals
// and displays the top Google Shopping results under each tracked item.

String decodeHtmlEntities(String input) {
  var value = input;

  final namedEntities = <String, String>{
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&trade;': '™',
    '&reg;': '®',
    '&copy;': '©',
    '&nbsp;': ' ',
  };

  namedEntities.forEach((entity, replacement) {
    value = value.replaceAll(entity, replacement);
  });

  value = value.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) {
      final codePoint = int.tryParse(match.group(1) ?? '');
      if (codePoint == null) return match.group(0) ?? '';
      return String.fromCharCode(codePoint);
    },
  );

  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String formatMoney(num value) {
  final amount = value.toDouble();

  if (amount == amount.roundToDouble()) {
    return amount.toStringAsFixed(0);
  }

  return amount.toStringAsFixed(2);
}


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
  final double price;
  final String source;
  final String link;
  final String thumbnail;
  final int confidence;
  final Map<String, dynamic> verificationSignals;

  DealResult({
    required this.title,
    required this.price,
    required this.source,
    required this.link,
    required this.thumbnail,
    required this.confidence,
    required this.verificationSignals,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'price': price,
        'source': source,
        'link': link,
        'thumbnail': thumbnail,
        'confidence': confidence,
        'verificationSignals': verificationSignals,
      };

  factory DealResult.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final rawSignals = json['verificationSignals'];

    return DealResult(
      title: decodeHtmlEntities(json['title']?.toString() ?? ''),
      price: rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse((rawPrice ?? '0').toString()) ?? 0,
      source: json['source']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      confidence: json['confidence'] is num
          ? (json['confidence'] as num).round()
          : int.tryParse((json['confidence'] ?? '0').toString()) ?? 0,
      verificationSignals: rawSignals is Map
          ? Map<String, dynamic>.from(rawSignals)
          : <String, dynamic>{
              'positive': <dynamic>[],
              'warnings': <dynamic>[],
            },
    );
  }
}

class ProductItem {
  final String url;
  final String title;
  final String sku;
  final String retailer;
  final double currentPrice;
  final double originalPrice;
  final bool originalPriceAvailable;
  final String imageUrl;
  final double betterDealPrice;
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
      title: decodeHtmlEntities(json['title'] ?? 'Unknown Product'),
      sku: json['sku'] ?? '',
      retailer: json['retailer'] ?? 'Unknown',
      currentPrice: (json['currentPrice'] ?? 0).toDouble(),
      originalPrice: (json['originalPrice'] ?? 0).toDouble(),
      originalPriceAvailable: json['originalPriceAvailable'] ?? false,
      imageUrl: json['imageUrl'] ?? '',
      betterDealPrice: (json['betterDealPrice'] ?? 0).toDouble(),
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
                'price': entry.toDouble(),
                'timestamp': DateTime.now().toIso8601String(),
              };
            }

            return {
              'price': ((entry['price'] ?? 0) as num).toDouble(),
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
  final Set<String> expandedDealKeys = <String>{};
  final Set<String> expandedItemKeys = <String>{};
  List<Map<String, dynamic>> alertHistory = [];
  String notificationStatus = 'Checking notification status...';
  bool notificationPermissionRequested = false;
  String fcmStatus = 'Push registration not started';
  String? fcmToken;

  String plan = 'Scout';
  int itemLimit = 5;

  Timer? monitorTimer;
  int countdown = 3600;

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get userDoc =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  @override
  void initState() {
    super.initState();
    loadUserData();

    startMonitoring();
    requestBrowserNotificationPermission();
    registerForFcmPushNotifications();
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
    monitorTimer = Timer.periodic(const Duration(minutes: 60), (_) {
      if (!mounted) return;
      refreshPrices(autoScan: true);
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
      alertHistory = List<Map<String, dynamic>>.from(
        (data['alertHistory'] ?? []).map(
          (alert) => Map<String, dynamic>.from(alert),
        ),
      );
    });
  }

  Future<void> saveUserData() async {
    await userDoc.set({
      'email': FirebaseAuth.instance.currentUser?.email,
      'plan': plan,
      'itemLimit': itemLimit,
      'updatedAt': FieldValue.serverTimestamp(),
      'trackedItems': trackedItems.map((item) => item.toJson()).toList(),
      'alertHistory': alertHistory,
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

      final title = decodeHtmlEntities((data['title'] ?? '').toString().trim());
      final retailer = (data['retailer'] ?? '').toString().trim();
      final currentPriceValue = data['currentPrice'];

      final newPrice = currentPriceValue is num
          ? currentPriceValue.toDouble()
          : double.tryParse((currentPriceValue ?? '').toString()) ?? 0;

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
        originalPrice: rawOriginal is num ? rawOriginal.toDouble() : 0,
        originalPriceAvailable: originalAvailable == true,
        imageUrl: data['imageUrl'] ?? '',
        betterDealPrice: cheapestDeal?.price ??
            (betterDeal is Map && betterDeal['price'] is num
                ? (betterDeal['price'] as num).toDouble()
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

  List<Map<String, dynamic>> createInitialHistory(double currentPrice) {
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

  addPriceDropAlert(oldItem: item, newItem: updated);

  try {
    final userSnapshot = await userDoc.get();
    final userData = userSnapshot.data();

    final token = userData?['lastFcmToken'];

    if (token != null && token.toString().isNotEmpty) {
      final pushUrl =
          'https://sale-scout-api.onrender.com/send-price-drop-push'
          '?token=$token'
          '&title=${Uri.encodeComponent(updated.title)}'
          '&oldPrice=${item.currentPrice}'
          '&newPrice=${updated.currentPrice}';

      await http.get(Uri.parse(pushUrl));

      print('SALE SCOUT PUSH SENT');
    }
  } catch (e) {
    print('SALE SCOUT PUSH ERROR: $e');
  }
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

  Future<void> registerForFcmPushNotifications() async {
    try {
      if (!mounted) return;

      setState(() {
        fcmStatus = 'Registering browser for push alerts...';
      });

      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (!mounted) return;
        setState(() {
          fcmStatus = 'Push notifications blocked';
        });
        return;
      }

      final token = await messaging.getToken(
        vapidKey: 'BAUnjJMlnr_yr9N91NssC4gEG-o6KxaIYUsl5bqISEpA2C5GNzZZ0RGRONH13ajdG6-JKGmCMbsth9VsIxVyzEc',
      );

      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          fcmStatus = 'Push token not available yet';
        });
        return;
      }

      fcmToken = token;

      await userDoc.set({
        'lastFcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        fcmStatus = 'Push device registered';
      });

      print('FCM TOKEN SAVED: $token');
    } catch (e) {
      print('FCM REGISTRATION ERROR: $e');
      if (!mounted) return;
      setState(() {
        fcmStatus = 'Push registration failed';
      });
    }
  }

  void updateNotificationStatus() {
    if (!mounted) return;

    String status;

    if (!html.Notification.supported) {
      status = 'Browser notifications are not supported in this browser.';
    } else if (html.Notification.permission == 'granted') {
      status = 'Browser notifications allowed';
    } else if (html.Notification.permission == 'denied') {
      status = 'Browser notifications blocked';
    } else {
      status = 'Browser notifications not enabled yet';
    }

    setState(() {
      notificationStatus = status;
    });
  }

  Future<void> requestBrowserNotificationPermission() async {
    try {
      if (!html.Notification.supported) {
        updateNotificationStatus();
        return;
      }

      if (html.Notification.permission == 'default') {
        notificationPermissionRequested = true;
        await html.Notification.requestPermission();
      }

      updateNotificationStatus();
    } catch (e) {
      print('BROWSER NOTIFICATION PERMISSION ERROR: $e');
      if (!mounted) return;

      setState(() {
        notificationStatus = 'Notification permission check failed';
      });
    }
  }

  void sendTestBrowserNotification() {
    try {
      if (!html.Notification.supported) {
        showMessage('This browser does not support notifications.');
        updateNotificationStatus();
        return;
      }

      if (html.Notification.permission != 'granted') {
        showMessage('Notifications are not enabled yet.');
        requestBrowserNotificationPermission();
        return;
      }

      html.Notification(
        'Sale Scout Test Alert',
        body: 'Browser notifications are working.',
        icon: 'assets/sale_scout_logo.png',
      );

      showMessage('Test notification sent.');
      updateNotificationStatus();
    } catch (e) {
      print('TEST BROWSER NOTIFICATION ERROR: $e');
      showMessage('Test notification failed.');
    }
  }

  void sendBrowserPriceDropNotification({
    required ProductItem oldItem,
    required ProductItem newItem,
  }) {
    try {
      if (!html.Notification.supported) return;
      if (html.Notification.permission != 'granted') return;

      final savings = oldItem.currentPrice - newItem.currentPrice;

      html.Notification(
        'Sale Scout Price Drop',
        body:
            '${newItem.title} dropped from \$${formatMoney(oldItem.currentPrice)} to \$${formatMoney(newItem.currentPrice)}. Saved \$${formatMoney(savings)}.',
        icon: newItem.imageUrl.isNotEmpty ? newItem.imageUrl : null,
      );
    } catch (e) {
      print('BROWSER NOTIFICATION ERROR: $e');
    }
  }

  void addPriceDropAlert({
    required ProductItem oldItem,
    required ProductItem newItem,
  }) {
    final alert = {
      'id': '${DateTime.now().millisecondsSinceEpoch}_${oldItem.sku}_${oldItem.url}',
      'title': newItem.title,
      'retailer': newItem.retailer,
      'oldPrice': oldItem.currentPrice,
      'newPrice': newItem.currentPrice,
      'savings': oldItem.currentPrice - newItem.currentPrice,
      'url': newItem.url,
      'timestamp': DateTime.now().toIso8601String(),
      'read': false,
    };

    alertHistory.insert(0, alert);

    sendBrowserPriceDropNotification(oldItem: oldItem, newItem: newItem);

    if (alertHistory.length > 25) {
      alertHistory = alertHistory.take(25).toList();
    }
  }

  int unreadAlertCount() {
    return alertHistory.where((alert) => alert['read'] != true).length;
  }

  String formatAlertTime(String value) {
    try {
      final date = DateTime.parse(value).toLocal();
      return date.toString().substring(0, 16);
    } catch (_) {
      return 'Recently';
    }
  }

  Future<void> clearAlerts() async {
    if (!mounted) return;

    setState(() {
      alertHistory = [];
    });

    await saveUserData();
  }

  Future<void> markAlertsRead() async {
    if (alertHistory.isEmpty) return;

    setState(() {
      alertHistory = alertHistory
          .map(
            (alert) => {
              ...alert,
              'read': true,
            },
          )
          .toList();
    });

    await saveUserData();
  }

  void showAlertsSheet() {
    markAlertsRead();

    showModalBottomSheet(
      context: context,
      backgroundColor: cardGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active, color: lightGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Price Drop Alerts',
                        style: TextStyle(
                          color: cream,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (alertHistory.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          clearAlerts();
                        },
                        child: Text(
                          'Clear',
                          style: TextStyle(color: gold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (alertHistory.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No price drops yet. Sale Scout will add alerts here when tracked items fall in price.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cream.withOpacity(.68),
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: alertHistory.length,
                      itemBuilder: (context, index) {
                        final alert = alertHistory[index];
                        final title = decodeHtmlEntities(
                          alert['title']?.toString() ?? 'Tracked item',
                        );
                        final retailer =
                            alert['retailer']?.toString() ?? 'Retailer';
                        final oldPrice =
                            (alert['oldPrice'] ?? 0) is num
                                ? (alert['oldPrice'] as num).toDouble()
                                : double.tryParse(
                                      (alert['oldPrice'] ?? '0').toString(),
                                    ) ??
                                    0;
                        final newPrice =
                            (alert['newPrice'] ?? 0) is num
                                ? (alert['newPrice'] as num).toDouble()
                                : double.tryParse(
                                      (alert['newPrice'] ?? '0').toString(),
                                    ) ??
                                    0;
                        final savings =
                            (alert['savings'] ?? (oldPrice - newPrice)) is num
                                ? (alert['savings'] as num).toDouble()
                                : oldPrice - newPrice;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 9),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: fieldGreen.withOpacity(.85),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: lightGreen.withOpacity(.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.trending_down,
                                    color: lightGreen,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      '$retailer price drop',
                                      style: TextStyle(
                                        color: lightGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatAlertTime(
                                      alert['timestamp']?.toString() ?? '',
                                    ),
                                    style: TextStyle(
                                      color: cream.withOpacity(.45),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cream,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '\$${formatMoney(oldPrice)} → \$${formatMoney(newPrice)}  •  Saved \$${formatMoney(savings)}',
                                style: TextStyle(
                                  color: gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
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

  double lowestPrice(ProductItem item) {
    if (item.priceHistory.isEmpty) return item.currentPrice;

    return item.priceHistory.map((entry) => (entry['price'] as num).toDouble()).reduce(min);
  }

  double bestCurrentMarketPrice(ProductItem item) {
    final marketPrices = <double>[item.currentPrice];

    for (final deal in item.dealResults) {
      if (deal.price > 0) {
        marketPrices.add(deal.price);
      }
    }

    return marketPrices.reduce(min);
  }

  String bestCurrentMarketStore(ProductItem item) {
    final bestPrice = bestCurrentMarketPrice(item);

    if ((item.currentPrice - bestPrice).abs() < 0.01) {
      return item.retailer;
    }

    for (final deal in item.dealResults) {
      if ((deal.price - bestPrice).abs() < 0.01) {
        return deal.source.isNotEmpty ? deal.source : 'Retailer';
      }
    }

    return item.retailer;
  }

  bool hasBetterMarketDeal(ProductItem item) {
    return bestCurrentMarketPrice(item) < item.currentPrice;
  }

  double highestPrice(ProductItem item) {
    if (item.priceHistory.isEmpty) return item.currentPrice;

    return item.priceHistory.map((entry) => (entry['price'] as num).toDouble()).reduce(max);
  }

  double averagePrice(ProductItem item) {
    if (item.priceHistory.isEmpty) {
      return item.currentPrice.toDouble();
    }

    final prices = item.priceHistory
        .map((entry) => (entry['price'] as num).toDouble())
        .toList();

    final total = prices.reduce((a, b) => a + b);

    return total / prices.length;
  }

  int averageDifference(ProductItem item) {
    final avg = averagePrice(item);

    if (avg <= 0) return 0;

    return (((item.currentPrice - avg) / avg) * 100).round();
  }

  String smartPriceInsight(ProductItem item) {
    if (item.priceHistory.length < 2) {
      return 'Building price history';
    }

    final difference = averageDifference(item);

    if (difference <= -10) {
      return '${difference.abs()}% below average';
    }

    if (difference >= 10) {
      return '${difference.abs()}% above average';
    }

    return 'Near average price';
  }

  Color smartPriceInsightColor(ProductItem item) {
    final difference = averageDifference(item);

    if (difference <= -10) return lightGreen;
    if (difference >= 10) return Colors.redAccent;

    return cream.withOpacity(.72);
  }

  String trendLabel(ProductItem item) {
    if (item.priceHistory.length < 2) return 'Tracking';

    final last = (item.priceHistory.last['price'] as num).toDouble();
    final previous =
        (item.priceHistory[item.priceHistory.length - 2]['price'] as num).toDouble();

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

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Widget _notificationStatusCard(bool isPhone) {
    final allowed = notificationStatus == 'Browser notifications allowed';
    final blocked = notificationStatus == 'Browser notifications blocked';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fieldGreen.withOpacity(.82),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: allowed
              ? lightGreen.withOpacity(.28)
              : blocked
                  ? Colors.redAccent.withOpacity(.32)
                  : gold.withOpacity(.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            allowed
                ? Icons.notifications_active
                : blocked
                    ? Icons.notifications_off
                    : Icons.notifications_none,
            color: allowed
                ? lightGreen
                : blocked
                    ? Colors.redAccent
                    : gold,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notificationStatus,
                  style: TextStyle(
                    color: cream.withOpacity(.82),
                    fontSize: isPhone ? 12 : 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fcmStatus,
                  style: TextStyle(
                    color: cream.withOpacity(.55),
                    fontSize: isPhone ? 10 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: allowed
                ? sendTestBrowserNotification
                : requestBrowserNotificationPermission,
            style: TextButton.styleFrom(
              foregroundColor: allowed ? green : cream,
              backgroundColor: allowed ? lightGreen : Colors.white.withOpacity(.06),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: Text(
              allowed ? 'Test' : 'Enable',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardGreen,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cream.withOpacity(.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.18),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cream,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cream.withOpacity(.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? lightGreen.withOpacity(.17) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? lightGreen.withOpacity(.28) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? lightGreen : cream.withOpacity(.68),
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? cream : cream.withOpacity(.68),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ),
            if (label == 'Alerts' && unreadAlertCount() > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: gold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  unreadAlertCount().toString(),
                  style: TextStyle(
                    color: green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(String email) {
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF07130E),
        border: Border(
          right: BorderSide(color: cream.withOpacity(.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 112,
                  child: Image.asset(
                    'assets/sale_scout_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'SALE SCOUT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cream,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Shopping Intelligence',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: lightGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _navItem(icon: Icons.dashboard_rounded, label: 'Dashboard', selected: true),
          _navItem(icon: Icons.bookmark_rounded, label: 'Tracked Items', onTap: () => showMessage('Tracked items are shown in the main dashboard.')),
          _navItem(icon: Icons.notifications_active_rounded, label: 'Alerts', onTap: showAlertsSheet),
          _navItem(icon: Icons.local_offer_rounded, label: 'Market Deals', onTap: () => showMessage('Market deals are inside each tracked item.')),
          _navItem(icon: Icons.settings_rounded, label: 'Settings', onTap: sendTestBrowserNotification),
          const Spacer(),
          _notificationStatusCard(false),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: fieldGreen.withOpacity(.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cream.withOpacity(.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cream.withOpacity(.70),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: logout,
                    icon: const Icon(Icons.logout, size: 15),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cream,
                      side: BorderSide(color: cream.withOpacity(.18)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topActionBar({
    required bool isPhone,
    required int remaining,
  }) {
    return Container(
      padding: EdgeInsets.all(isPhone ? 10 : 14),
      decoration: BoxDecoration(
        color: cardGreen,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cream.withOpacity(.12)),

      ),
      child: isPhone
          ? Column(
              children: [
                _urlInput(remaining, isPhone),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _trackButton(remaining, isPhone)),
                    const SizedBox(width: 8),
                    Expanded(child: _scanButton(isPhone)),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 5, child: _urlInput(remaining, isPhone)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _trackButton(remaining, isPhone)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _scanButton(isPhone)),
              ],
            ),
    );
  }

  Widget _urlInput(int remaining, bool isPhone) {
    return TextField(
      controller: urlController,
      style: TextStyle(color: cream, fontSize: isPhone ? 14 : 15),
      decoration: InputDecoration(
        hintText: remaining > 0 ? 'Paste product URL...' : 'Scout item limit reached',
        hintStyle: TextStyle(color: cream.withOpacity(.52)),
        prefixIcon: Icon(Icons.link, color: cream.withOpacity(.64)),
        filled: true,
        fillColor: fieldGreen,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isPhone ? 12 : 14,
        ),
        enabled: remaining > 0 && !apiScanInProgress,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: cream.withOpacity(.18)),
          borderRadius: BorderRadius.circular(16),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: gold.withOpacity(.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightGreen, width: 1.8),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _trackButton(int remaining, bool isPhone) {
    return SizedBox(
      height: isPhone ? 54 : 50,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (isLoading || apiScanInProgress || remaining <= 0)
            ? null
            : fetchProduct,
        icon: isLoading
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.travel_explore, size: 18),
        label: Text(
          isLoading || apiScanInProgress
              ? 'Scouting...'
              : (remaining > 0 ? 'Track Item' : 'Upgrade'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isPhone ? 14 : 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: lightGreen,
          foregroundColor: green,
          disabledBackgroundColor: lightGreen.withOpacity(.38),
          disabledForegroundColor: green.withOpacity(.55),
          elevation: 0,
          minimumSize: Size(double.infinity, isPhone ? 54 : 50),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _scanButton(bool isPhone) {
    return SizedBox(
      height: isPhone ? 54 : 50,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: (isRefreshing || apiScanInProgress)
            ? null
            : () => refreshPrices(),
        icon: isRefreshing || apiScanInProgress
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 18),
        label: Text(
          isRefreshing || apiScanInProgress ? 'Scanning...' : 'Scan Now',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isPhone ? 14 : 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: cream,
          disabledForegroundColor: cream.withOpacity(.45),
          side: BorderSide(color: cream.withOpacity(.22)),
          minimumSize: Size(double.infinity, isPhone ? 54 : 50),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _alertsBanner() {
    if (alertHistory.isEmpty) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: showAlertsSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: fieldGreen.withOpacity(.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: lightGreen.withOpacity(.24)),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_active, color: lightGreen, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                unreadAlertCount() > 0
                    ? '${unreadAlertCount()} new price-drop alert${unreadAlertCount() == 1 ? '' : 's'}'
                    : '${alertHistory.length} saved price-drop alert${alertHistory.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: cream,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_up, color: cream.withOpacity(.55), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _trackedItemsList(bool isPhone) {
    if (trackedItems.isEmpty) {
      return Center(
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
              Icon(Icons.travel_explore, color: lightGreen, size: isPhone ? 34 : 42),
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
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: trackedItems.length,
      itemBuilder: (context, index) {
        final item = trackedItems[index];
        return RepaintBoundary(
          child: _trackedItemCard(item, index, isPhone: isPhone),
        );
      },
    );
  }

  String _itemExpansionKey(ProductItem item) => item.url.isNotEmpty ? item.url : item.title;

  void _toggleItemExpanded(ProductItem item) {
    final key = _itemExpansionKey(item);
    setState(() {
      if (expandedItemKeys.contains(key)) {
        expandedItemKeys.remove(key);
      } else {
        expandedItemKeys.add(key);
      }
    });
  }

  Widget _trackedItemCard(
    ProductItem item,
    int index, {
    required bool isPhone,
  }) {
    final expanded = expandedItemKeys.contains(_itemExpansionKey(item));
    final bestMarketPrice = bestCurrentMarketPrice(item);
    final bestMarketStore = bestCurrentMarketStore(item);
    final hasBetterDeal = hasBetterMarketDeal(item);
    final savings = item.originalPriceAvailable
        ? item.originalPrice - item.currentPrice
        : max(0, item.currentPrice - bestMarketPrice);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isPhone ? 10 : 12),
      decoration: BoxDecoration(
        color: cardGreen,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: expanded ? gold.withOpacity(.35) : cream.withOpacity(.12),
        ),

      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleItemExpanded(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _productImage(item, isPhone ? 54 : 64),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: isPhone ? 4 : 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: isPhone ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cream,
                            fontSize: isPhone ? 15 : 17,
                            height: 1.08,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.retailer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: lightGreen,
                            fontSize: isPhone ? 12 : 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isPhone) ...[
                    const SizedBox(width: 10),
                    _compactPriceColumn(
                      label: 'Current',
                      value: '\$${formatMoney(item.currentPrice)}',
                      accent: lightGreen,
                    ),
                    const SizedBox(width: 18),
                    _compactPriceColumn(
                      label: 'Best',
                      value: '\$${formatMoney(bestMarketPrice)}',
                      subLabel: bestMarketStore,
                      accent: hasBetterDeal ? gold : cream,
                    ),
                    const SizedBox(width: 14),
                    if (savings > 0)
                      _smallSavingsPill('\$${formatMoney(savings)}'),
                  ] else ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${formatMoney(item.currentPrice)}',
                          style: TextStyle(
                            color: lightGreen,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Best \$${formatMoney(bestMarketPrice)}',
                          style: TextStyle(
                            color: hasBetterDeal ? gold : cream.withOpacity(.58),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(width: 10),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: cream.withOpacity(.72),
                    size: 24,
                  ),
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: () => removeItem(index),
                    icon: Icon(Icons.delete_outline, color: cream.withOpacity(.64), size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            Divider(color: cream.withOpacity(.10), height: 1),
            const SizedBox(height: 10),
            _productDetails(item, compact: true),
          ],
        ],
      ),
    );
  }

  Widget _compactPriceColumn({
    required String label,
    required String value,
    String? subLabel,
    required Color accent,
  }) {
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cream.withOpacity(.58),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subLabel != null) ...[
            const SizedBox(height: 1),
            Text(
              subLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cream.withOpacity(.58),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallSavingsPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: lightGreen.withOpacity(.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: lightGreen.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.south_rounded, color: lightGreen, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: lightGreen,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileHeader(String email) {
    return Row(
      children: [
        Image.asset(
          'assets/sale_scout_logo.png',
          height: 46,
          width: 46,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SALE SCOUT',
                style: TextStyle(
                  color: cream,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cream.withOpacity(.58), fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: showAlertsSheet,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_active, color: lightGreen),
              if (unreadAlertCount() > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: gold,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unreadAlertCount().toString(),
                        style: TextStyle(
                          color: green,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: logout,
          icon: Icon(Icons.logout, color: cream.withOpacity(.78)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final remaining = itemLimit - trackedItems.length;
    final width = MediaQuery.of(context).size.width;
    final isPhone = width < 700;
    final useSidebar = width >= 900;
    final bestMarket = trackedItems.isEmpty
        ? 0.0
        : trackedItems.map(bestCurrentMarketPrice).reduce(min);

    final mainContent = Padding(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 14 : 20,
        isPhone ? 10 : 18,
        isPhone ? 14 : 22,
        isPhone ? 12 : 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDropAlert)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
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
          if (!useSidebar) ...[
            _mobileHeader(email),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        color: cream,
                        fontSize: isPhone ? 24 : 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Track products, compare the market, and catch price drops.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cream.withOpacity(.58),
                        fontSize: isPhone ? 12 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (useSidebar)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('🎖 $plan Plan', lightGreen, green),
                    _pill('Watching ${trackedItems.length}/$itemLimit', cream, green),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          _topActionBar(isPhone: isPhone, remaining: remaining),
          const SizedBox(height: 14),
          if (!isPhone)
            Row(
              children: [
                _dashboardStatCard(
                  icon: Icons.remove_red_eye_rounded,
                  label: 'Tracked Items',
                  value: '${trackedItems.length}/$itemLimit',
                  accent: lightGreen,
                ),
                const SizedBox(width: 12),
                _dashboardStatCard(
                  icon: Icons.notifications_active_rounded,
                  label: 'Unread Alerts',
                  value: unreadAlertCount().toString(),
                  accent: gold,
                ),
                const SizedBox(width: 12),
                _dashboardStatCard(
                  icon: Icons.local_offer_rounded,
                  label: 'Best Market',
                  value: trackedItems.isEmpty ? '—' : '\$${formatMoney(bestMarket)}',
                  accent: lightGreen,
                ),
                const SizedBox(width: 12),
                _dashboardStatCard(
                  icon: apiScanInProgress ? Icons.sync_rounded : Icons.check_circle_rounded,
                  label: 'Monitoring',
                  value: apiScanInProgress ? 'Scanning' : 'Active',
                  accent: apiScanInProgress ? gold : lightGreen,
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('🎖 $plan Plan', lightGreen, green),
                _pill('Watching ${trackedItems.length}/$itemLimit', cream, green),
                _pill(apiScanInProgress ? '🟡 Scan Running' : '🟢 Monitoring Active', fieldGreen, cream),
              ],
            ),
          if (!isPhone) const SizedBox(height: 14) else const SizedBox(height: 10),
          if (!useSidebar) ...[
            _notificationStatusCard(isPhone),
            const SizedBox(height: 10),
          ],
          _alertsBanner(),
          if (alertHistory.isNotEmpty) const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tracked Items',
                style: TextStyle(
                  color: cream,
                  fontSize: isPhone ? 21 : 24,
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
          const SizedBox(height: 8),
          Expanded(child: _trackedItemsList(isPhone)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: green,
      body: SafeArea(
        child: useSidebar
            ? Row(
                children: [
                  _sidebar(email),
                  Expanded(child: mainContent),
                ],
              )
            : mainContent,
      ),
    );
  }

  Widget _desktopProductCard(ProductItem item, int index) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _productImage(item, 86),
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
            _productImage(item, 64),
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
        gaplessPlayback: true,
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
          'Current Price: \$${formatMoney(item.currentPrice)}',
          style: TextStyle(
            color: lightGreen,
            fontSize: compact ? 18 : 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          item.originalPriceAvailable
              ? 'Original Price: \$${formatMoney(item.originalPrice)}'
              : 'Original Price: Not available',
          style: TextStyle(
            color: cream.withOpacity(.82),
            fontSize: compact ? 14 : 16,
          ),
        ),
        Text(
          item.originalPriceAvailable
              ? 'Savings: \$${formatMoney(item.originalPrice - item.currentPrice)}'
              : 'Savings: Tracking...',
          style: TextStyle(
            color: gold,
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            _badge(
              'Lowest ${item.retailer} Seen: \$${formatMoney(lowestPrice(item))}',
              fieldGreen,
              cream,
            ),
            _badge(
              'Best Market: \$${formatMoney(bestCurrentMarketPrice(item))} at ${bestCurrentMarketStore(item)}',
              hasBetterMarketDeal(item) ? lightGreen : fieldGreen,
              hasBetterMarketDeal(item) ? green : cream,
            ),
            if (hasBetterMarketDeal(item))
              _badge(
                '💸 Better deal found',
                lightGreen,
                green,
              )
            else if ((item.currentPrice - lowestPrice(item)).abs() < 0.01)
              _badge(
                '🔥 Lowest ${item.retailer} price we’ve seen',
                lightGreen,
                green,
              ),
          ],
        ),
        const SizedBox(height: 7),
        _dealResultsSection(item),
        const SizedBox(height: 7),
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
              'Low: \$${formatMoney(lowestPrice(item))}',
              style: TextStyle(
                color: cream.withOpacity(.68),
                fontSize: 13,
              ),
            ),
            Text(
              'High: \$${formatMoney(highestPrice(item))}',
              style: TextStyle(
                color: cream.withOpacity(.68),
                fontSize: 13,
              ),
            ),
            Text(
              'Avg: \$${formatMoney(averagePrice(item))}',
              style: TextStyle(
                color: cream.withOpacity(.68),
                fontSize: 13,
              ),
            ),
            Text(
              smartPriceInsight(item),
              style: TextStyle(
                color: smartPriceInsightColor(item),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (item.priceHistory.isNotEmpty)
          SizedBox(
            height: compact ? 32 : 40,
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
                            (entry.value['price'] as num).toDouble(),
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


  Future<void> openDealLink(String link) async {
    final trimmedLink = link.trim();

    if (trimmedLink.isEmpty) {
      showMessage('No retailer link available for this deal yet.');
      return;
    }

    final uri = Uri.tryParse(trimmedLink);

    if (uri == null || !uri.hasScheme) {
      showMessage('Invalid retailer link.');
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        showMessage('Could not open retailer link.');
      }
    } catch (e) {
      print('OPEN DEAL LINK ERROR: $e');
      showMessage('Could not open retailer link.');
    }
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
          'Cross-retailer deals: Searching...' ,
          style: TextStyle(
            color: cream.withOpacity(.62),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final bestMatches =
        item.dealResults.where((deal) => deal.confidence >= 80).toList();

    final possibleMatches =
        item.dealResults.where((deal) => deal.confidence < 80).toList();

    Widget dealRow(DealResult deal) {
      final dealKey =
          '${deal.source}|${deal.link}|${deal.title}|${deal.price}';
      final expanded = expandedDealKeys.contains(dealKey);
      final cheaper = deal.price < item.currentPrice;

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            setState(() {
              if (expanded) {
                expandedDealKeys.remove(dealKey);
              } else {
                expandedDealKeys.add(dealKey);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: cream.withOpacity(.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      cheaper ? Icons.local_offer : Icons.storefront,
                      size: 15,
                      color: cheaper ? lightGreen : cream.withOpacity(.6),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${deal.source} • \$${formatMoney(deal.price)} • ${deal.confidence}%',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              cheaper ? lightGreen : cream.withOpacity(.84),
                          fontSize: 12,
                          fontWeight:
                              cheaper ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: cream.withOpacity(.55),
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => openDealLink(deal.link),
                      style: TextButton.styleFrom(
                        foregroundColor: green,
                        backgroundColor: lightGreen,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Open',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (expanded) ...[
                  if (deal.title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cream.withOpacity(.58),
                        fontSize: 11,
                        height: 1.15,
                      ),
                    ),
                  ],
                  _verificationSignalsChips(deal),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final shownDeals = [
      ...bestMatches.take(4),
      ...possibleMatches.take(bestMatches.isEmpty ? 3 : 2),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: fieldGreen.withOpacity(.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lightGreen.withOpacity(.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Retailer matches',
                style: TextStyle(
                  color: lightGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${item.dealResults.length} found',
                style: TextStyle(
                  color: cream.withOpacity(.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...shownDeals.map(dealRow),
        ],
      ),
    );
  }
  List<String> _signalList(Map<String, dynamic> signals, String key) {
    final raw = signals[key];

    if (raw is List) {
      return raw.map((signal) => signal.toString()).toList();
    }

    return [];
  }

  Widget _verificationSignalsChips(DealResult deal) {
    final positives = _signalList(deal.verificationSignals, 'positive');
    final warnings = _signalList(deal.verificationSignals, 'warnings');

    if (positives.isEmpty && warnings.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget chip({
      required String text,
      required IconData icon,
      required Color color,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.72)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ...positives.map(
            (signal) => chip(
              text: signal,
              icon: Icons.check_circle,
              color: lightGreen,
            ),
          ),
          ...warnings.map(
            (signal) => chip(
              text: signal,
              icon: Icons.warning_amber_rounded,
              color: gold,
            ),
          ),
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
