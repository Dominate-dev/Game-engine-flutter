# Task 05 — Core Presentation Layer (`BaseState`, `BaseDialog`, `BaseSheet`)

Depends on: Task 00, 02 (uses `networkInfoProvider`).

## Prompt for Cursor

```
Inside lib/core/presentation/, create four files so every screen in the app
gets toast/snackbar/dialog/bottom-sheet helpers for free instead of calling
ScaffoldMessenger/showDialog directly.

1. ui_helpers_interface.dart
   - enum ToastType { success, error, info, warning }
   - abstract class UIHelpersInterface with these method signatures:
     - void showToast(String message, {ToastType type = ToastType.info})
     - void showAppSnackBar(String message, {ToastType type = ToastType.info,
       Duration duration = const Duration(seconds: 3)})
     - Future<T?> showAppDialog<T>({required Widget child,
       bool barrierDismissible = true})
     - Future<T?> showAppBottomSheet<T>({required Widget child,
       bool isScrollControlled = true})
     - Future<bool> checkInternetConnection()

2. base_dialog.dart
   - `BaseDialog` StatelessWidget: optional title (String?), required
     content (Widget), optional actions (List<Widget>?), rounded corners
     (16 radius), padding default EdgeInsets.all(20). Lay out title (if
     present) centered above content, actions row right-aligned at the
     bottom (if present).
   - `ConfirmDialog` StatelessWidget built on top of BaseDialog: title,
     message, confirmText='Confirm', cancelText='Cancel'. Cancel button
     pops `false`, confirm button pops `true`.

3. base_sheet.dart
   - `BaseSheet` StatelessWidget: optional title, required child, default
     padding EdgeInsets.fromLTRB(20,12,20,24). Wrap in SafeArea, show a
     small centered drag-handle bar (40x4, rounded, divider color) above
     the optional title and the child.

4. base_page.dart
   - `abstract class BaseState<T extends ConsumerStatefulWidget>
     extends ConsumerState<T> implements UIHelpersInterface`
   - Declares `Widget buildPage(BuildContext context)` and implements
     `build(context) => buildPage(context)` — screens override buildPage,
     never build.
   - showToast: use package:fluttertoast (Fluttertoast.showToast),
     LENGTH_SHORT, gravity BOTTOM, background color from a private
     `_colorForType` helper (success=green.shade600, error=red.shade600,
     warning=orange.shade700, info=blueGrey.shade700), white text.
   - showAppSnackBar: guard on `mounted`, use
     ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(...)
     with the same color mapping, floating behavior, rounded shape (10).
   - showAppDialog: showDialog(context, barrierDismissible, builder
     returning the passed child directly).
   - showConfirmDialog(title, message, confirmText, cancelText) helper
     (not from the interface, just convenient) that calls showAppDialog
     with a ConfirmDialog and returns `result ?? false`.
   - showAppBottomSheet: showModalBottomSheet with rounded top corners
     (20 radius) and wraps the child in BaseSheet.
   - checkInternetConnection: `ref.read(networkInfoProvider).isConnected`
     (import from core/network/network_info_provider.dart, Task 02).

Every screen created from now on MUST extend BaseState<T> and implement
buildPage(), never extend ConsumerState directly.
```

## Acceptance criteria
- [ ] No screen anywhere in the project calls `ScaffoldMessenger.of(context).showSnackBar` or `showDialog(` directly — only through `BaseState` methods
- [ ] `showConfirmDialog` returns a plain `bool`, never `bool?`
- [ ] `checkInternetConnection()` reads through `networkInfoProvider`, not a duplicate connectivity check
