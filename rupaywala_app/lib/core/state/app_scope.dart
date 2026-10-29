import 'package:flutter/widgets.dart';

import '../api/api.dart';
import 'session_controller.dart';

/// Provides [Api] and [SessionController] to the application tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.session,
    required super.child,
  });

  final Api api;
  final SessionController session;

  static Api apiOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!.api;
  }

  static SessionController sessionOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!.session;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return oldWidget.api != api || oldWidget.session != session;
  }
}

extension AppScopeContext on BuildContext {
  Api get api => AppScope.apiOf(this);

  SessionController get session => AppScope.sessionOf(this);
}
