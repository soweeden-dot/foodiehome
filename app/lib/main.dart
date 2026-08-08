import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseKey,
    // This project is shared with Keep Track ("Katie"), which owns the
    // default `public` schema. Every Foodie table/RPC lives in the
    // dedicated `foodie` schema, so all .from()/.rpc() calls made through
    // this client are scoped there by default. Auth, Storage, and Realtime
    // are separate APIs and are unaffected by this setting.
    postgrestOptions: const PostgrestClientOptions(schema: 'foodie'),
  );

  runApp(const ProviderScope(child: FoodieHomeApp()));
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Missing configuration.\n\nRun with:\n'
            '--dart-define=SUPABASE_URL=...\n'
            '--dart-define=SUPABASE_ANON_KEY=...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
