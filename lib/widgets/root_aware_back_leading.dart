import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';

/// Defence in depth for issue #35 ("There is no back button, anywhere!").
///
/// Most in-app navigation uses `context.push(...)`, so the AppBar's
/// automatic back button appears and everything is fine. The trap is
/// arriving somewhere through `context.go(...)`: that *replaces* the
/// whole stack, nothing sits below the new page, and the AppBar draws
/// no leading at all — on a destination screen with no home affordance
/// of its own the user is stranded and has to restart the app.
///
/// [rootAwareBackLeading] is meant to be passed straight to
/// `AppBar(leading: ...)`. It returns `null` whenever Flutter would
/// have drawn its own back button (a non-null `leading` *suppresses*
/// that automatic button, so returning null is what lets the normal
/// behaviour through), and otherwise returns a "back to home" button
/// that sends the user to `/`.
///
/// The "would Flutter draw a back button?" question is answered with the
/// very predicate AppBar itself uses — [ModalRoute.impliesAppBarDismissal]
/// — so the two can never disagree.
Widget? rootAwareBackLeading(BuildContext context, {VoidCallback? onGoHome}) {
  if (canDismissRoute(context)) return null;
  return RootHomeButton(onPressed: onGoHome);
}

/// Whether the enclosing route can be dismissed — i.e. whether the
/// AppBar would render its own back (or close) button for it.
bool canDismissRoute(BuildContext context) {
  // Explicit type argument: `strict-inference` in analysis_options.yaml
  // makes an un-inferrable generic invocation an error.
  final ModalRoute<Object?>? route = ModalRoute.of<Object?>(context);
  if (route != null) return route.impliesAppBarDismissal;
  return Navigator.maybeOf(context)?.canPop() ?? false;
}

/// The fallback leading: a home button that resets the router to `/`.
class RootHomeButton extends StatelessWidget {
  const RootHomeButton({super.key, this.onPressed});

  /// Overrides the default `context.go('/')`. Only used by tests and by
  /// callers that need to run cleanup before leaving.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.home_outlined),
      tooltip: AppLocalizations.of(context).navBackToHome,
      onPressed: onPressed ?? () => context.go('/'),
    );
  }
}
