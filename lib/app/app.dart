import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class AstrolokApp extends StatelessWidget {
  const AstrolokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Astrolok',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
    );
  }
}
