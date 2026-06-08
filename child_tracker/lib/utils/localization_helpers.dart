import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

extension AppLocalizationsExtra on AppLocalizations {
  bool get _isFa => localeName.startsWith('fa');
  bool get _isPs => localeName.startsWith('ps');

  String get mapUnavailableTitle =>
      _isFa ? 'نقشه در دسترس نیست' : _isPs ? 'نقشه شتون نه لري' : 'Map unavailable';
  String get mapUnavailableMessage => _isFa
      ? 'Google Maps در این مرورگر در حال حاضر آماده نیست. تنظیمات اسکریپت و API key نقشه وب را بررسی کنید.'
      : _isPs
          ? 'Google Maps اوس په دې براوزر کې چمتو نه دی. د وېب نقشې سکرېپټ او API key امستنې وګورئ.'
          : 'Google Maps is not ready in this browser right now. Check the web Maps script and API key configuration.';
  String get noLiveLocationAvailableForChild => _isFa
      ? 'برای این کودک موقعیت زنده موجود نیست'
      : _isPs
          ? 'د دې ماشوم لپاره ژوندی موقعیت نشته'
          : 'No live location available for this child';
  String get mapAppearsWhenGpsAvailable => _isFa
      ? 'نقشه وقتی نمایش داده می‌شود که دستگاه متصل داده GPS معتبر ارسال کند.'
      : _isPs
          ? 'نقشه هغه وخت ښکاري کله چې تړلې وسیله سم GPS معلومات واستوي.'
          : 'The map will appear when the linked device sends valid GPS data.';
  String get noLiveLocationOrSafeZoneAvailable => _isFa
      ? 'هیچ موقعیت زنده یا منطقه امنی موجود نیست'
      : _isPs
          ? 'ژوندی موقعیت یا خوندي سیمه نشته'
          : 'No live location or safe zone available';
  String get addChildToStartTrackingAndSafeZones => _isFa
      ? 'برای شروع ردیابی زنده و پایش مناطق امن یک کودک اضافه کنید.'
      : _isPs
          ? 'د ژوندۍ څارنې او خوندي سیمو د څار پیل لپاره یو ماشوم اضافه کړئ.'
          : 'Add a child to start live tracking and safe zone monitoring.';
  String get mapAppearsWhenLiveDataOrSafeZoneSaved => _isFa
      ? 'نقشه زمانی نمایش داده می‌شود که کودک داده زنده ارسال کند یا یک منطقه امنی ذخیره شود.'
      : _isPs
          ? 'نقشه هغه وخت ښکاري کله چې ماشوم ژوندی معلومات واستوي یا خوندي سیمه خوندي شي.'
          : 'The map will appear once the child sends live data or a safe zone is saved.';
  String get childMapTemporarilyUnavailable => _isFa
      ? 'نقشه کودک موقتاً در دسترس نیست.'
      : _isPs
          ? 'د ماشوم نقشه لنډمهاله شتون نه لري.'
          : 'The child map is temporarily unavailable.';
  String get mapMode => _isFa ? 'حالت نقشه' : _isPs ? 'د نقشې حالت' : 'Map mode';
  String get mapTypeNormal => _isFa ? 'عادی' : _isPs ? 'عادي' : 'Normal';
  String get mapTypeSatellite => _isFa ? 'ماهواره‌ای' : _isPs ? 'سپوږمکۍ' : 'Satellite';
  String get mapTypeTerrain => _isFa ? 'عوارض' : _isPs ? 'ځمکنی' : 'Terrain';
  String get mapTypeDefault => _isFa ? 'پیش‌فرض' : _isPs ? 'اصلي' : 'Default';
  String get mapTypeThreeDimensionalLike =>
      _isFa ? 'شبیه ۳ بعدی' : _isPs ? '۳ بعدي ته ورته' : '3D-like';
  String insideSafeZoneNamed(String name) =>
      _isFa ? 'داخل $name' : _isPs ? 'د $name دننه' : 'Inside $name';
  String outsideByDistance(String distance) =>
      _isFa ? 'به اندازه $distance بیرون' : _isPs ? 'د $distance په اندازه بهر' : 'Outside by $distance';
  String get outsideSafeZones =>
      _isFa ? 'بیرون از مناطق امن' : _isPs ? 'له خوندي سیمو بهر' : 'Outside safe zones';
  String get noLiveData => _isFa ? 'داده زنده‌ای موجود نیست' : _isPs ? 'ژوندی معلومات نشته' : 'No live data';
  String get moving => _isFa ? 'در حال حرکت' : _isPs ? 'په خوځښت کې' : 'Moving';
  String get stationary => _isFa ? 'ثابت' : _isPs ? 'ولاړ' : 'Stationary';
  String get insideSafeZone =>
      _isFa ? 'داخل منطقه امن' : _isPs ? 'د خوندي سیمې دننه' : 'Inside safe zone';
  String get outsideSafeZone =>
      _isFa ? 'بیرون منطقه امن' : _isPs ? 'له خوندي سیمې بهر' : 'Outside safe zone';
  String get changeMapStyle =>
      _isFa ? 'تغییر سبک نقشه' : _isPs ? 'د نقشې بڼه بدله کړئ' : 'Change map style';
  String get savedCenterHint => _isFa
      ? 'مرکز ذخیره‌شده. روی نقشه ضربه بزنید یا از یک اقدام مکان استفاده کنید، سپس برای تغییر آن ذخیره کنید.'
      : _isPs
          ? 'خوندي شوی مرکز. په نقشه ټک وکړئ یا د ځای یو عمل وکاروئ، بیا یې د بدلولو لپاره خوندي کړئ.'
          : 'Saved center. Tap the map or use a location action, then save to change it.';
  String get previewCenterHint => _isFa
      ? 'فقط پیش‌نمایش. پیش از ذخیره روی نقشه ضربه بزنید یا از یک اقدام مکان برای تنظیم مرکز استفاده کنید.'
      : _isPs
          ? 'یوازې مخکتنه. د خوندي کولو مخکې په نقشه ټک وکړئ یا د مرکز ټاکلو لپاره د ځای یو عمل وکاروئ.'
          : 'Preview only. Tap the map or use a location action to set the center before saving.';
  String get chooseNewCenterOrKeepSaved => _isFa
      ? 'یک مرکز جدید انتخاب و ذخیره کنید، یا مرکز ذخیره‌شده فعلی را نگه دارید.'
      : _isPs
          ? 'یو نوی مرکز وټاکئ او خوندي یې کړئ، یا اوسنی خوندي شوی مرکز همداسې پرېږدئ.'
          : 'Choose a new center and save, or keep the existing saved center.';
  String get previousSavedLocation => _isFa
      ? 'موقعیت ذخیره‌شده قبلی'
      : _isPs
          ? 'مخکینی خوندي شوی موقعیت'
          : 'Previous saved location';
  String get currentLiveLocation =>
      _isFa ? 'موقعیت زنده کنونی' : _isPs ? 'اوسنی ژوندی موقعیت' : 'Current live location';
  String get customLocationFromMap => _isFa
      ? 'موقعیت سفارشی از نقشه'
      : _isPs
          ? 'له نقشې څخه ځانګړی موقعیت'
          : 'Custom location from map';
  String get previewingSavedLocationInstructions => _isFa
      ? 'در حال پیش‌نمایش یک موقعیت ذخیره‌شده. روی نقشه ضربه بزنید، نشانگر را بکشید، یا پیش از ذخیره کردن یک اقدام مکان را تایید کنید.'
      : _isPs
          ? 'یو خوندي شوی موقعیت مخکتنه کېږي. په نقشه ټک وکړئ، نښه راکاږئ، یا د خوندي کولو مخکې د ځای عمل تایید کړئ.'
          : 'Previewing a saved location. Tap the map, drag the marker, or confirm a location action before saving a new center.';
  String get previewingLiveLocationInstructions => _isFa
      ? 'در حال پیش‌نمایش موقعیت زنده کنونی کودک. برای تنظیم یک مرکز جدید پیش از ذخیره از دکمه اقدام یا ضربه روی نقشه استفاده کنید.'
      : _isPs
          ? 'د ماشوم اوسنی ژوندی موقعیت مخکتنه کېږي. د نوي مرکز د ټاکلو لپاره د عمل تڼۍ یا پر نقشه ټک کاروئ.'
          : "Previewing the child's current live location. Use the action button or tap the map to set a new center before saving.";
  String get pendingCenterChange => _isFa
      ? 'تغییر در انتظار: برای به‌روزرسانی مرکز منطقه امن ذخیره کنید.'
      : _isPs
          ? 'بدلون انتظار باسي: د خوندي سیمې مرکز د نوي کولو لپاره خوندي یې کړئ.'
          : 'Pending change: save to update the safe zone center.';
  String get savedCenterLoaded => _isFa
      ? 'مرکز ذخیره‌شده از پایگاه داده بارگیری شد.'
      : _isPs
          ? 'خوندي شوی مرکز له ډیټابېس څخه پورته شو.'
          : 'Saved center loaded from the database.';
  String get previewOnlyChooseLocation => _isFa
      ? 'فقط پیش‌نمایش: این مکان را به‌صورت صریح انتخاب کنید، سپس برای نگه داشتن آن ذخیره کنید.'
      : _isPs
          ? 'یوازې مخکتنه: دا ځای په څرګنده وټاکئ، بیا یې د ساتلو لپاره خوندي کړئ.'
          : 'Preview only: choose this location explicitly, then save to keep it.';
  String get noCenterSelectedYet => _isFa
      ? 'هنوز هیچ مرکزی انتخاب نشده است.'
      : _isPs
          ? 'لا تر اوسه کوم مرکز نه دی ټاکل شوی.'
          : 'No center selected yet.';
  String get unknownTime => _isFa ? 'زمان نامشخص' : _isPs ? 'نامعلوم وخت' : 'Unknown time';
  String get safeZoneCenterTitle =>
      _isFa ? 'مرکز منطقه امن' : _isPs ? 'د خوندي سیمې مرکز' : 'Safe zone center';
  String get noPreviousSavedLocations => _isFa
      ? 'هنوز هیچ موقعیت ذخیره‌شده قبلی برای این کودک موجود نیست.'
      : _isPs
          ? 'لا تر اوسه د دې ماشوم لپاره کوم مخکینی خوندي شوی موقعیت نشته.'
          : 'No previous saved locations are available for this child yet.';
  String get refreshSavedLocations =>
      _isFa ? 'بازنگری موقعیت‌های ذخیره‌شده' : _isPs ? 'خوندي شوي موقعیتونه تازه کړئ' : 'Refresh saved locations';
  String get savedLocations =>
      _isFa ? 'موقعیت‌های ذخیره‌شده' : _isPs ? 'خوندي شوي موقعیتونه' : 'Saved locations';
  String get useSelectedSavedLocation => _isFa
      ? 'از موقعیت ذخیره‌شده انتخاب‌شده استفاده کنید'
      : _isPs
          ? 'ټاکل شوی خوندي شوی موقعیت وکاروئ'
          : 'Use selected saved location';
  String get savedLocationPreviewHint => _isFa
      ? 'انتخاب از این فهرست فقط مکان را پیش‌نمایش می‌کند. مرکز پس از فشردن دکمه بالا و سپس ذخیره تغییر می‌کند.'
      : _isPs
          ? 'له دې لست څخه ټاکل یوازې ځای مخکتنه کوي. مرکز هغه وخت بدلېږي چې پورته تڼۍ وکاروئ او بیا خوندي کړئ.'
          : 'Picking from this list only previews the location. The center changes after you press the button above and then save.';
  String get useCurrentLiveLocation => _isFa
      ? 'از موقعیت زنده کنونی استفاده کنید'
      : _isPs
          ? 'اوسنی ژوندی موقعیت وکاروئ'
          : 'Use current live location';
  String latestLiveUpdateUseButton(String time) => _isFa
      ? 'آخرین به‌روزرسانی زنده: $time. اگر می‌خواهید آن را به‌عنوان مرکز تنظیم کنید از دکمه بالا استفاده کنید.'
      : _isPs
          ? 'وروستی ژوندی تازه کول: $time. که غواړئ دا د مرکز په توګه وټاکئ، پورته تڼۍ وکاروئ.'
          : 'Latest live update: $time. Use the button above if you want to set it as the center.';
  String get liveLocationPreviewHint => _isFa
      ? 'این بخش آخرین موقعیت زنده را برای پیش‌نمایش نشان می‌دهد. تنها پس از انتخاب آن و ذخیره کردن، به مرکز منطقه امن تبدیل می‌شود.'
      : _isPs
          ? 'دا برخه د مخکتنې لپاره وروستی ژوندی موقعیت ښيي. دا یوازې هغه وخت د خوندي سیمې مرکز ګرځي چې یې وټاکئ او خوندي یې کړئ.'
          : 'This shows the latest live location for preview. It only becomes the safe zone center after you choose it and save.';
  String get customLocationPanelHint => _isFa
      ? 'در هر جای نقشه ضربه بزنید یا نشانگر را بکشید تا مرکز منطقه امن را دقیقاً همان جایی که می‌خواهید قرار دهید. مرکز ذخیره‌شده تا زمانی که ذخیره یا به‌روزرسانی را فشار ندهید تغییر نمی‌کند.'
      : _isPs
          ? 'د نقشې پر هر ځای ټک وکړئ یا نښه راکش کړئ تر څو د خوندي سیمې مرکز په دقیق ډول هغه ځای کې کېږدئ چې غواړئ. خوندي شوی مرکز تر هغه نه بدلېږي څو Save یا Update ونه ټکوئ.'
          : 'Tap anywhere on the map or drag the marker to place the safe zone center exactly where you want it. The saved center stays unchanged until you press Save or Update.';
  String get chooseCenterToPreviewSafeZone => _isFa
      ? 'یک مرکز زنده، ذخیره‌شده یا سفارشی انتخاب کنید تا پیش‌نمایش منطقه امن را روی نقشه ببینید.'
      : _isPs
          ? 'یو ژوندی، خوندي شوی، یا ځانګړی مرکز وټاکئ تر څو په نقشه کې د خوندي سیمې مخکتنه ووینئ.'
          : 'Choose a live, saved, or custom center to preview the safe zone on the map.';
}

String localizeErrorMessage(AppLocalizations l10n, Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  return localizeRawMessage(l10n, raw);
}

String localizeRawMessage(AppLocalizations l10n, String raw) {
  final message = raw.trim();
  if (message.isEmpty) {
    return l10n.error;
  }

  const exactMessages = <String, String>{
    'User not found': 'userNotFound',
    'Admin not found': 'adminNotFound',
    'Email and password are required': 'emailPasswordRequired',
    'Invalid credentials': 'invalidCredentials',
    'Invalid admin credentials': 'invalidCredentials',
    'Account is blocked': 'accountBlocked',
    'Email not found': 'emailNotFound',
    'OTP expired': 'otpExpired',
    'Invalid OTP': 'invalidOtp',
    'Invalid request': 'invalidRequest',
    'Alert not found': 'alertNotFound',
    'Login failed': 'loginFailed',
    'Registration failed': 'registrationFailed',
    'Child is in danger!': 'sos',
    'Child is in danger': 'sos',
  };

  final exactKey = exactMessages[message];
  if (exactKey != null) {
    return _localizedGetter(l10n, exactKey);
  }

  if (message.startsWith('Request timed out')) {
    return l10n.requestTimedOut;
  }

  if (message.startsWith('Unable to reach backend server')) {
    return l10n.backendUnavailable;
  }

  if (message.startsWith('Failed to get alerts')) {
    return l10n.failedToLoadAlerts;
  }

  if (message.startsWith('Failed to request password reset')) {
    return l10n.failedToSendOtp;
  }

  if (message.startsWith('Failed to reset password')) {
    return l10n.failedToResetPassword;
  }

  if (message.startsWith('Failed to get system logs')) {
    return l10n.failedToLoadSystemLogs;
  }

  if (message.startsWith('Failed to get devices')) {
    return l10n.failedToLoadDevices;
  }

  if (message.startsWith('Failed to get children')) {
    return l10n.failedToLoadChildren;
  }

  if (message.startsWith('Failed to get users')) {
    return l10n.failedToLoadUsers;
  }

  if (message.startsWith('Failed to get admin profile') ||
      message.startsWith('Failed to get profile')) {
    return l10n.failedToLoadProfile;
  }

  if (message.startsWith('Failed to update profile') ||
      message.startsWith('Failed to update admin profile')) {
    return l10n.failedToUpdateProfile;
  }

  if (message == 'Current password is incorrect') {
    return l10n.invalidCredentials;
  }

  if (message == 'New password must be at least 6 characters') {
    return l10n.passwordMinSix;
  }

  if (message == 'Passwords do not match') {
    return l10n.passwordsDoNotMatch;
  }

  if (message.startsWith('currentPassword') && message.contains('required')) {
    return l10n.passwordRequired;
  }

  if (message.startsWith('Failed to delete alert')) {
    return l10n.failedToDeleteAlert;
  }

  if (message.startsWith('Failed to delete system log')) {
    return l10n.failedToDeleteLog;
  }

  if (message.startsWith('Failed to create safe zone')) {
    return l10n.failedToCreateSafeZone;
  }

  if (message.startsWith('Failed to update safe zone')) {
    return l10n.failedToUpdateSafeZone;
  }

  if (message
      .startsWith('Emergency Alert: SOS button triggered from child device')) {
    return l10n.sos;
  }

  if (message.startsWith('Child out of Safe Zone')) {
    return l10n.childOutOfSafeZone;
  }

  if (message.startsWith('Safe Zone was exited at')) {
    return l10n.childOutOfSafeZone;
  }

  if (message.startsWith('Your child returned to the safe zone at')) {
    return l10n.childBackInSafeZone;
  }

  if (message.startsWith('Your child returned to the configured safe zone')) {
    return l10n.childBackInSafeZone;
  }

  if (message
      .startsWith('Your child has returned to the configured safe zone')) {
    return l10n.childBackInSafeZone;
  }

  if (message.startsWith('Low battery alert! Battery level:')) {
    final level = message.split(':').last.trim();
    return '${l10n.lowBattery}: $level';
  }

  if (message == 'Device has been turned off!') {
    return l10n.deviceOffline;
  }

  if (message == 'Device is now online!') {
    return l10n.deviceOnline;
  }

  if (message
      .startsWith('Device disconnected automatically after no updates')) {
    return l10n.deviceOffline;
  }

  if (message.startsWith("Your child's device disconnected after no updates")) {
    return l10n.deviceOffline;
  }

  if (message == 'Device reconnected automatically.') {
    return l10n.deviceOnline;
  }

  if (message == "Your child's device is online again.") {
    return l10n.deviceOnline;
  }

  return message;
}

String localizeStatusLabel(AppLocalizations l10n, String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'active':
      return l10n.active;
    case 'blocked':
      return l10n.blocked;
    case 'online':
      return l10n.online;
    case 'delayed':
    case 'weak_connection':
      return l10n.deviceOffline;
    case 'offline':
    case 'disconnected':
      return l10n.offline;
    case 'no_data':
    case 'no_recent_data':
    case 'missing_live_tracking':
      return l10n.noData;
    default:
      return l10n.unknown;
  }
}

String localizeRoleLabel(AppLocalizations l10n, String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'admin':
      return l10n.admin;
    case 'user':
      return l10n.user;
    default:
      return l10n.unknown;
  }
}

String localizeAlertTypeLabel(AppLocalizations l10n, String? value) {
  switch ((value ?? '').trim().toUpperCase()) {
    case 'SOS':
      return l10n.sos;
    case 'LOCATION_UPDATE':
      return l10n.location;
    case 'OUT_ZONE':
    case 'ZONE_EXIT':
    case 'SAFE_ZONE_EXIT':
      return l10n.childOutOfSafeZone;
    case 'IN_ZONE':
    case 'ZONE_ENTER':
    case 'ZONE_ENTRY':
    case 'SAFE_ZONE_ENTER':
      return l10n.childBackInSafeZone;
    case 'SAFE_ZONE':
      return l10n.safeZone;
    case 'LOW_BATTERY':
      return l10n.lowBattery;
    case 'DEVICE_OFF':
    case 'DEVICE_OFFLINE':
    case 'DEVICE_DISCONNECTED':
      return l10n.deviceOffline;
    case 'DEVICE_ONLINE':
    case 'DEVICE_RECONNECTED':
      return l10n.deviceOnline;
    default:
      return (value ?? '').trim().isEmpty ? l10n.unknown : value!.toString();
  }
}

String _localizedGetter(AppLocalizations l10n, String key) {
  switch (key) {
    case 'userNotFound':
      return l10n.userNotFound;
    case 'adminNotFound':
      return l10n.adminNotFound;
    case 'emailPasswordRequired':
      return l10n.emailPasswordRequired;
    case 'invalidCredentials':
      return l10n.invalidCredentials;
    case 'accountBlocked':
      return l10n.accountBlocked;
    case 'emailNotFound':
      return l10n.emailNotFound;
    case 'otpExpired':
      return l10n.otpExpired;
    case 'invalidOtp':
      return l10n.invalidOtp;
    case 'invalidRequest':
      return l10n.invalidRequest;
    case 'alertNotFound':
      return l10n.alertNotFound;
    case 'loginFailed':
      return l10n.loginFailed;
    case 'registrationFailed':
      return l10n.registrationFailed;
    case 'sos':
      return l10n.sos;
    default:
      return l10n.error;
  }
}
