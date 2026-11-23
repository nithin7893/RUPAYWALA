import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api/api.dart';
import 'core/state/app_scope.dart';
import 'core/state/session_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/phone_input_screen.dart';
import 'features/shell/role_shell.dart';
import 'widgets/brand_mark.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(const RupaywalaApp());
}

class RupaywalaApp extends StatefulWidget {
  const RupaywalaApp({super.key, this.api});

  final Api? api;

  @override
  State<RupaywalaApp> createState() => _RupaywalaAppState();
}

class _RupaywalaAppState extends State<RupaywalaApp> {
  late final Api _api = widget.api ?? Api();
  late final SessionController _session = SessionController(_api);

  @override
  void initState() {
    super.initState();
    // Restoring here, rather than on the login screen, is what makes a cold
    // start return an already signed-in user to their dashboard.
    _session.restore();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rupaywala',
      theme: buildAppTheme(),
      builder: (context, child) {
        // The user's accessibility text scale is respected as-is. Layouts use
        // wrapping, flexible rows and scroll views instead of clamping it,
        // which used to make large-text users see text smaller than they asked
        // for.
        return AppScope(
          api: _api,
          session: _session,
          child: child!,
        );
      },
      home: const _SessionGate(),
    );
  }
}

/// Decides between the splash, the auth flow and the role shell.
///
/// This is the only place role routing happens.
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final session = context.session;

    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => AnimatedSwitcher(
        duration: kMediumAnimation,
        child: switch (session.status) {
          SessionStatus.restoring => const _SplashScreen(),
          SessionStatus.signedOut =>
            const PhoneInputScreen(key: ValueKey('auth')),
          SessionStatus.signedIn =>
            RoleShell(key: ValueKey('shell-${session.role!.wireName}')),
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 130;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(size: compact ? 56 : 76),
                SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xxl),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
