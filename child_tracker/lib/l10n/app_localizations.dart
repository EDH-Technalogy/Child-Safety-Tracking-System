import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_ps.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
    Locale('ps')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Child Tracker'**
  String get appTitle;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotPasswordTitle;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get dontHaveAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @children.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get children;

  /// No description provided for @myChildren.
  ///
  /// In en, this message translates to:
  /// **'My Children'**
  String get myChildren;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @safeZones.
  ///
  /// In en, this message translates to:
  /// **'Safe Zones'**
  String get safeZones;

  /// No description provided for @locationHistory.
  ///
  /// In en, this message translates to:
  /// **'Location History'**
  String get locationHistory;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get map;

  /// No description provided for @mapView.
  ///
  /// In en, this message translates to:
  /// **'Map View'**
  String get mapView;

  /// No description provided for @addChild.
  ///
  /// In en, this message translates to:
  /// **'Add Child'**
  String get addChild;

  /// No description provided for @addSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Add Safe Zone'**
  String get addSafeZone;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @locationSettings.
  ///
  /// In en, this message translates to:
  /// **'Location Settings'**
  String get locationSettings;

  /// No description provided for @privacySecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get privacySecurity;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @adminPanel.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPanel;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @administrator.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get administrator;

  /// No description provided for @adminPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Dashboard'**
  String get adminPanelTitle;

  /// No description provided for @userPages.
  ///
  /// In en, this message translates to:
  /// **'User Pages'**
  String get userPages;

  /// No description provided for @adminPages.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPages;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// No description provided for @deviceManagement.
  ///
  /// In en, this message translates to:
  /// **'Device Management'**
  String get deviceManagement;

  /// No description provided for @childrenManagement.
  ///
  /// In en, this message translates to:
  /// **'Children Management'**
  String get childrenManagement;

  /// No description provided for @alertsManagement.
  ///
  /// In en, this message translates to:
  /// **'Alerts Management'**
  String get alertsManagement;

  /// No description provided for @systemLogs.
  ///
  /// In en, this message translates to:
  /// **'System Logs'**
  String get systemLogs;

  /// No description provided for @totalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get totalUsers;

  /// No description provided for @activeUsers.
  ///
  /// In en, this message translates to:
  /// **'Active Users'**
  String get activeUsers;

  /// No description provided for @totalDevices.
  ///
  /// In en, this message translates to:
  /// **'Total Devices'**
  String get totalDevices;

  /// No description provided for @activeDevices.
  ///
  /// In en, this message translates to:
  /// **'Active Devices'**
  String get activeDevices;

  /// No description provided for @totalChildren.
  ///
  /// In en, this message translates to:
  /// **'Total Children'**
  String get totalChildren;

  /// No description provided for @totalAlerts.
  ///
  /// In en, this message translates to:
  /// **'Total Alerts'**
  String get totalAlerts;

  /// No description provided for @management.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get management;

  /// No description provided for @viewAddEditDeleteUsers.
  ///
  /// In en, this message translates to:
  /// **'View, add, edit, delete users'**
  String get viewAddEditDeleteUsers;

  /// No description provided for @viewAddEditDeleteDevices.
  ///
  /// In en, this message translates to:
  /// **'View, add, edit, delete devices'**
  String get viewAddEditDeleteDevices;

  /// No description provided for @viewDeleteChildren.
  ///
  /// In en, this message translates to:
  /// **'View and delete children profiles'**
  String get viewDeleteChildren;

  /// No description provided for @viewDeleteAlerts.
  ///
  /// In en, this message translates to:
  /// **'View and delete alerts'**
  String get viewDeleteAlerts;

  /// No description provided for @viewSystemActivity.
  ///
  /// In en, this message translates to:
  /// **'View system activity logs'**
  String get viewSystemActivity;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get appVersion;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @termsOfServiceBody.
  ///
  /// In en, this message translates to:
  /// **'By using this application, you agree to use it only for lawful child-safety monitoring, protect your account credentials, and respect the privacy of children and family members. Unauthorized tracking, misuse of alerts, or sharing private location data without permission is prohibited.'**
  String get termsOfServiceBody;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get noData;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @pashto.
  ///
  /// In en, this message translates to:
  /// **'Pashto'**
  String get pashto;

  /// No description provided for @dari.
  ///
  /// In en, this message translates to:
  /// **'Dari'**
  String get dari;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @app.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get app;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @childName.
  ///
  /// In en, this message translates to:
  /// **'Child Name'**
  String get childName;

  /// No description provided for @childAge.
  ///
  /// In en, this message translates to:
  /// **'Child Age'**
  String get childAge;

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceId;

  /// No description provided for @battery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get battery;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last Seen'**
  String get lastSeen;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @sos.
  ///
  /// In en, this message translates to:
  /// **'SOS Alert'**
  String get sos;

  /// No description provided for @outOfZone.
  ///
  /// In en, this message translates to:
  /// **'Out of Safe Zone'**
  String get outOfZone;

  /// No description provided for @inZone.
  ///
  /// In en, this message translates to:
  /// **'In Safe Zone'**
  String get inZone;

  /// No description provided for @lowBattery.
  ///
  /// In en, this message translates to:
  /// **'Low Battery'**
  String get lowBattery;

  /// No description provided for @deviceOffline.
  ///
  /// In en, this message translates to:
  /// **'Device Offline'**
  String get deviceOffline;

  /// No description provided for @deleteUser.
  ///
  /// In en, this message translates to:
  /// **'Delete User'**
  String get deleteUser;

  /// No description provided for @areYouSureDeleteUser.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this user?'**
  String get areYouSureDeleteUser;

  /// No description provided for @addNewUser.
  ///
  /// In en, this message translates to:
  /// **'Add New User'**
  String get addNewUser;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @editUser.
  ///
  /// In en, this message translates to:
  /// **'Edit User'**
  String get editUser;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @deleteDevice.
  ///
  /// In en, this message translates to:
  /// **'Delete Device'**
  String get deleteDevice;

  /// No description provided for @areYouSureDeleteDevice.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this device?'**
  String get areYouSureDeleteDevice;

  /// No description provided for @editDevice.
  ///
  /// In en, this message translates to:
  /// **'Edit Device'**
  String get editDevice;

  /// No description provided for @deviceManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Management'**
  String get deviceManagementTitle;

  /// No description provided for @deleteChild.
  ///
  /// In en, this message translates to:
  /// **'Delete Child'**
  String get deleteChild;

  /// No description provided for @areYouSureDeleteChild.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this child?'**
  String get areYouSureDeleteChild;

  /// No description provided for @childrenManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Children Management'**
  String get childrenManagementTitle;

  /// No description provided for @deleteAlert.
  ///
  /// In en, this message translates to:
  /// **'Delete Alert'**
  String get deleteAlert;

  /// No description provided for @areYouSureDeleteAlert.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this alert?'**
  String get areYouSureDeleteAlert;

  /// No description provided for @alertsManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts Management'**
  String get alertsManagementTitle;

  /// No description provided for @systemLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'System Logs'**
  String get systemLogsTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileTitle;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordTitle;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirm;

  /// No description provided for @logoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutTitle;

  /// No description provided for @adminLogin.
  ///
  /// In en, this message translates to:
  /// **'Admin Login'**
  String get adminLogin;

  /// No description provided for @backToApp.
  ///
  /// In en, this message translates to:
  /// **'Back to App'**
  String get backToApp;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get chooseFromGallery;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get removePhoto;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// No description provided for @liveTracking.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking'**
  String get liveTracking;

  /// No description provided for @showChildLocation.
  ///
  /// In en, this message translates to:
  /// **'Show child location in real-time'**
  String get showChildLocation;

  /// No description provided for @showSafeZones.
  ///
  /// In en, this message translates to:
  /// **'Show safe zone boundaries'**
  String get showSafeZones;

  /// No description provided for @showChildMarker.
  ///
  /// In en, this message translates to:
  /// **'Show child marker on map'**
  String get showChildMarker;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @child.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get child;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @safeZone.
  ///
  /// In en, this message translates to:
  /// **'Safe Zone'**
  String get safeZone;

  /// No description provided for @childLocation.
  ///
  /// In en, this message translates to:
  /// **'Child Location'**
  String get childLocation;

  /// No description provided for @noDailyData.
  ///
  /// In en, this message translates to:
  /// **'No daily data'**
  String get noDailyData;

  /// No description provided for @areYouSureDeleteZone.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this safe zone?'**
  String get areYouSureDeleteZone;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @childHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get childHistory;

  /// No description provided for @childActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get childActivity;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back!'**
  String get welcomeBack;

  /// No description provided for @signInToTrack.
  ///
  /// In en, this message translates to:
  /// **'Sign in to track your children'**
  String get signInToTrack;

  /// No description provided for @enterYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get enterYourEmail;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get enterYourPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @enterConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get enterConfirmPassword;

  /// No description provided for @registrationSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Registration successful'**
  String get registrationSuccessful;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter name'**
  String get enterName;

  /// No description provided for @enterPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter phone number'**
  String get enterPhone;

  /// No description provided for @enterDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Please enter device ID'**
  String get enterDeviceId;

  /// No description provided for @childAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Child added successfully'**
  String get childAddedSuccess;

  /// No description provided for @childUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Child updated successfully'**
  String get childUpdatedSuccess;

  /// No description provided for @childDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Child deleted successfully'**
  String get childDeletedSuccess;

  /// No description provided for @zoneAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Safe zone added successfully'**
  String get zoneAddedSuccess;

  /// No description provided for @zoneDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Safe zone deleted successfully'**
  String get zoneDeletedSuccess;

  /// No description provided for @profileUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccess;

  /// No description provided for @profileUpdatedFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile'**
  String get profileUpdatedFailed;

  /// No description provided for @noChildren.
  ///
  /// In en, this message translates to:
  /// **'No children added yet'**
  String get noChildren;

  /// No description provided for @noAlerts.
  ///
  /// In en, this message translates to:
  /// **'No alerts'**
  String get noAlerts;

  /// No description provided for @noSafeZones.
  ///
  /// In en, this message translates to:
  /// **'No safe zones'**
  String get noSafeZones;

  /// No description provided for @addYourFirstChild.
  ///
  /// In en, this message translates to:
  /// **'Add your first child to start tracking'**
  String get addYourFirstChild;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get permissionDenied;

  /// No description provided for @locationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required'**
  String get locationPermissionRequired;

  /// No description provided for @cameraPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required'**
  String get cameraPermissionRequired;

  /// No description provided for @storagePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Storage permission is required'**
  String get storagePermissionRequired;

  /// No description provided for @userUpdated.
  ///
  /// In en, this message translates to:
  /// **'User updated successfully'**
  String get userUpdated;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @userBlocked.
  ///
  /// In en, this message translates to:
  /// **'User blocked successfully'**
  String get userBlocked;

  /// No description provided for @userUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User unblocked successfully'**
  String get userUnblocked;

  /// No description provided for @userDeleted.
  ///
  /// In en, this message translates to:
  /// **'User deleted successfully'**
  String get userDeleted;

  /// No description provided for @userCreated.
  ///
  /// In en, this message translates to:
  /// **'User created successfully'**
  String get userCreated;

  /// No description provided for @adminPanelSection.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPanelSection;

  /// No description provided for @userPagesSection.
  ///
  /// In en, this message translates to:
  /// **'User Pages'**
  String get userPagesSection;

  /// No description provided for @adminDrawerAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get adminDrawerAdmin;

  /// No description provided for @manageUsersDevicesSystem.
  ///
  /// In en, this message translates to:
  /// **'Manage users, devices, and system'**
  String get manageUsersDevicesSystem;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account Section'**
  String get accountSection;

  /// No description provided for @appSection.
  ///
  /// In en, this message translates to:
  /// **'App Section'**
  String get appSection;

  /// No description provided for @systemSection.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemSection;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About Section'**
  String get aboutSection;

  /// No description provided for @systemConfiguration.
  ///
  /// In en, this message translates to:
  /// **'System Configuration'**
  String get systemConfiguration;

  /// No description provided for @configureDefaultSettings.
  ///
  /// In en, this message translates to:
  /// **'Configure default settings'**
  String get configureDefaultSettings;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// No description provided for @configureAlertsAndNotifications.
  ///
  /// In en, this message translates to:
  /// **'Configure alerts and notifications'**
  String get configureAlertsAndNotifications;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @aboutThisAppTitle.
  ///
  /// In en, this message translates to:
  /// **'About This App'**
  String get aboutThisAppTitle;

  /// No description provided for @aboutAppName.
  ///
  /// In en, this message translates to:
  /// **'Child Tracking & Safety App'**
  String get aboutAppName;

  /// No description provided for @aboutPurposeBody.
  ///
  /// In en, this message translates to:
  /// **'This application is designed to help parents and guardians monitor the safety of their children through GPS tracking technology. It provides live location tracking, safe zone monitoring, instant alerts when a child leaves a defined area, and emergency SOS notifications. The system is built to improve child safety, provide peace of mind to parents, and support quick response during emergencies. User data and location information are protected and accessible only to authorized users.'**
  String get aboutPurposeBody;

  /// No description provided for @aboutFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Key Features'**
  String get aboutFeaturesTitle;

  /// No description provided for @aboutFeaturesList.
  ///
  /// In en, this message translates to:
  /// **'Live Location Tracking\nSafe Zone / Geofence\nEnter / Exit Alerts\nSOS Emergency Alert\nLocation History\nParent Notifications\nChild Profile Management\nAdmin Monitoring Panel'**
  String get aboutFeaturesList;

  /// No description provided for @aboutBenefitsTitle.
  ///
  /// In en, this message translates to:
  /// **'App Benefits'**
  String get aboutBenefitsTitle;

  /// No description provided for @aboutBenefitsList.
  ///
  /// In en, this message translates to:
  /// **'Improves child safety\nGives parents instant alerts\nHelps quickly identify child location\nSupports fast response in emergencies'**
  String get aboutBenefitsList;

  /// No description provided for @aboutWhoCanUseTitle.
  ///
  /// In en, this message translates to:
  /// **'Who Can Use It'**
  String get aboutWhoCanUseTitle;

  /// No description provided for @aboutWhoCanUseList.
  ///
  /// In en, this message translates to:
  /// **'Admin\nParents / Guardians\nChildren Users'**
  String get aboutWhoCanUseList;

  /// No description provided for @aboutPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy and Security'**
  String get aboutPrivacyTitle;

  /// No description provided for @aboutPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'User and location data are stored securely and are accessible only to authorized users.'**
  String get aboutPrivacyBody;

  /// No description provided for @aboutDeveloperInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Developer / Company Info'**
  String get aboutDeveloperInfoTitle;

  /// No description provided for @aboutDeveloperLabel.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get aboutDeveloperLabel;

  /// No description provided for @aboutCompanyLabel.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get aboutCompanyLabel;

  /// No description provided for @aboutEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get aboutEmailLabel;

  /// No description provided for @aboutContactNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact Number'**
  String get aboutContactNumberLabel;

  /// No description provided for @aboutWebsiteLabel.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsiteLabel;

  /// No description provided for @aboutSupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support / Help'**
  String get aboutSupportTitle;

  /// No description provided for @aboutSupportBody.
  ///
  /// In en, this message translates to:
  /// **'If you need help using the app or face any issue, please contact the support team using the email or contact information below.'**
  String get aboutSupportBody;

  /// No description provided for @aboutSupportContactLine.
  ///
  /// In en, this message translates to:
  /// **'If you have any issue in the application, call us at 0706439264 or send your complaint on WhatsApp to 0780258081.'**
  String get aboutSupportContactLine;

  /// No description provided for @aboutCopyrightTitle.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get aboutCopyrightTitle;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark All Read'**
  String get markAllRead;

  /// No description provided for @monitoring.
  ///
  /// In en, this message translates to:
  /// **'Monitoring'**
  String get monitoring;

  /// No description provided for @pleaseAddChildFirst.
  ///
  /// In en, this message translates to:
  /// **'Please add a child first'**
  String get pleaseAddChildFirst;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @searchByNameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email...'**
  String get searchByNameOrEmail;

  /// No description provided for @searchByName.
  ///
  /// In en, this message translates to:
  /// **'Search by name...'**
  String get searchByName;

  /// No description provided for @searchByIdOrImei.
  ///
  /// In en, this message translates to:
  /// **'Search by ID or IMEI...'**
  String get searchByIdOrImei;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @noChildrenFound.
  ///
  /// In en, this message translates to:
  /// **'No children found'**
  String get noChildrenFound;

  /// No description provided for @noAlertsFound.
  ///
  /// In en, this message translates to:
  /// **'No alerts found'**
  String get noAlertsFound;

  /// No description provided for @noLogsFound.
  ///
  /// In en, this message translates to:
  /// **'No logs found'**
  String get noLogsFound;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @addProfile.
  ///
  /// In en, this message translates to:
  /// **'Add Profile'**
  String get addProfile;

  /// No description provided for @saveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get saveProfile;

  /// No description provided for @failedToUpdateProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile photo'**
  String get failedToUpdateProfilePhoto;

  /// No description provided for @uploadFailedPhotoOptional.
  ///
  /// In en, this message translates to:
  /// **'Upload failed. Photo is optional.'**
  String get uploadFailedPhotoOptional;

  /// No description provided for @imageUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image upload failed'**
  String get imageUploadFailed;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @adminId.
  ///
  /// In en, this message translates to:
  /// **'Admin ID'**
  String get adminId;

  /// No description provided for @childId.
  ///
  /// In en, this message translates to:
  /// **'Child ID'**
  String get childId;

  /// No description provided for @userId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get userId;

  /// No description provided for @age.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get age;

  /// No description provided for @imei.
  ///
  /// In en, this message translates to:
  /// **'IMEI'**
  String get imei;

  /// No description provided for @simNumber.
  ///
  /// In en, this message translates to:
  /// **'SIM Number'**
  String get simNumber;

  /// No description provided for @simNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'SIM Number (Optional)'**
  String get simNumberOptional;

  /// No description provided for @firmwareVersion.
  ///
  /// In en, this message translates to:
  /// **'Firmware Version'**
  String get firmwareVersion;

  /// No description provided for @registerDevice.
  ///
  /// In en, this message translates to:
  /// **'Register Device'**
  String get registerDevice;

  /// No description provided for @deviceWillBeRegistered.
  ///
  /// In en, this message translates to:
  /// **'The device will be registered and ready to track location.'**
  String get deviceWillBeRegistered;

  /// No description provided for @tapToAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to add photo'**
  String get tapToAddPhoto;

  /// No description provided for @adminAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Admin access required. Please login as admin.'**
  String get adminAccessRequired;

  /// No description provided for @logoutAndLoginAsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Logout & Login as Admin'**
  String get logoutAndLoginAsAdmin;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @deactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// No description provided for @addDevice.
  ///
  /// In en, this message translates to:
  /// **'Add Device'**
  String get addDevice;

  /// No description provided for @deviceActivatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Device activated successfully'**
  String get deviceActivatedSuccessfully;

  /// No description provided for @deviceDeactivatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Device deactivated successfully'**
  String get deviceDeactivatedSuccessfully;

  /// No description provided for @deviceAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Device added successfully'**
  String get deviceAddedSuccessfully;

  /// No description provided for @deviceUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Device updated successfully'**
  String get deviceUpdatedSuccessfully;

  /// No description provided for @deleteDevicePermanentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete this device?'**
  String get deleteDevicePermanentConfirm;

  /// No description provided for @childIdAndImeiRequired.
  ///
  /// In en, this message translates to:
  /// **'Child ID and IMEI are required'**
  String get childIdAndImeiRequired;

  /// No description provided for @noDevicesRegistered.
  ///
  /// In en, this message translates to:
  /// **'No devices registered'**
  String get noDevicesRegistered;

  /// No description provided for @noDevicesMatch.
  ///
  /// In en, this message translates to:
  /// **'No devices match'**
  String get noDevicesMatch;

  /// No description provided for @unknownImei.
  ///
  /// In en, this message translates to:
  /// **'Unknown IMEI'**
  String get unknownImei;

  /// No description provided for @childBlockedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Child blocked successfully'**
  String get childBlockedSuccessfully;

  /// No description provided for @childUnblockedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Child unblocked successfully'**
  String get childUnblockedSuccessfully;

  /// No description provided for @deleteChildProfileConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this child profile? This will remove the child and linked device metadata.'**
  String get deleteChildProfileConfirm;

  /// No description provided for @alertDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Alert deleted successfully'**
  String get alertDeletedSuccessfully;

  /// No description provided for @noMessage.
  ///
  /// In en, this message translates to:
  /// **'No message'**
  String get noMessage;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @childOutOfSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Child out of Safe Zone'**
  String get childOutOfSafeZone;

  /// No description provided for @childBackInSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Child back in Safe Zone'**
  String get childBackInSafeZone;

  /// No description provided for @deviceOnline.
  ///
  /// In en, this message translates to:
  /// **'Device Online'**
  String get deviceOnline;

  /// No description provided for @deleteLog.
  ///
  /// In en, this message translates to:
  /// **'Delete Log'**
  String get deleteLog;

  /// No description provided for @deleteLogEntryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this log entry?'**
  String get deleteLogEntryConfirm;

  /// No description provided for @deleteAllLogs.
  ///
  /// In en, this message translates to:
  /// **'Delete All Logs'**
  String get deleteAllLogs;

  /// No description provided for @deleteAllLogsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all system logs?'**
  String get deleteAllLogsConfirm;

  /// No description provided for @deleteSelectedLogs.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected Logs'**
  String get deleteSelectedLogs;

  /// No description provided for @deleteSelectedLogsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the selected log items?'**
  String get deleteSelectedLogsConfirm;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected'**
  String get deleteSelected;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get deleteAll;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get clearSelection;

  /// No description provided for @logDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Log deleted successfully'**
  String get logDeletedSuccessfully;

  /// No description provided for @allSystemLogsDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'All system logs deleted successfully'**
  String get allSystemLogsDeletedSuccessfully;

  /// No description provided for @selectedLogsDeleted.
  ///
  /// In en, this message translates to:
  /// **'selected log(s) deleted'**
  String get selectedLogsDeleted;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @eventType.
  ///
  /// In en, this message translates to:
  /// **'Event Type'**
  String get eventType;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @dateTime.
  ///
  /// In en, this message translates to:
  /// **'Date/Time'**
  String get dateTime;

  /// No description provided for @actor.
  ///
  /// In en, this message translates to:
  /// **'Actor'**
  String get actor;

  /// No description provided for @target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get target;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @changedFields.
  ///
  /// In en, this message translates to:
  /// **'Changed Fields'**
  String get changedFields;

  /// No description provided for @additionalMetadata.
  ///
  /// In en, this message translates to:
  /// **'Additional Metadata'**
  String get additionalMetadata;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @noDescriptionAvailable.
  ///
  /// In en, this message translates to:
  /// **'No description available'**
  String get noDescriptionAvailable;

  /// No description provided for @noAdditionalDetailsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No additional details available'**
  String get noAdditionalDetailsAvailable;

  /// No description provided for @requestTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please try again.'**
  String get requestTimedOut;

  /// No description provided for @backendUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to reach backend server. Check API URL, backend server, and CORS settings.'**
  String get backendUnavailable;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials'**
  String get invalidCredentials;

  /// No description provided for @adminNotFound.
  ///
  /// In en, this message translates to:
  /// **'Admin not found'**
  String get adminNotFound;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @emailPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Email and password are required'**
  String get emailPasswordRequired;

  /// No description provided for @emailNotFound.
  ///
  /// In en, this message translates to:
  /// **'Email not found'**
  String get emailNotFound;

  /// No description provided for @otpExpired.
  ///
  /// In en, this message translates to:
  /// **'OTP expired'**
  String get otpExpired;

  /// No description provided for @invalidOtp.
  ///
  /// In en, this message translates to:
  /// **'Invalid OTP'**
  String get invalidOtp;

  /// No description provided for @accountBlocked.
  ///
  /// In en, this message translates to:
  /// **'Account is blocked'**
  String get accountBlocked;

  /// No description provided for @invalidRequest.
  ///
  /// In en, this message translates to:
  /// **'Invalid request'**
  String get invalidRequest;

  /// No description provided for @alertNotFound.
  ///
  /// In en, this message translates to:
  /// **'Alert not found'**
  String get alertNotFound;

  /// No description provided for @failedToLoadAlerts.
  ///
  /// In en, this message translates to:
  /// **'Failed to load alerts'**
  String get failedToLoadAlerts;

  /// No description provided for @failedToLoadSystemLogs.
  ///
  /// In en, this message translates to:
  /// **'Failed to load system logs'**
  String get failedToLoadSystemLogs;

  /// No description provided for @failedToLoadDevices.
  ///
  /// In en, this message translates to:
  /// **'Failed to load devices'**
  String get failedToLoadDevices;

  /// No description provided for @failedToLoadChildren.
  ///
  /// In en, this message translates to:
  /// **'Failed to load children'**
  String get failedToLoadChildren;

  /// No description provided for @failedToLoadUsers.
  ///
  /// In en, this message translates to:
  /// **'Failed to load users'**
  String get failedToLoadUsers;

  /// No description provided for @failedToLoadProfile.
  ///
  /// In en, this message translates to:
  /// **'Failed to load profile'**
  String get failedToLoadProfile;

  /// No description provided for @failedToUpdateProfile.
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile'**
  String get failedToUpdateProfile;

  /// No description provided for @failedToDeleteAlert.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete alert'**
  String get failedToDeleteAlert;

  /// No description provided for @failedToDeleteLog.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete log'**
  String get failedToDeleteLog;

  /// No description provided for @failedToCreateSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Failed to create safe zone'**
  String get failedToCreateSafeZone;

  /// No description provided for @failedToUpdateSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Failed to update safe zone'**
  String get failedToUpdateSafeZone;

  /// No description provided for @otpSentToEmail.
  ///
  /// In en, this message translates to:
  /// **'OTP sent to your email'**
  String get otpSentToEmail;

  /// No description provided for @failedToSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Failed to send OTP'**
  String get failedToSendOtp;

  /// No description provided for @passwordResetSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Password reset successful!'**
  String get passwordResetSuccessful;

  /// No description provided for @failedToResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Failed to reset password'**
  String get failedToResetPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @enterOtpAndNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter the OTP and your new password'**
  String get enterOtpAndNewPassword;

  /// No description provided for @enterEmailToReceiveOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter your email to receive OTP'**
  String get enterEmailToReceiveOtp;

  /// No description provided for @otp.
  ///
  /// In en, this message translates to:
  /// **'OTP'**
  String get otp;

  /// No description provided for @enterOtp.
  ///
  /// In en, this message translates to:
  /// **'Please enter the OTP'**
  String get enterOtp;

  /// No description provided for @otpMustBeSixDigits.
  ///
  /// In en, this message translates to:
  /// **'OTP must be 6 digits'**
  String get otpMustBeSixDigits;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @enterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter a new password'**
  String get enterNewPassword;

  /// No description provided for @passwordMinSix.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordMinSix;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @callSupport.
  ///
  /// In en, this message translates to:
  /// **'Call Support'**
  String get callSupport;

  /// No description provided for @searchFaq.
  ///
  /// In en, this message translates to:
  /// **'Search FAQ...'**
  String get searchFaq;

  /// No description provided for @frequentlyAskedQuestions.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get frequentlyAskedQuestions;

  /// No description provided for @reportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get reportIssue;

  /// No description provided for @describeYourIssue.
  ///
  /// In en, this message translates to:
  /// **'Describe your issue'**
  String get describeYourIssue;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReport;

  /// No description provided for @submitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get submitting;

  /// No description provided for @pleaseFillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill all fields'**
  String get pleaseFillAllFields;

  /// No description provided for @reportSubmittedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Report submitted successfully!'**
  String get reportSubmittedSuccessfully;

  /// No description provided for @faqTrackChildQuestion.
  ///
  /// In en, this message translates to:
  /// **'How to track my child?'**
  String get faqTrackChildQuestion;

  /// No description provided for @faqTrackChildAnswer.
  ///
  /// In en, this message translates to:
  /// **'Open the map screen and select your child from the list.'**
  String get faqTrackChildAnswer;

  /// No description provided for @faqLowBatteryQuestion.
  ///
  /// In en, this message translates to:
  /// **'What to do if device battery is low?'**
  String get faqLowBatteryQuestion;

  /// No description provided for @faqLowBatteryAnswer.
  ///
  /// In en, this message translates to:
  /// **'Charge the device or enable low power mode in settings.'**
  String get faqLowBatteryAnswer;

  /// No description provided for @faqGeofenceQuestion.
  ///
  /// In en, this message translates to:
  /// **'How to set up geofence?'**
  String get faqGeofenceQuestion;

  /// No description provided for @faqGeofenceAnswer.
  ///
  /// In en, this message translates to:
  /// **'Go to Safe Zones screen and tap + to add a new zone.'**
  String get faqGeofenceAnswer;

  /// No description provided for @faqLocationUpdateQuestion.
  ///
  /// In en, this message translates to:
  /// **'Why is location not updating?'**
  String get faqLocationUpdateQuestion;

  /// No description provided for @faqLocationUpdateAnswer.
  ///
  /// In en, this message translates to:
  /// **'Check device battery, internet connection, and GPS permissions.'**
  String get faqLocationUpdateAnswer;

  /// No description provided for @faqShareLocationQuestion.
  ///
  /// In en, this message translates to:
  /// **'Can I share location with family?'**
  String get faqShareLocationQuestion;

  /// No description provided for @faqShareLocationAnswer.
  ///
  /// In en, this message translates to:
  /// **'Yes, go to Settings > Privacy & Security > Share Location.'**
  String get faqShareLocationAnswer;

  /// No description provided for @privacyPolicyBody.
  ///
  /// In en, this message translates to:
  /// **'Your data is protected with end-to-end encryption. Location data is only stored for 30 days and never shared with third parties.'**
  String get privacyPolicyBody;

  /// No description provided for @notificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications enabled'**
  String get notificationsEnabled;

  /// No description provided for @notificationsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications disabled'**
  String get notificationsDisabled;

  /// No description provided for @receiveAlertsForLowBatteryAndGeofenceExits.
  ///
  /// In en, this message translates to:
  /// **'Receive alerts for low battery and geofence exits'**
  String get receiveAlertsForLowBatteryAndGeofenceExits;

  /// No description provided for @locationSharing.
  ///
  /// In en, this message translates to:
  /// **'Location Sharing'**
  String get locationSharing;

  /// No description provided for @shareLiveLocationWithEmergencyContacts.
  ///
  /// In en, this message translates to:
  /// **'Share live location with emergency contacts'**
  String get shareLiveLocationWithEmergencyContacts;

  /// No description provided for @locationTrackingEnabled.
  ///
  /// In en, this message translates to:
  /// **'Location tracking enabled'**
  String get locationTrackingEnabled;

  /// No description provided for @locationTrackingDisabled.
  ///
  /// In en, this message translates to:
  /// **'Location tracking disabled'**
  String get locationTrackingDisabled;

  /// No description provided for @autoUpdates.
  ///
  /// In en, this message translates to:
  /// **'Auto Updates'**
  String get autoUpdates;

  /// No description provided for @autoUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically download security updates'**
  String get autoUpdatesSubtitle;

  /// No description provided for @autoUpdatesEnabled.
  ///
  /// In en, this message translates to:
  /// **'Auto updates enabled'**
  String get autoUpdatesEnabled;

  /// No description provided for @autoUpdatesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Auto updates disabled'**
  String get autoUpdatesDisabled;

  /// No description provided for @updateYourAccountPassword.
  ///
  /// In en, this message translates to:
  /// **'Update your account password'**
  String get updateYourAccountPassword;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all your data'**
  String get deleteAccountSubtitle;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. All your data will be permanently deleted.'**
  String get deleteAccountConfirm;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get accountDeleted;

  /// No description provided for @dataUsage.
  ///
  /// In en, this message translates to:
  /// **'Data Usage'**
  String get dataUsage;

  /// No description provided for @locationHistoryRetention.
  ///
  /// In en, this message translates to:
  /// **'Location history: 30 days retention'**
  String get locationHistoryRetention;

  /// No description provided for @activityLogsRetention.
  ///
  /// In en, this message translates to:
  /// **'Activity logs: 90 days retention'**
  String get activityLogsRetention;

  /// No description provided for @deviceDataRealTime.
  ///
  /// In en, this message translates to:
  /// **'Device data: Real-time'**
  String get deviceDataRealTime;

  /// No description provided for @exportMyData.
  ///
  /// In en, this message translates to:
  /// **'Export My Data'**
  String get exportMyData;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// No description provided for @exportDataDescription.
  ///
  /// In en, this message translates to:
  /// **'Export all your location history and activity logs.'**
  String get exportDataDescription;

  /// No description provided for @exportStartedCheckEmail.
  ///
  /// In en, this message translates to:
  /// **'Export started. Check email for download link.'**
  String get exportStartedCheckEmail;

  /// No description provided for @passwordChangedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChangedSuccessfully;

  /// No description provided for @adminAccountUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Admin account updated successfully'**
  String get adminAccountUpdatedSuccessfully;

  /// No description provided for @failedToUpdateAdminAccount.
  ///
  /// In en, this message translates to:
  /// **'Failed to update admin account'**
  String get failedToUpdateAdminAccount;

  /// No description provided for @failedToRemoveProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove profile photo'**
  String get failedToRemoveProfilePhoto;

  /// No description provided for @selectParentUser.
  ///
  /// In en, this message translates to:
  /// **'Select Parent User'**
  String get selectParentUser;

  /// No description provided for @unableToLoadParentUsers.
  ///
  /// In en, this message translates to:
  /// **'Unable to load parent users right now'**
  String get unableToLoadParentUsers;

  /// No description provided for @noParentUsersAvailable.
  ///
  /// In en, this message translates to:
  /// **'No parent users are available to select'**
  String get noParentUsersAvailable;

  /// No description provided for @userIdRequiredForAdminChildCreation.
  ///
  /// In en, this message translates to:
  /// **'User ID is required for admin child creation'**
  String get userIdRequiredForAdminChildCreation;

  /// No description provided for @waitForParentUsersToLoad.
  ///
  /// In en, this message translates to:
  /// **'Please wait for parent users to finish loading'**
  String get waitForParentUsersToLoad;

  /// No description provided for @noMatchingParentUserFound.
  ///
  /// In en, this message translates to:
  /// **'No matching parent user found. Use an existing phone, email, or pick a user.'**
  String get noMatchingParentUserFound;

  /// No description provided for @childIdRequiredForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Child ID is required for updates'**
  String get childIdRequiredForUpdates;

  /// No description provided for @parentUser.
  ///
  /// In en, this message translates to:
  /// **'Parent User'**
  String get parentUser;

  /// No description provided for @safeZoneCenter.
  ///
  /// In en, this message translates to:
  /// **'Safe Zone Center'**
  String get safeZoneCenter;

  /// No description provided for @dragToAdjustLocation.
  ///
  /// In en, this message translates to:
  /// **'Drag to adjust location'**
  String get dragToAdjustLocation;

  /// No description provided for @pleaseEnterSafeZoneName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name for the safe zone'**
  String get pleaseEnterSafeZoneName;

  /// No description provided for @pleaseSelectLocation.
  ///
  /// In en, this message translates to:
  /// **'Please select a location'**
  String get pleaseSelectLocation;

  /// No description provided for @safeZoneRadiusRange.
  ///
  /// In en, this message translates to:
  /// **'Radius must be between 50 meters and 50 kilometers'**
  String get safeZoneRadiusRange;

  /// No description provided for @safeZoneCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Safe zone created successfully'**
  String get safeZoneCreatedSuccessfully;

  /// No description provided for @safeZoneUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Safe zone updated successfully'**
  String get safeZoneUpdatedSuccessfully;

  /// No description provided for @zoneName.
  ///
  /// In en, this message translates to:
  /// **'Zone Name'**
  String get zoneName;

  /// No description provided for @zoneNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Home, School, Park'**
  String get zoneNameHint;

  /// No description provided for @useMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get useMyLocation;

  /// No description provided for @tapOnMapToSelectLocation.
  ///
  /// In en, this message translates to:
  /// **'Tap on map to select location'**
  String get tapOnMapToSelectLocation;

  /// No description provided for @capture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get capture;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @deviceDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Device deleted successfully'**
  String get deviceDeletedSuccessfully;

  /// No description provided for @editSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Edit Safe Zone'**
  String get editSafeZone;

  /// No description provided for @updateSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Update Safe Zone'**
  String get updateSafeZone;

  /// No description provided for @createSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Create Safe Zone'**
  String get createSafeZone;

  /// No description provided for @radius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get radius;

  /// No description provided for @meters.
  ///
  /// In en, this message translates to:
  /// **'meters'**
  String get meters;

  /// No description provided for @metersShort.
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get metersShort;

  /// No description provided for @kilometersShort.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get kilometersShort;

  /// No description provided for @selectedLocation.
  ///
  /// In en, this message translates to:
  /// **'Selected Location'**
  String get selectedLocation;

  /// No description provided for @noLocationSelected.
  ///
  /// In en, this message translates to:
  /// **'No location selected'**
  String get noLocationSelected;

  /// No description provided for @safeZoneAlertsInfo.
  ///
  /// In en, this message translates to:
  /// **'You will receive alerts when your child enters or exits this safe zone.'**
  String get safeZoneAlertsInfo;

  /// No description provided for @tapToChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to change photo'**
  String get tapToChangePhoto;

  /// No description provided for @useParentPhoneEmailOrTapSearch.
  ///
  /// In en, this message translates to:
  /// **'Use parent phone, email, or tap search'**
  String get useParentPhoneEmailOrTapSearch;

  /// No description provided for @pleaseEnterParentUserId.
  ///
  /// In en, this message translates to:
  /// **'Please enter parent user ID'**
  String get pleaseEnterParentUserId;

  /// No description provided for @pleaseEnterChildName.
  ///
  /// In en, this message translates to:
  /// **'Please enter child\'s name'**
  String get pleaseEnterChildName;

  /// No description provided for @pleaseEnterChildAge.
  ///
  /// In en, this message translates to:
  /// **'Please enter child\'s age'**
  String get pleaseEnterChildAge;

  /// No description provided for @pleaseEnterValidAge.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid age (0-18)'**
  String get pleaseEnterValidAge;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @mapSettings.
  ///
  /// In en, this message translates to:
  /// **'Map Settings'**
  String get mapSettings;

  /// No description provided for @defaultZoomLevel.
  ///
  /// In en, this message translates to:
  /// **'Default Zoom Level'**
  String get defaultZoomLevel;

  /// No description provided for @myLocation.
  ///
  /// In en, this message translates to:
  /// **'My Location'**
  String get myLocation;

  /// No description provided for @currentPosition.
  ///
  /// In en, this message translates to:
  /// **'Current position'**
  String get currentPosition;

  /// No description provided for @systemManagementPortal.
  ///
  /// In en, this message translates to:
  /// **'System Management Portal'**
  String get systemManagementPortal;

  /// No description provided for @adminEmail.
  ///
  /// In en, this message translates to:
  /// **'Admin Email'**
  String get adminEmail;

  /// No description provided for @validEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Valid email required'**
  String get validEmailRequired;

  /// No description provided for @adminLoginButton.
  ///
  /// In en, this message translates to:
  /// **'ADMIN LOGIN'**
  String get adminLoginButton;

  /// No description provided for @serverNotReachableStartBackend.
  ///
  /// In en, this message translates to:
  /// **'Server not reachable. Start backend server.'**
  String get serverNotReachableStartBackend;

  /// No description provided for @editChild.
  ///
  /// In en, this message translates to:
  /// **'Edit Child'**
  String get editChild;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @activityLogs.
  ///
  /// In en, this message translates to:
  /// **'Activity Logs'**
  String get activityLogs;

  /// No description provided for @todaysSummary.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Summary'**
  String get todaysSummary;

  /// No description provided for @totalDistance.
  ///
  /// In en, this message translates to:
  /// **'Total Distance'**
  String get totalDistance;

  /// No description provided for @locationPoints.
  ///
  /// In en, this message translates to:
  /// **'Location Points'**
  String get locationPoints;

  /// No description provided for @sosAlerts.
  ///
  /// In en, this message translates to:
  /// **'SOS Alerts'**
  String get sosAlerts;

  /// No description provided for @zoneExits.
  ///
  /// In en, this message translates to:
  /// **'Zone Exits'**
  String get zoneExits;

  /// No description provided for @firstLocation.
  ///
  /// In en, this message translates to:
  /// **'First Location'**
  String get firstLocation;

  /// No description provided for @lastLocation.
  ///
  /// In en, this message translates to:
  /// **'Last Location'**
  String get lastLocation;

  /// No description provided for @noDataAvailableForToday.
  ///
  /// In en, this message translates to:
  /// **'No data available for today'**
  String get noDataAvailableForToday;

  /// No description provided for @weeklySummary.
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary'**
  String get weeklySummary;

  /// No description provided for @daysTracked.
  ///
  /// In en, this message translates to:
  /// **'Days Tracked'**
  String get daysTracked;

  /// No description provided for @totalSosAlerts.
  ///
  /// In en, this message translates to:
  /// **'Total SOS Alerts'**
  String get totalSosAlerts;

  /// No description provided for @totalZoneExits.
  ///
  /// In en, this message translates to:
  /// **'Total Zone Exits'**
  String get totalZoneExits;

  /// No description provided for @dailyBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Daily Breakdown'**
  String get dailyBreakdown;

  /// No description provided for @noWeeklyDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No weekly data available'**
  String get noWeeklyDataAvailable;

  /// No description provided for @noActivityLogsYet.
  ///
  /// In en, this message translates to:
  /// **'No activity logs yet'**
  String get noActivityLogsYet;

  /// No description provided for @distance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get distance;

  /// No description provided for @latitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitude;

  /// No description provided for @longitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitude;

  /// No description provided for @locations.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get locations;

  /// No description provided for @routeMap.
  ///
  /// In en, this message translates to:
  /// **'Route Map'**
  String get routeMap;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get points;

  /// No description provided for @noLocationDataForDate.
  ///
  /// In en, this message translates to:
  /// **'No location data for this date'**
  String get noLocationDataForDate;

  /// No description provided for @connectWithYourChildrenSafely.
  ///
  /// In en, this message translates to:
  /// **'Connect with your children safely'**
  String get connectWithYourChildrenSafely;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password too short'**
  String get passwordTooShort;

  /// No description provided for @registrationSuccessfulPleaseLogin.
  ///
  /// In en, this message translates to:
  /// **'Registration successful! Please login.'**
  String get registrationSuccessfulPleaseLogin;

  /// No description provided for @registrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get registrationFailed;

  /// No description provided for @noSafeZonesAvailableForScope.
  ///
  /// In en, this message translates to:
  /// **'No safe zones available for your search scope'**
  String get noSafeZonesAvailableForScope;

  /// No description provided for @searchSafeZonesPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by child name, child ID, or zone name...'**
  String get searchSafeZonesPlaceholder;

  /// No description provided for @noSafeZonesMatch.
  ///
  /// In en, this message translates to:
  /// **'No safe zones match'**
  String get noSafeZonesMatch;

  /// No description provided for @uploadFailedCurrentPhotoKept.
  ///
  /// In en, this message translates to:
  /// **'Upload failed. Current photo kept.'**
  String get uploadFailedCurrentPhotoKept;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get updateFailed;

  /// No description provided for @yearsOld.
  ///
  /// In en, this message translates to:
  /// **'years old'**
  String get yearsOld;

  /// No description provided for @adminOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live operational overview for the admin system'**
  String get adminOverviewSubtitle;

  /// No description provided for @noDataAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'No data available yet'**
  String get noDataAvailableYet;

  /// No description provided for @dashboardPartialData.
  ///
  /// In en, this message translates to:
  /// **'Some dashboard sections could not be loaded. Available data is still shown.'**
  String get dashboardPartialData;

  /// No description provided for @systemStatus.
  ///
  /// In en, this message translates to:
  /// **'System Status'**
  String get systemStatus;

  /// No description provided for @chartsAndInsights.
  ///
  /// In en, this message translates to:
  /// **'Charts & Insights'**
  String get chartsAndInsights;

  /// No description provided for @monitorUsersDevicesAlertsLocations.
  ///
  /// In en, this message translates to:
  /// **'Monitor users, devices, alerts, and location activity'**
  String get monitorUsersDevicesAlertsLocations;

  /// No description provided for @welcomeBackAdmin.
  ///
  /// In en, this message translates to:
  /// **'Welcome back, {name}'**
  String welcomeBackAdmin(Object name);

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdated;

  /// No description provided for @refreshData.
  ///
  /// In en, this message translates to:
  /// **'Refresh data'**
  String get refreshData;

  /// No description provided for @todayAlerts.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Alerts'**
  String get todayAlerts;

  /// No description provided for @safeZonesCount.
  ///
  /// In en, this message translates to:
  /// **'Safe Zones'**
  String get safeZonesCount;

  /// No description provided for @liveDeviceStatus.
  ///
  /// In en, this message translates to:
  /// **'Live device status'**
  String get liveDeviceStatus;

  /// No description provided for @latestAlertVolume.
  ///
  /// In en, this message translates to:
  /// **'Latest alert volume'**
  String get latestAlertVolume;

  /// No description provided for @totalParentsNormalUsers.
  ///
  /// In en, this message translates to:
  /// **'Parent / Normal Users'**
  String get totalParentsNormalUsers;

  /// No description provided for @offlineDevices.
  ///
  /// In en, this message translates to:
  /// **'Offline Devices'**
  String get offlineDevices;

  /// No description provided for @vsYesterday.
  ///
  /// In en, this message translates to:
  /// **'vs yesterday'**
  String get vsYesterday;

  /// No description provided for @locationUpdates.
  ///
  /// In en, this message translates to:
  /// **'Location Updates'**
  String get locationUpdates;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @latestAuditEvents.
  ///
  /// In en, this message translates to:
  /// **'Latest audit and activity events'**
  String get latestAuditEvents;

  /// No description provided for @openCoreAdminAreas.
  ///
  /// In en, this message translates to:
  /// **'Open core admin areas'**
  String get openCoreAdminAreas;

  /// No description provided for @usersActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review accounts, roles, and user access'**
  String get usersActionSubtitle;

  /// No description provided for @childrenActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open child profiles and assignments'**
  String get childrenActionSubtitle;

  /// No description provided for @devicesActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor device health and assignments'**
  String get devicesActionSubtitle;

  /// No description provided for @viewMapActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open live map monitoring'**
  String get viewMapActionSubtitle;

  /// No description provided for @viewAlertsActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review active and historical alerts'**
  String get viewAlertsActionSubtitle;

  /// No description provided for @viewReportsHistory.
  ///
  /// In en, this message translates to:
  /// **'Reports & History'**
  String get viewReportsHistory;

  /// No description provided for @viewReportsActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open logs and historical reports'**
  String get viewReportsActionSubtitle;

  /// No description provided for @safeZonesActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review configured safe zones'**
  String get safeZonesActionSubtitle;

  /// No description provided for @usersByRole.
  ///
  /// In en, this message translates to:
  /// **'Users by Role'**
  String get usersByRole;

  /// No description provided for @userRoleDistribution.
  ///
  /// In en, this message translates to:
  /// **'Distribution of parent and admin accounts'**
  String get userRoleDistribution;

  /// No description provided for @deviceStatusChart.
  ///
  /// In en, this message translates to:
  /// **'Device Status'**
  String get deviceStatusChart;

  /// No description provided for @liveFleetHealth.
  ///
  /// In en, this message translates to:
  /// **'Live fleet health by connection state'**
  String get liveFleetHealth;

  /// No description provided for @alertsByType.
  ///
  /// In en, this message translates to:
  /// **'Alerts by Type'**
  String get alertsByType;

  /// No description provided for @alertBreakdownAcrossThePlatform.
  ///
  /// In en, this message translates to:
  /// **'Alert breakdown across the platform'**
  String get alertBreakdownAcrossThePlatform;

  /// No description provided for @locationUpdatesLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Location update volume over the last 7 days'**
  String get locationUpdatesLast7Days;

  /// No description provided for @noAggregatedLocationData.
  ///
  /// In en, this message translates to:
  /// **'No aggregated location data available'**
  String get noAggregatedLocationData;

  /// No description provided for @allAccessibleSafeZones.
  ///
  /// In en, this message translates to:
  /// **'All accessible safe zones'**
  String get allAccessibleSafeZones;

  /// No description provided for @todayLocationUpdates.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Location Updates'**
  String get todayLocationUpdates;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days'**
  String get last7Days;

  /// No description provided for @geofenceBreachesToday.
  ///
  /// In en, this message translates to:
  /// **'Geofence Breaches Today'**
  String get geofenceBreachesToday;

  /// No description provided for @mapUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Map unavailable'**
  String get mapUnavailableTitle;

  /// No description provided for @mapUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Google Maps is not ready in this browser right now. Check the web Maps script and API key configuration.'**
  String get mapUnavailableMessage;

  /// No description provided for @noLiveLocationAvailableForChild.
  ///
  /// In en, this message translates to:
  /// **'No live location available for this child'**
  String get noLiveLocationAvailableForChild;

  /// No description provided for @mapAppearsWhenGpsAvailable.
  ///
  /// In en, this message translates to:
  /// **'The map will appear when the linked device sends valid GPS data.'**
  String get mapAppearsWhenGpsAvailable;

  /// No description provided for @noLiveLocationOrSafeZoneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No live location or safe zone available'**
  String get noLiveLocationOrSafeZoneAvailable;

  /// No description provided for @addChildToStartTrackingAndSafeZones.
  ///
  /// In en, this message translates to:
  /// **'Add a child to start live tracking and safe zone monitoring.'**
  String get addChildToStartTrackingAndSafeZones;

  /// No description provided for @mapAppearsWhenLiveDataOrSafeZoneSaved.
  ///
  /// In en, this message translates to:
  /// **'The map will appear once the child sends live data or a safe zone is saved.'**
  String get mapAppearsWhenLiveDataOrSafeZoneSaved;

  /// No description provided for @childMapTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The child map is temporarily unavailable.'**
  String get childMapTemporarilyUnavailable;

  /// No description provided for @mapMode.
  ///
  /// In en, this message translates to:
  /// **'Map mode'**
  String get mapMode;

  /// No description provided for @mapTypeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get mapTypeNormal;

  /// No description provided for @mapTypeSatellite.
  ///
  /// In en, this message translates to:
  /// **'Satellite'**
  String get mapTypeSatellite;

  /// No description provided for @mapTypeTerrain.
  ///
  /// In en, this message translates to:
  /// **'Terrain'**
  String get mapTypeTerrain;

  /// No description provided for @mapTypeDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get mapTypeDefault;

  /// No description provided for @mapTypeThreeDimensionalLike.
  ///
  /// In en, this message translates to:
  /// **'3D-like'**
  String get mapTypeThreeDimensionalLike;

  /// No description provided for @insideSafeZoneNamed.
  ///
  /// In en, this message translates to:
  /// **'Inside {name}'**
  String insideSafeZoneNamed(Object name);

  /// No description provided for @outsideByDistance.
  ///
  /// In en, this message translates to:
  /// **'Outside by {distance}'**
  String outsideByDistance(Object distance);

  /// No description provided for @outsideSafeZones.
  ///
  /// In en, this message translates to:
  /// **'Outside safe zones'**
  String get outsideSafeZones;

  /// No description provided for @noLiveData.
  ///
  /// In en, this message translates to:
  /// **'No live data'**
  String get noLiveData;

  /// No description provided for @moving.
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get moving;

  /// No description provided for @stationary.
  ///
  /// In en, this message translates to:
  /// **'Stationary'**
  String get stationary;

  /// No description provided for @insideSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Inside safe zone'**
  String get insideSafeZone;

  /// No description provided for @outsideSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Outside safe zone'**
  String get outsideSafeZone;

  /// No description provided for @changeMapStyle.
  ///
  /// In en, this message translates to:
  /// **'Change map style'**
  String get changeMapStyle;

  /// No description provided for @savedCenterHint.
  ///
  /// In en, this message translates to:
  /// **'Saved center. Tap the map or use a location action, then save to change it.'**
  String get savedCenterHint;

  /// No description provided for @previewCenterHint.
  ///
  /// In en, this message translates to:
  /// **'Preview only. Tap the map or use a location action to set the center before saving.'**
  String get previewCenterHint;

  /// No description provided for @chooseNewCenterOrKeepSaved.
  ///
  /// In en, this message translates to:
  /// **'Choose a new center and save, or keep the existing saved center.'**
  String get chooseNewCenterOrKeepSaved;

  /// No description provided for @previousSavedLocation.
  ///
  /// In en, this message translates to:
  /// **'Previous saved location'**
  String get previousSavedLocation;

  /// No description provided for @currentLiveLocation.
  ///
  /// In en, this message translates to:
  /// **'Current live location'**
  String get currentLiveLocation;

  /// No description provided for @customLocationFromMap.
  ///
  /// In en, this message translates to:
  /// **'Custom location from map'**
  String get customLocationFromMap;

  /// No description provided for @previewingSavedLocationInstructions.
  ///
  /// In en, this message translates to:
  /// **'Previewing a saved location. Tap the map, drag the marker, or confirm a location action before saving a new center.'**
  String get previewingSavedLocationInstructions;

  /// No description provided for @previewingLiveLocationInstructions.
  ///
  /// In en, this message translates to:
  /// **'Previewing the child\'s current live location. Use the action button or tap the map to set a new center before saving.'**
  String get previewingLiveLocationInstructions;

  /// No description provided for @pendingCenterChange.
  ///
  /// In en, this message translates to:
  /// **'Pending change: save to update the safe zone center.'**
  String get pendingCenterChange;

  /// No description provided for @savedCenterLoaded.
  ///
  /// In en, this message translates to:
  /// **'Saved center loaded from the database.'**
  String get savedCenterLoaded;

  /// No description provided for @previewOnlyChooseLocation.
  ///
  /// In en, this message translates to:
  /// **'Preview only: choose this location explicitly, then save to keep it.'**
  String get previewOnlyChooseLocation;

  /// No description provided for @noCenterSelectedYet.
  ///
  /// In en, this message translates to:
  /// **'No center selected yet.'**
  String get noCenterSelectedYet;

  /// No description provided for @unknownTime.
  ///
  /// In en, this message translates to:
  /// **'Unknown time'**
  String get unknownTime;

  /// No description provided for @safeZoneCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Safe zone center'**
  String get safeZoneCenterTitle;

  /// No description provided for @noPreviousSavedLocations.
  ///
  /// In en, this message translates to:
  /// **'No previous saved locations are available for this child yet.'**
  String get noPreviousSavedLocations;

  /// No description provided for @refreshSavedLocations.
  ///
  /// In en, this message translates to:
  /// **'Refresh saved locations'**
  String get refreshSavedLocations;

  /// No description provided for @savedLocations.
  ///
  /// In en, this message translates to:
  /// **'Saved locations'**
  String get savedLocations;

  /// No description provided for @useSelectedSavedLocation.
  ///
  /// In en, this message translates to:
  /// **'Use selected saved location'**
  String get useSelectedSavedLocation;

  /// No description provided for @savedLocationPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Picking from this list only previews the location. The center changes after you press the button above and then save.'**
  String get savedLocationPreviewHint;

  /// No description provided for @useCurrentLiveLocation.
  ///
  /// In en, this message translates to:
  /// **'Use current live location'**
  String get useCurrentLiveLocation;

  /// No description provided for @latestLiveUpdateUseButton.
  ///
  /// In en, this message translates to:
  /// **'Latest live update: {time}. Use the button above if you want to set it as the center.'**
  String latestLiveUpdateUseButton(Object time);

  /// No description provided for @liveLocationPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'This shows the latest live location for preview. It only becomes the safe zone center after you choose it and save.'**
  String get liveLocationPreviewHint;

  /// No description provided for @customLocationPanelHint.
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere on the map or drag the marker to place the safe zone center exactly where you want it. The saved center stays unchanged until you press Save or Update.'**
  String get customLocationPanelHint;

  /// No description provided for @chooseCenterToPreviewSafeZone.
  ///
  /// In en, this message translates to:
  /// **'Choose a live, saved, or custom center to preview the safe zone on the map.'**
  String get chooseCenterToPreviewSafeZone;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa', 'ps'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
    case 'ps':
      return AppLocalizationsPs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
