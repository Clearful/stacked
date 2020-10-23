import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stacked_themes/src/locator_setup.dart';
import 'package:stacked_themes/src/services/shared_preferences_service.dart';
import 'package:stacked_themes/src/services/statusbar_service.dart';
import 'package:stacked_themes/src/theme_service.dart';

const String SelectedTheme = 'selected-theme';
const String DarkTheme = 'dark-theme';

/// Provides functionality to manage the current theme for the application
class ThemeManager {
  final _sharedPreferences = locator<SharedPreferencesService>();
  final _statusBarService = locator<StatusBarService>();

  /// Has to be called before  we make use of the theme manager
  static Future initialise() async {
    WidgetsFlutterBinding.ensureInitialized();
    await setupLocator();
  }

  /// A list of themes that the application can swap to
  final List<ThemeData> themes;

  /// The theme to be used when not using the darkTheme
  final ThemeData lightTheme;

  /// The theme to be used when not using the lightTheme
  final ThemeData darkTheme;

  /// The default theme mode to use for the application when the application is frst used.
  ///
  /// When using system all previously user selected theme will be cleared in favor of the system.
  final ThemeMode defaultTheme;

  ThemeMode _selectedThemeMode;

  /// Returns the current selected theme mode
  ThemeMode get selectedThemeMode => _selectedThemeMode;

  /// A builder function that provides you with the new selected theme that expects you to
  /// return a color for the status bar.
  final Color Function(ThemeData) statusBarColorBuilder;

  BehaviorSubject<ThemeModel> _themesController;

  Stream<ThemeModel> get themesStream => _themesController.stream;

  /// Returns true if the ThemeMode is dark. This does not apply when you're using system as ThemeMode
  bool get isDarkMode => _selectedThemeMode == ThemeMode.dark;

  /// My code
  Brightness _lastBrightness;
  Brightness get lastBrightness => _lastBrightness;
  set lastBrigtness(Brightness newBrightness) =>
      _lastBrightness = newBrightness;

  ThemeManager({
    this.themes,
    this.statusBarColorBuilder,
    this.darkTheme,
    this.lightTheme,
    this.defaultTheme = ThemeMode.system,
  }) {
    var hasMultipleThemes = themes != null && themes.length > 1;
    var hasLightAndDarkThemes = darkTheme != null && lightTheme != null;
    assert(hasMultipleThemes || hasLightAndDarkThemes,
        '''You have to supply themes if you want to use themes. You have supplied no themes. Don\'t do that. Supply themes.
You can supply either a list of ThemeData objects to the themes property or a lightTheme and a darkTheme to be swapped between.
        ''');

    var storedThemeIndex = _sharedPreferences.themeIndex;

    ThemeData selectedTheme;

    if (hasMultipleThemes) {
      if (storedThemeIndex != null) {
        try {
          selectedTheme = themes[storedThemeIndex];
        } catch (e) {
          print(
              '''WARNING: You have changed your number of themes. Because of this we will clear your previously selected
        theme and broadcast the first theme in your list of themes.''');
          _sharedPreferences.themeIndex = null;
          selectedTheme = themes.first;
        }
      } else {
        selectedTheme = themes.first;
      }
      _applyStatusBarColor(selectedTheme);
    } else {
      _selectedThemeMode = defaultTheme;

      var savedUserThemeMode = _sharedPreferences.userThemeMode;
      if (savedUserThemeMode != null) {
        _selectedThemeMode = savedUserThemeMode;
      }

      selectedTheme =
          _selectedThemeMode == ThemeMode.dark ? darkTheme : lightTheme;
      _applyStatusBarColor(selectedTheme);
    }

    _lastBrightness = _getCurrentBrightness();

    _themesController = BehaviorSubject<ThemeModel>.seeded(
      ThemeModel(
          selectedTheme: selectedTheme,
          darkTheme: darkTheme,
          themeMode: _selectedThemeMode),
    );

    ThemeService.getInstance().setThemeManager(this);
  }

  /// Sets the theme for the application equal to the theme at the index
  /// in the list of [themes] supplied to the [ThemeBuilder]
  Future selectThemeAtIndex(int themeIndex) async {
    var theme = themes[themeIndex];
    await _applyStatusBarColor(theme);

    _themesController.add(ThemeModel(
      selectedTheme: theme,
      darkTheme: darkTheme,
      themeMode: _selectedThemeMode,
    ));

    _sharedPreferences.themeIndex = themeIndex;
  }

  Future _applyStatusBarColor(ThemeData theme) async {
    var statusBarColor = statusBarColorBuilder?.call(theme);
    if (statusBarColor != null) {
      await _statusBarService.updateStatusBarColor(statusBarColor);
    }
  }

  /// Swaps between the light and dark ThemeMode
  void toggleDarkLightTheme() {
    _selectedThemeMode =
        _selectedThemeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;

    _applyStatusBarColor(
        _selectedThemeMode == ThemeMode.dark ? darkTheme : lightTheme);

    _themesController.add(ThemeModel(
      selectedTheme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _selectedThemeMode,
    ));
  }

  void setThemeMode(ThemeMode themeMode) {
    _selectedThemeMode = themeMode;

    _sharedPreferences.userThemeMode = themeMode;

    if (themeMode != ThemeMode.system) {
      _applyStatusBarColor(
          _selectedThemeMode == ThemeMode.dark ? darkTheme : lightTheme);
      // My code
      _setStatusBarColor(isDarkMode: _selectedThemeMode == ThemeMode.dark);
    } else {
      // My code
      // final currentBrightness =
      //     SchedulerBinding.instance.window.platformBrightness;
      final currentBrightness = _getCurrentBrightness();
      _applyStatusBarColor(
          currentBrightness == Brightness.dark ? darkTheme : lightTheme);
      // My code
      _setStatusBarColor(isDarkMode: currentBrightness == Brightness.dark);
    }

    _themesController.add(ThemeModel(
      selectedTheme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _selectedThemeMode,
    ));
  }

  Brightness _getCurrentBrightness() {
    return SchedulerBinding.instance.window.platformBrightness;
  }

  _setStatusBarColor({@required bool isDarkMode}) {
    if ((isDarkMode && lastBrightness == Brightness.dark) ||
        (!isDarkMode && lastBrightness == Brightness.light)) {
      return null;
    }
    _lastBrightness = _getCurrentBrightness();

    if (Platform.isIOS) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
        ),
      );
    } else if (Platform.isAndroid) {
      // The following line is for this error: https://github.com/flutter/flutter/issues/40590
      // WidgetsBinding.instance.renderView.automaticSystemUiAdjustment = false;

      // SystemChrome.setSystemUIOverlayStyle(
      //   SystemUiOverlayStyle.dark.copyWith(
      //     statusBarColor: Colors.transparent, // Color for Android
      //     statusBarBrightness: isDarkMode
      //         ? Brightness.dark
      //         : Brightness.light, // Dark == white status bar -- for IOS.
      //     // systemNavigationBarColor: Colors.transparent, // navigation bar color
      //   ),
      // );
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
        ),
      );
    }
  }
}

/// Returns the [ThemeManger] that
ThemeManager getThemeManager(BuildContext context) =>
    Provider.of<ThemeManager>(context, listen: false);

class ThemeModel {
  final ThemeData selectedTheme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;

  ThemeModel({
    @required this.selectedTheme,
    @required this.darkTheme,
    @required this.themeMode,
  });
}
