import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/home/home_screen.dart';
import 'state/app_controller.dart';
import 'state/call_controller.dart';
import 'state/group_call_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/flow_chat_logo.dart';
import 'widgets/call_overlay.dart';
import 'widgets/group_call_overlay.dart';

class FlowChatApp extends StatelessWidget {
  const FlowChatApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider<CallController>.value(
          value: controller.callController,
        ),
        ChangeNotifierProvider<GroupCallController>.value(
          value: controller.groupCallController,
        ),
      ],
      child: Consumer<AppController>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'FlowChat',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: state.isDark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => Stack(
              children: [?child, const CallOverlay(), const GroupCallOverlay()],
            ),
            initialRoute: '/',
            routes: {
              '/': (_) => const _AuthGate(),
              SignInScreen.routeName: (_) => const SignInScreen(),
              SignUpScreen.routeName: (_) => const SignUpScreen(),
              ForgotPasswordScreen.routeName: (_) =>
                  const ForgotPasswordScreen(),
            },
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    if (state.isInitializing) return const _SplashScreen();
    if (state.currentUser == null) return const SignInScreen();
    return const HomeScreen();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowChatLogo(size: 68),
                SizedBox(height: 28),
                SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
